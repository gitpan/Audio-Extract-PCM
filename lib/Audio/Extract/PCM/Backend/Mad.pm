package Audio::Extract::PCM::Backend::Mad;
use strict;
use warnings;
use Carp;
use Audio::Extract::PCM::Format;

# If required stuff cannot be found, we must fail with a special error message,
# so that AEPCM knows that this is not a real error (otherwise it would show
# the error message to the user).
BEGIN {
    use Class::Inspector;

    unless (Class::Inspector->installed('Audio::Mad')) {
        die __PACKAGE__ . " - trynext\n"; # try next backend
    }
}

use Audio::Mad qw(:all);
use List::Util qw(sum);
use base qw(Audio::Extract::PCM::Backend);

my $use_mmap;
BEGIN {
    local $@;
    local $SIG{__DIE__};
    $use_mmap = eval 'use Sys::Mmap::Simple qw(map_handle); 1';
}

__PACKAGE__->mk_accessors(qw(stream frame synth timer resample dither samples_pending));


=head1 NAME

Audio::Extract::PCM::Backend::Mad - mad backend for audio extraction

=head1 SYNOPSIS

This module makes L<Audio::Extract::PCM> capable to use the libmad library
(specifically L<Audio::Mad>) for audio extraction.

=head2 Memory usage

Unless L<Sys::Mmap::Simple> is available, the MP3 encoded data will be read
into memory completely.  This is a few megabytes for typical music files, but
may be some hundred MB or more for radio broadcasts, music albums or whatever
strange applications you find for this module.

If L<Sys::MMap::Simple> is installed, it will be used automatically.

=head1 WARNING

L<Audio::Mad> version 0.6 from 2003 has problems.  Consider applying the patch
from L<http://rt.cpan.org/Public/Bug/Display.html?id=42338> until L<Audio::Mad>
releases a fixed version.

=head1 METHODS

=head2 new

See L<Audio::Extract::PCM::Backend/new>.

=cut


sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    $this->stream(Audio::Mad::Stream->new());
    $this->frame(Audio::Mad::Frame->new());
    $this->synth(Audio::Mad::Synth->new());
    $this->timer(Audio::Mad::Timer->new());
    $this->samples_pending([]);

    return $this;
}


my @dithervalues = (
    {
        value => MAD_DITHER_S8,
        samplesize => 1,
        signed => 1,
    },
    {
        value => MAD_DITHER_U8,
        samplesize => 1,
        signed => 0,
    },
    {
        value => MAD_DITHER_S24_LE,
        samplesize => 3,
        endian => 'little',
        signed => 1,
    },
    {
        value => MAD_DITHER_S24_BE,
        samplesize => 3,
        endian => 'big',
        signed => 1,
    },
    {
        value => MAD_DITHER_S32_LE,
        samplesize => 4,
        endian => 'little',
        signed => 1,
    },
    {
        value => MAD_DITHER_S32_BE,
        samplesize => 4,
        endian => 'big',
        signed => 1,
    },
    {
        value => MAD_DITHER_S16_LE,
        samplesize => 2,
        endian => 'little',
        signed => 1,
    },
    {
        value => MAD_DITHER_S16_BE,
        samplesize => 2,
        endian => 'big',
        signed => 1,
    },
);


=head2 open_back

See L<Audio::Extract::PCM::Backend/open>.

=cut

