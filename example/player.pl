#!/usr/bin/env perl
use strict;
use warnings;
use Audio::Extract::PCM;
use SDL;
use List::Util qw(min);

# Well, this player doesn't really work because SDL uses threads for audio,
# which results in random behaviour from perl.  It probably depends on the
# system, but on my system it looks like this:
#
# The Mad Extract backend gives all kind of random errors.
#
# The Vorbis backend actually survives one piece of music.


my $fn = shift;

my $extractor = Audio::Extract::PCM->new($fn);
$extractor->open(undef, 2, undef) or die $extractor->error;
my $format = $extractor->format;

my $audiospec = SDL::NewAudioSpec($format->freq, AUDIO_S16, $format->channels, 4096);
SDL::OpenAudio($audiospec, 'callback');
SDL::FreeAudioSpec($audiospec);


my @bufs = ('', '');
my $cur = 0;


sub callback {
    my ($stream, $len) = @_;

    if (0 == length $bufs[!$cur]) {
        my $l = $extractor->read($bufs[!$cur], seconds => 1);
        warn "have read $l seconds.\n";
        warn $extractor->error unless defined $l;
        if (0 == $l) {
            warn "done soon.\n";
        } else {
            warn "not done!\n";
        }
    }
    if (0 == length $bufs[$cur]) {
        $cur = !$cur;
    }

    my $pointer = unpack('L!', pack('p', $bufs[$cur]));
    $len = min(length($bufs[$cur]), $len);
    SDL::MixAudio($stream, $pointer, $len, SDL_MIX_MAXVOLUME);
    substr($bufs[$cur], 0, $len, '');

    if (0 == length $bufs[0] && 0 == length $bufs[1]) {
        warn "done.\n";
        exit;
    }
}

SDL::PauseAudio(0);

sleep while 1;
