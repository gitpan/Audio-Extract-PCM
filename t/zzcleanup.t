#!perl
use Test::More tests => 1;
use strict;
use warnings;

# That's why this test is named cleanup
unlink('sine.wav');

my $int = hex sprintf('%02x' x 4, map ord, qw(U N I X));
my $str = unpack('A4', pack ('L', $int));

my $endian = {
    XINU => 'little',
    UNIX => 'big',
    NUXI => 'middle, UNSUPPORTED!',
}->{$str} || 'UNKNOWN, WHOA!!!';

diag("This system has $str ($endian) endianness");

like($str, qr(UNIX|XINU)i);
