package Audio::Extract::PCM::Backend::SoX;
use strict;
use warnings;
use Carp;
use IO::CaptureOutput qw( qxx );
use base qw(Audio::Extract::PCM::Backend);
use Audio::Extract::PCM::Format;

unless (defined get_sox_version()) {
    die __PACKAGE__ . " - trynext\n"; # try next backend
}

my @bppvals = (
    {
        value => '-w',
        samplesize => 2,
    },
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

    my $sample_size = $infos{'sample size'} or die "no sample size from sox\n";
    $sample_size =~ s/^([0-9]+).*// or die "bad sample size from sox: $sample_size\n";
    $sample_size = $1 / 8;

    my $duration = $infos{duration} or die "no duration from sox\n";
    $duration =~ /^(\d+):(\d+\.\d+) / or die "bad duration from sox: $duration\n";
    $duration = $1 * 60 + $2 ;

    my $channels = $infos{channels} or die "no channels from sox\n";
    my $endian = $infos{'endian type'} or die "no endianness from sox\n";
    my $endfreq = $infos{'sample rate'} or die "no sample rate from sox\n";

    $endformat->combine(
        samplesize => $sample_size,
        duration => $duration,
        channels => $channels,
        endian => $endian,
        freq => $endfreq,
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

If no sox program is in the path or C<sox --version> outputs strange things,
C<undef> will be returned.  In the latter case, a warning will be issued.

Currently, the only internal use is to find out whether SoX is above version
13.0.0, because they renamed the C<"-b"/"-w"/"-l"/"-d"> flags to
C<"-1"/"-2"/"-4"/"-8"> by then.  Note that the old flags were still recognized
(though deprecated) until SoX 14.1.0.

=cut

{
    my $soxver;

    sub get_sox_version {
        return $soxver if defined $soxver;

        my $vers_output = `sox --version`;

        if (defined $vers_output) {
            ($soxver) = $vers_output =~ /v(\d+\.\d+\.\d+)/
                or warn "Strange sox --version output: $vers_output\n";
        }

        use version;
        $soxver = version->new($soxver);

        return $soxver;
    }
}


1;

=head1 SEE ALSO

=over 8

=item *

L<http://sox.sourceforge.net/> - SoX homepage

=back
