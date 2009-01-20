#!perl
use strict;
use warnings;
use Test::More;
use Audio::Extract::PCM;

unless (eval 'use Audio::SndFile; 1') {
    plan skip_all => 'Audio::SndFile not installed';
}

plan tests => 6;

diag('Audio::SndFile version ' . Audio::SndFile->VERSION);
diag('libsndfile version ' . Audio::SndFile::lib_version());

my $extractor = Audio::Extract::PCM->new('sine.wav', backend => 'SndFile');

$extractor->open(undef, undef, undef);
is($extractor->format->freq,       44100);
is($extractor->format->samplesize, 2);
is($extractor->format->channels,   2);
is($extractor->format->duration,   10);

is($extractor->read(my $buf, bytes => 4096), 4096);
is(length($buf), 4096);
