#!/usr/bin/perl
use strict;
use warnings;
use Audio::Extract::PCM;
use Getopt::Long;

# Extracts PCM data to Standard Output

GetOptions (
    'rate=i'     => \(my $rate = 44100),
    'size=i'     => \(my $samplesize = 2),
    'channels=i' => \(my $channels = 2),
) or exit 1;

my ($source) = @ARGV or die "Expected a source filename\n";

my $extractor = Audio::Extract::PCM->new($source);
my $pcm = $extractor->pcm(
    freq => $rate,
    samplesize => $samplesize,
    channels => $channels,
) or die $extractor->error() . "\n";

binmode STDOUT;
print $$pcm or die $!;
close STDOUT or die $!;
