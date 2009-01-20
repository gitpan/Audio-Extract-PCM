#!perl
use strict;
use warnings;
use Test::More;
use Audio::Extract::PCM;

unless (eval 'use Ogg::Vorbis::Decoder; 1') {
    plan skip_all => 'Ogg::Vorbis::Decoder not installed';
}

plan tests => 6;

diag('Ogg::Vorbis::Decoder version ' . Ogg::Vorbis::Decoder->VERSION);

my $extractor = Audio::Extract::PCM->new('t/sine.ogg', backend => 'Vorbis');

$extractor->open(undef, undef, undef);
is($extractor->format->freq,       44100);
is($extractor->format->samplesize, 2);
is($extractor->format->channels,   2);
is($extractor->format->duration,   10);

is($extractor->read(my $buf, bytes => 4096), 4096);
is(length($buf), 4096);