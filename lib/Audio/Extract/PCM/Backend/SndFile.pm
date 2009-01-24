package Audio::Extract::PCM::Backend::SndFile;
use strict;
use warnings;
use Audio::Extract::PCM::Format;
use base qw(Audio::Extract::PCM::Backend);


# If required stuff cannot be found, we must fail with a special error message,
# so that AEPCM knows that this is not a real error (otherwise it would show
# the error message to the user).
BEGIN {
    use Class::Inspector;

    unless (Class::Inspector->installed('Audio::SndFile')) {
        die __PACKAGE__ . " - trynext\n"; # try next backend
    }
}
use Audio::SndFile;

__PACKAGE__->mk_accessors(qw(_sndfile _sampletype));


use constant SHORT_SIZE => length pack('s', 0);
use constant INT_SIZE   => length pack('i', 0);


=head1 NAME

Audio::Extract::PCM::Backend::SndFile - sndfile backend for audio extraction

=head1 SYNOPSIS

This module makes L<Audio::Extract::PCM> capable to use the sndfile library
(specifically L<Audio::SndFile>) for audio extraction.

=cut


my @sample_format_vals = (
    {
        value => 'int',
        samplesize => INT_SIZE,
        signed => 1,
    },
    {
        value => 'short',
        samplesize => SHORT_SIZE,
        signed => 1,
    },
);


=head2 open_back

See L<Audio::Extract::PCM::Backend/open>.

=cut

sub open_back {
    my $this = shift;
    my ($format) = @_;

    my ($sampletype, $sample_format) = $format->findvalue(\@sample_format_vals);
    return 'trynext' unless defined $sample_format;

    my $sndfile;
    {
        local $@;
        local $SIG{__DIE__};

        $sndfile = eval { Audio::SndFile->open('<', $this->filename, endianness => 'cpu') };

        if ($@) {
            $@ =~ s#^(.*) at .*?\z#$1#s;
            $this->error("$@");
            return ();
        }
    }
    $this->_sndfile($sndfile);

    if (! defined $format->samplesize) {
        # User has no specific samplesize requests; choose a wise default

        my ($unsigned, $orig_ssize) = $sndfile->subtype() =~ /_(u?)(\d+)\z/;

        # We choose the sample size according to the file's sample size.  For
        # libsndfile's more obscure sample formats (like "ulaw" and float
        # formats, and what the heck "dwvw_16" is I don't actually care), this
        # is just heuristic.  But for usual integer pcm formats, it should be
        # fine.

        $orig_ssize++ if $unsigned;

        if (defined $orig_ssize && $orig_ssize <= 8 * SHORT_SIZE) {

            ($sampletype, $sample_format) = ('short', AEPF->new(samplesize => SHORT_SIZE));
        } else {
            ($sampletype, $sample_format) = ('int',   AEPF->new(samplesize => INT_SIZE));
        }
    }

    my $duration = $sndfile->frames() / $sndfile->samplerate();

    my $endformat = Audio::Extract::PCM::Format->new(
        channels => $sndfile->channels,
        freq     => $sndfile->samplerate,
        signed   => 1,
        duration => $duration,

        # I *believe* that read always returns native endian data, but I gotta
        # check this.  Anyway, $sndfile->endianness always returns "file", so
        # we cannot use it here.
        endian   => 'native',
        # endian   => $sndfile->endianness,
    );

    $endformat->combine($sample_format);

    $this->_sampletype($sampletype);

    return $endformat;
}


=head2 read_back

See L<Audio::Extract::PCM::Backend/read>.

=cut

sub read_back {
    my $this = shift;
    my $buf = \shift;
    my (%args) = @_;

    my $bytes = $args{bytes};
    my $format = $this->format;

    my $items = $bytes / $format->samplesize;

    $items++ until 0 == $items % $format->channels;

    my $workbuf = $args{append} ? do{\my($x)} : $buf;
    $$workbuf = '';

    my $readfunc = 'read_' . $this->_sampletype;

    my $l = $this->_sndfile->$readfunc($$workbuf, $items);
    $$buf .= $$workbuf if $args{append} && $l > 0;
    return $l * $format->samplesize;
}


=head2 used_versions

Returns versions of L<Audio::SndFile> and libsndfile in a hash reference.

=cut

sub used_versions {
    return {
        'Audio::SndFile' => Audio::SndFile->VERSION,
        'libsndfile'     => Audio::SndFile::lib_version(),
    };
}


1;


=head1 TODO

Thoroughly test this for float pcm files, especially normalization issues.

=cut
