#!perl
use strict;
use warnings;
use Test::More;


# This is in the test suite (rather than in Build.PL), because the CPAN
# Reporters only show the test output.

my $vers_output = `sox --version`;

if (defined $vers_output) {
    my ($soxver) = $vers_output =~ /v([\d.]+)/
        or die "Strange sox --version output: $vers_output\n";
    warn "SoX version $soxver found.\n";
} else {
    warn "The sox program was not found.  Don't be bothered, it's only one backend of many.";
    plan skip_all => 'no sox';
}

my $help = `sox --help`;

unless ($help =~ /SUPPORTED FILE FORMATS: .*\bogg\b/) {
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
