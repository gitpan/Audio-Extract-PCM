#!perl
use strict;
use warnings;
use Audio::Extract::PCM;
use Test::More tests => 6;
use Compress::Zlib;
use bytes;

my $wav = Compress::Zlib::memGunzip (do {
    open my $fh, '<', 't/sine.wav.gz' or die "t/sine.wav.gz: $!";
    local $/;
    <$fh>;
});

open my $wavfh, '>', 'sine.wav' or die "sine.wav: $!";
syswrite($wavfh, $wav) or die $!;
close $wavfh or die $!;

my $samples = substr($wav, 44);
my $freq = 44100;
my $samplesize = 2;
my $channels = 2;

for my $backend ('SndFile', 'SoX', 'default') {
    diag("Testing backend $backend");

    my %backend;
    $backend{backend} = $backend unless 'default' eq $backend;

    my $extractor = Audio::Extract::PCM->new('sine.wav', %backend);
    my $extracted = $extractor->pcm($freq, $samplesize, $channels)
        or die $extractor->error;

    ok($samples eq $$extracted, 'extract ok');
    diag('Tested data was '.length($samples).' bytes');

    my $bad = Audio::Extract::PCM->new('no-such-file.wav', %backend);
    $bad->pcm($freq, $samplesize, $channels);

    my %searchstr = (
        SndFile => qr(Can't open no-such-file\.wav),
        SoX     => qr(Can't open input file)i,
    );
    $searchstr{default} = qr( $searchstr{SndFile} | $searchstr{SoX} )x;

    like($bad->error, $searchstr{$backend}, 'get backend\'s errors');
}
