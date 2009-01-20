#!perl
use Audio::Extract::PCM::Format;
use strict;
use warnings;
use Test::More tests => 12;


my @values = (
    {
        value => '44100 unsigned 24-bit',

        freq => 44100,
        samplesize => 3,
        signed => 0,
    },
    {
        value => '8000 16-bit little endian',

        freq => 8000,
        samplesize => 2,
        endian => 'little',
    },
);

my $format = Audio::Extract::PCM::Format->new(
    freq => 44100,
    samplesize => 3,
    signed => \[1],
);

# use Data::Dumper;
# diag(Dumper $format);

is($format->findvalue(\@values), '44100 unsigned 24-bit');

unshift @values, {
    value => '44100 signed 24-bit',
    freq => 44100,
    samplesize => 3,
    signed => 1,
};

is($format->findvalue(\@values), '44100 signed 24-bit');

my $format1_5 = Audio::Extract::PCM::Format->new(
    freq => [8000, 22050],
);
is($format1_5->findvalue(\@values), '8000 16-bit little endian');
my $format1_6 = Audio::Extract::PCM::Format->new(
    freq => [22050, 8000],
);
is($format1_6->findvalue(\@values), '8000 16-bit little endian');
my $format1_7 = Audio::Extract::PCM::Format->new(
    freq => [22050, 16000],
);
is($format1_7->findvalue(\@values), undef);

my $format2 = Audio::Extract::PCM::Format->new(
    endian => 'little',
);

is($format2->findvalue(\@values), '8000 16-bit little endian');

my $format3 = Audio::Extract::PCM::Format->new(
    endian => 'big',
);

diag ('big endian test');
ok($format3->findvalue(\@values)); # this should be _anything_

my $format4 = Audio::Extract::PCM::Format->new(
    signed => \[0],
);

is($format4->findvalue(\@values), '44100 unsigned 24-bit');

my $foundformat = [$format4->findvalue(\@values)]->[1];
is($foundformat->freq, 44100);
is($foundformat->signed, 0);
is($foundformat->samplesize, 3);

my @values2 = (
    {
        endian => 'little',
        signed => 0,
        freq   => 8000,

        value  => 'two matching, one wrong',
    },
    {
        freq   => 44100,

        value  => 'one matching, rest unspecified',
    },
    {
        endian => 'little',
        signed => 0,
        freq   => 48000,

        value  => 'two matching, one wrong (2)',
    },
);

my $format5 = Audio::Extract::PCM::Format->new(
    signed => \[0],
    freq   => \[44100],
    endian => \['little'],
);

# This should prefer the settings where there are no non-matching values
is($format5->findvalue(\@values2), 'one matching, rest unspecified', 'choosing the smaller evil');
