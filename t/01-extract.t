#!perl
use strict;
use warnings;
use Audio::Extract::PCM;
use Test::More tests => 12;
use Compress::Zlib;
use bytes;


my $wav;

for my $testsound (qw(sine quadchan)) {
    diag("Testing with sound $testsound...");

    my $wav = Compress::Zlib::memGunzip (do {
            open my $fh, '<', "t/$testsound.wav.gz" or die "t/$testsound.wav.gz: $!";
            local $/;
            <$fh>;
        });

    open my $wavfh, '>', "$testsound.wav" or die "$testsound.wav: $!";
    syswrite($wavfh, $wav) or die $!;
    close $wavfh or die $!;

    my $samples = substr($wav, index($wav, 'data')+8);
    my $freq = undef;
    my $samplesize = undef;
    my $channels = undef;

    for my $backend ('SndFile', 'SoX', 'default') {
        diag("Testing backend $backend...");

        my %backend;
        $backend{backend} = $backend unless 'default' eq $backend;

        SKIP: {
            my $extractor = Audio::Extract::PCM->new("$testsound.wav", %backend);
            my $extracted = $extractor->pcm($freq, $samplesize, $channels);
            unless ($extracted) {
                die $extractor->error unless $extractor->error =~ /no suitable backend/;

                skip "Backend $backend not available", 2;
            }

            ok($samples eq $$extracted, 'extract ok');
            diag('Tested data was '.length($samples).' bytes, extracted was '.length($$extracted));

            my $bad = Audio::Extract::PCM->new('no-such-file.wav', %backend);
            $bad->pcm($freq, $samplesize, $channels);

            my %searchstr = (
                SndFile => qr(Can't open no-such-file\.wav),
                SoX     => qr(Can't open input file)i,
            );
            $searchstr{default} = qr( $searchstr{SndFile} | $searchstr{SoX} )x;

            like($bad->error, $searchstr{$backend}, 'get backend\'s errors');
        }
    }
}