sub open_back {
    my $this = shift;

    my ($format) = @_;

    my ($dithervalue, $endformat) = $format->findvalue(\@dithervalues);
    if ($dithervalue) {
        $this->dither(Audio::Mad::Dither->new($dithervalue));
    } else {
        return 'trynext'; # try next backend
    }

    # We need to find out the sample rate of the input stream.  To do that, we
    # must decode the first frame.

    my $fn = $this->filename;
    croak 'no filename given' unless defined $fn;

    open my $fh, '<:raw', $fn or do {
        $this->error("open: $fn: $!");
        return ();
    };

    # The buffer should stay in memory while $this exists:  Audio::Mad does not
    # care about garbage collection.
    # Maybe this shouldn't be done in the backend: We don't want the next
    # backend to slurp the file again if we have to return 'trynext'.

    if ($use_mmap) {

        $this->{buffer} = do {
            #mmap(my $buf, 0, PROT_READ, MAP_SHARED, $fh) or die "mmap: $fn: $!";

            my $buf;

            local $@;
            local $SIG{__DIE__};
            eval {
                map_handle($buf, $fh);
            };
            if ($@) {
                # This happens e.g. for pipes
                $this->error("Could not map file ($fn): $@");
                return ();

                # Should instead slurp the file?
                # Or should we return 'trynext'?
            }

            \ $buf;
        };

        # This is only for the reference counter :)
        $this->{__fh} = $fh;

    } else {

        warn 'Install Sys::Mmap::Simple for more efficiency' unless our($have_warned_mmap)++;

        $this->{buffer} = do {

            # I try not to use a my-scalar because perl would't free the memory
            # when it goes out of scope.

            # Actually I'm not sure if this is better, but it looks complicated
            # enough.

            my %foohash = (buf => '');

            for (;;) {
                my $l = sysread($fh, $foohash{buf}, 4096, length($foohash{buf}));
                unless (defined $l) {
                    $this->error("read: $!");
                    return ();
                }
                last unless $l;
            }

            \$foohash{buf};
        };
        close $fh or die "$fh: $!";

    }

    $this->stream->buffer(${$this->{buffer}});

    # Now everything is set up for the first call to _crunch_frame, which will
    # finally provide us with the sought-after sample rate.

    $this->_crunch_frame or do {
        $this->error("could not decode file"); # XXX what about empty files?
        return ();
    };

    $endformat->combine(channels => $this->frame->NCHANNELS);
    return 'trynext' unless $format->satisfied($endformat);

    my $srcfreq = $this->frame->samplerate;
    my $freq = $format->freq || $srcfreq;

    $this->resample(Audio::Mad::Resample->new($srcfreq, $freq));

    if (2 == $this->resample->mode && $freq != $srcfreq) {
        # resampling of these values not supported

        # XXX try other accepted sampling frequencies, if there are any

        return 'trynext' if ! $format->satisfied(freq => $srcfreq);

        $freq = $srcfreq;
    }

    $endformat->combine(freq => $freq);


    return $endformat;
}


sub _resample {
    my $this = shift;
    if (2 == $this->resample->mode) {
        return @_;
    }
    return $this->resample->resample(@_);
}


# Reads a frame (or tries until one frame has been read successfully)
sub _crunch_frame {
    my $this = shift;

    while (-1 == $this->frame->decode($this->stream)) {
        if (MAD_ERROR_BUFLEN == $this->stream->error) {
            return 0;
        }
        unless ($this->stream->err_ok()) {
            $this->error("Fatal decoding error: " . $this->stream->error);
            return ();
        }

        # Don't warn for recoverable errors.  Too much noise.
        # warn "Decoding error: " . $this->stream->error;
    }

    $this->synth->synth($this->frame);
    push @{$this->samples_pending}, [$this->frame->duration, $this->synth->samples];
    return 1;
}


=head2 read

See L<Audio::Extract::PCM::Backend/read>.

=cut

sub read {
    my $this = shift;
    my $buf = \shift;
    my %args = @_;

    $$buf = '' unless $args{append};

    my $bytes_read = 0;

    for (;;) {
        while (@{$this->samples_pending}) {
            my $s = shift @{$this->samples_pending};

            my $pcm = $this->dither->dither($this->_resample(@{$s}[1..$#$s]));
            $$buf .= $pcm;
            $bytes_read += length $pcm;
        }

        if (defined $args{bytes}) {
            last if $args{bytes} <= $bytes_read;
        }

        my $crunch = $this->_crunch_frame;
        return () unless defined $crunch;
        last unless $crunch;
    }

    return $bytes_read;
}


=head2 used_versions

Returns a hashref with Audio::Mad's version as a value.

=cut

sub used_versions {
    return {
        'Audio::Mad' => Audio::Mad->VERSION,
    };
}


our $AVAILABLE = 1;
