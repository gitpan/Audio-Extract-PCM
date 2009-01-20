#!perl
use strict;
use warnings;
use Test::More;
use Audio::Extract::PCM;

unless (eval 'use Audio::Mad; 1') {
    plan skip_all => 'Audio::Mad not installed';
}

plan tests => 6;

diag('Audio::Mad version ' . Audio::Mad->VERSION);

my $extractor = Audio::Extract::PCM->new('t/sine.mp3', backend => 'Mad');

$extractor->open(undef, undef, undef);
is($extractor->format->freq,       44100);
is($extractor->format->samplesize, 2);
is($extractor->format->channels,   2);
is($extractor->format->duration,   undef);

my $l = $extractor->read(my $buf, bytes => 4096);
cmp_ok($l, '>=', 4096);
is(length($buf), $l);
