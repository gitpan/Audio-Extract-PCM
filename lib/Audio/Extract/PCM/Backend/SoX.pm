package Audio::Extract::PCM::Backend::SoX;
use strict;
use warnings;
use Carp;
use IO::CaptureOutput qw( qxx qxy );
use base qw(Audio::Extract::PCM::Backend);
use Audio::Extract::PCM::Format;

unless (defined get_sox_version()) {
    die __PACKAGE__ . " - trynext\n"; # try next backend
}

my @bppvals = (
    {
        value => '-b',
        samplesize => 1,
    },
    {
        value => '-l',
        samplesize => 4,
    },
    {
        value => '-d',
        samplesize => 8,
    },
    {
        value => '-w',
        samplesize => 2,
    },
);
my @signvals = (
    {
        value => '-s',
        signed => 1,
    },
    {
        value => '-u',
        signed => 0,
    },
);

if (get_sox_version() && get_sox_version() > '13.0.0') {
    $_->{value} = '-' . $_->{samplesize} for @bppvals;
}

=head1 NAME

Audio::Extract::PCM::Backend::SoX - sox backend for audio extraction

=head1 METHODS

=head2 pcm_back

See L<Audio::Extract::PCM::Backend/pcm>.

=head1 SYNOPSIS

Note that this backend does not support C<read>, i.e. it only supports the
C<pcm> method, which will read all pcm data at once.

=cut

