#!perl
use strict;
use warnings;
use Test::More;
use IO::CaptureOutput qw(qxy);
use POSIX qw(WIFEXITED);


# The sox version is printed in the test suite (rather than in Build.PL),
# because the CPAN Reporters only show the test output.

my $soxbackend = 'Audio::Extract::PCM::Backend::SoX';
unless (eval "use $soxbackend; 1") {
    die unless $@ =~ m{^$soxbackend - trynext$}m;

    warn "You don't seem to have sox installed.  Don't be bothered, it's only one backend of many.\n";
    plan skip_all => 'no sox';
}

my $soxversion = $soxbackend->get_sox_version();
diag("SoX version $soxversion found.");

my ($help, undef, $status) = qxy('sox', '-h');
die "couldn't run sox -h" unless WIFEXITED($status);

unless ($help =~ /SUPPORTED FILE FORMATS: .*\b(?:ogg|vorbis)\b/i) {
    plan skip_all => 'your sox has no ogg';
}

plan tests => 5;

require Audio::Extract::PCM;
my $extractor = Audio::Extract::PCM->new('t/sine.ogg', backend => 'SoX');
ok($extractor->pcm(undef, undef, undef));
is($extractor->format->freq, 44100);
is($extractor->format->samplesize, 2);
is($extractor->format->channels, 2);
is($extractor->format->duration, 10);