sub pcm_back {
    my $this = shift;
    my ($format) = @_;

    my $fn = $this->{filename} or croak 'No filename';

    my @param;
    my $endformat = ref($format)->new();

    if (defined $format->samplesize) {
        (my $bpp_option, $endformat) = $format->findvalue(\@bppvals)
            or return 'trynext';

        push @param, $bpp_option;
    }
    # We need either -s or -u, otherwise we cannot be sure that sox doesn't use
    # strange output formats like u-law
    my ($signoption, $signformat) = $format->findvalue(\@signvals);
    push @param, $signoption;
    $endformat->combine($signformat);

    use bytes;

    local $ENV{LC_ALL} = 'C';

    push @param, '-r'.$format->freq     if defined $format->freq;
    push @param, '-c'.$format->channels if defined $format->channels;

    my @command = ('sox', '-V3', $fn, @param, '-twav', '-');

    warn qq(Running "@command"\n") if $ENV{DEBUG};

    my ($pcm, $soxerr, $success) = qxx(@command);

    chomp $soxerr;

    # # Well, this is ugly, but that warning is annoying and does not matter to
    # # us (we strip the header anyway)
    # $soxerr =~ s/.*header will be wrong since can't seek.*\s*//;

    # Now that we use -V3, we cannot display all that stderr stuff, so the
    # above is commented out.

    unless ($success) {
        my $err;
        if ($!) {
            $err = length($soxerr) ? "$! - $soxerr" : "$!";
        } else {
            # show only the last line
            $soxerr = [$soxerr =~ /[^\n\r]+/g]->[-1] || '';

            $err = length($soxerr) ? $soxerr : "Error running sox";
        }

        undef $pcm;

        $this->error($err);
        return ();
    }

    # warn $soxerr if length $soxerr;

    # Now get the format data from stderr:

    my ($sample_size, $duration, $channels, $endian, $endfreq, $signed);

    # Older soxes had a very different format of the -V3 output.  From sox's
    # Changelog, I *assume* that it changed in 13.0.0.
    # What I actually tested is 12.17.9 and 14.0.1, for sample output see the
    # comment at the bottom of this module.


    if (get_sox_version() >= '13.0.0') {

        my %infos = (
            # Parse table
            map {
                /^(.+?)\s*:\s*(.*?)\s*$/ ? (lc $1, $2) : ()
            }
            # Find output file stanza
            grep {
                /^Output File\s*:/i .. /^\s*$/
            }
            # Split lines
            $soxerr =~ /[^\n\r]+/g
        );

        if ($ENV{DEBUG}) {
            warn "SoX stderr:\n$soxerr\n";
        }

        $sample_size = $infos{'sample size'} or die "no sample size from sox";
        $sample_size =~ s/^([0-9]+).*// or die "bad sample size from sox: $sample_size";
        $sample_size = $1 / 8;

        $duration = $infos{duration} or die "no duration from sox";
        $duration =~ /^(\d+):(\d+\.\d+) / or die "bad duration from sox: $duration";
        $duration = $1 * 60 + $2 ;

        $channels = $infos{channels} or die "no channels from sox";
        $endian = $infos{'endian type'} or die "no endianness from sox";
        $endfreq = $infos{'sample rate'} or die "no sample rate from sox";

        my $encoding = $infos{'sample encoding'};
        $signed = $encoding =~ /\bsigned\b/ ? 1 : $encoding =~ /\bunsigned\b/ ? 0
            : die "no signed from sox";

    } else {
        # sox < 13.0.0

        my ($info) = $soxerr =~ m{^(sox: Writing Wave file:.*?bits/samp)}msi;
        my ($info2) = $soxerr =~ m{^(sox: Output file .*? channels\s*$)}msi;

        ($sample_size) = $info =~ m{(\d+) bits/samp}i or die "no sample size from sox";
        $sample_size /= 8;

        ($endfreq) = $info =~ m{(\d+) samp/sec}i or die "no sample rate from sox";
        $endian = 'little'; # ?
        ($channels) = $info =~ m{(\d+) channels}i or die "no channels from sox";

        ($duration) = $soxerr =~ m{^sox: Finished writing.*?(\d+) samples}mi
            or die "no duration from sox";
        $duration /= $endfreq;

        $signed = $info2 =~ /encoding signed/ ? 1 : $info2 =~ /encoding unsigned/ ? 0
            : die "no signed from sox: $info2";
    }

    $endformat->combine(
        samplesize => $sample_size,
        duration => $duration,
        channels => $channels,
        endian => $endian,
        freq => $endfreq,
        signed => $signed,
    );

    # SoX doesn't always return what we tell it to return.
    # Quote: "sox wav: Do not support unsigned with 16-bit data.  Forcing to Signed."
    return 'trynext' unless $format->satisfied($endformat);

    $this->format($endformat);

    substr($pcm, 0, 44, ''); # strip wave header (we know the details, we specified them to sox)

    return \$pcm;
}



=head1 SUBROUTINES

=head2 get_sox_version

This will return the SoX version as a L<version> object.  The result will be
cached, i.e. if you install a new sox, this module will not recognize it until
it is reloaded or the application using it is restarted.

If no sox program is in the path or C<sox -h> outputs strange things, C<undef>
will be returned.  In the latter case, a warning will be issued.

Currently, the only internal use is to find out whether SoX is above version
13.0.0, because they renamed the C<"-b"/"-w"/"-l"/"-d"> flags to
C<"-1"/"-2"/"-4"/"-8"> by then.  Note that the old flags were still recognized
(though deprecated) until SoX 14.1.0.

=cut

{
    my $soxver;

    sub get_sox_version {
        return $soxver if defined $soxver;

        # Note: we use sox -h, not sox --version.
        # The latter doesn't work with e.g. 12.17.9 (etch)
        # Older soxes print stuff like "sox: Version 12.17.9" in the first line of sox -h,
        # newer soxes print stuff like "sox: SoX v14.0.1" instead.

        my ($vers_output, $success, $exitstatus) = qxy(qw(sox -h));

        # return undef unless $success;
        # argh, old soxes have exit status 1 for sox -h (and print to stderr;
        # rather than stdout like newer ones)
        use POSIX qw(WIFEXITED);
        return undef unless WIFEXITED($exitstatus);

        if (defined $vers_output) {
            $vers_output =~ s#[\r\n].*##s;

            ($soxver) = $vers_output =~ /(?:Version |v)(\d+\.\d+\.\d+)/
                or warn "Strange sox -h output (first line): $vers_output\n";
            return undef unless defined $soxver;
        }

        use version;
        $soxver = version->new($soxver);

        return $soxver;
    }
}


1;

# Sample -V3 output from sox:

# 12.17.9:
#
#    sox: invalid option -- 3
# (hehe, but as long as it isn't an error, why not)
#    sox: Detected file format type: ogg
#
#    sox: Input file t/sine.ogg: using sample rate 44100
#            size shorts, encoding Vorbis, 2 channels
#    sox: Do not support Vorbis with 16-bit data.  Forcing to Signed.
#    sox: Writing Wave file: Microsoft PCM format, 2 channels, 44100 samp/sec
#    sox:         176400 byte/sec, 4 block align, 16 bits/samp
#    sox: Output file sine.wav: using sample rate 44100
#            size shorts, encoding signed (2's complement), 2 channels
#    sox: Output file: comment "Processed by SoX"
#    
#    sox: Finished writing Wave file, 1764000 data bytes 441000 samples
#
# and 14.0.1:
#    sox: SoX v14.0.1
#    
#    Input File     : 't/sine.ogg'
#    Sample Size    : 16-bit (2 bytes)
#    Sample Encoding: Vorbis
#    Channels       : 2
#    Sample Rate    : 44100
#    Duration       : 00:10.00 = 441000 samples = 750 CDDA sectors
#    Endian Type    : little
#    Reverse Nibbles: no
#    Reverse Bits   : no
#    
#    sox wav: Do not support Vorbis with 16-bit data.  Forcing to Signed.
#    
#    Output File    : 'sine.wav'
#    Sample Size    : 16-bit (2 bytes)
#    Sample Encoding: signed (2's complement)
#    Channels       : 2
#    Sample Rate    : 44100
#    Duration       : 00:10.00 = 441000 samples = 750 CDDA sectors
#    Endian Type    : little
#    Reverse Nibbles: no
#    Reverse Bits   : no
#    Comment        : 'Processed by SoX'
#    
#    sox sox: effects chain: input      44100Hz 2 channels 16 bits (multi)
#    sox sox: effects chain: output     44100Hz 2 channels 16 bits (multi)


=head1 SEE ALSO

=over 8

=item *

L<http://sox.sourceforge.net/> - SoX homepage

=back
