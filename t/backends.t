#!perl
use strict;
use warnings;
use Test::More;
use List::Util qw(sum);
use Audio::Extract::PCM;
use IO::CaptureOutput qw(qxy);
use POSIX qw(WIFEXITED);


my %files = (
    wav => [
    {
        filename => 'sine.wav',
        verify   => {
            samplesize => 2,
            freq       => 44100,
            channels   => 2,
            signed     => 1,
            endian     => 'little',
            duration   => 10,
        },
    },
    {
        filename => 'quadchan.wav',
        verify   => {
            samplesize => 2,
            freq       => 44100,
            channels   => 4,
            duration   => 10,
        },
        WAV_EXTENSIBLE => 1,
    },
    {
        filename => 'quadchan-wavpcm.wav',
        verify   => {
            samplesize => 2,
            freq       => 44100,
            channels   => 4,
            duration   => 10,
        },
    },
    ],
    ogg => [
    {
        filename => 't/sine.ogg',
        verify   => {
            samplesize => 2,
            freq       => 44100,
            channels   => 2,
            signed     => 1,
            endian     => 'little',
            duration   => 10,
        },
    },
    ],
    mp3 => [
    {
        filename => 't/sine.mp3',
        verify   => {
            samplesize => 2,
            freq       => 44100,
            channels   => 2,
            signed     => 1,
            endian     => 'little',
            duration   => 10,
        },
    },
    ],
);


my %tests = (
    SoX => {
        backend => 'SoX',
        types => ['wav'],
        interface => 'pcm',
    },
    Mad => {
        backend => 'Mad',
        types => ['mp3'],
        interface => 'open',
        exclude => {
            duration => 1, # mad does not tell us about duration
        },
    },
    Vorbis => {
        backend => 'Vorbis',
        types => ['ogg'],
        interface => 'open',
    },
    SndFile => {
        backend => 'SndFile',
        types => ['wav'],
        interface => 'open',
    },
);


# Based on sox's capabilities, add extra tests to the above data structure

if (AEP->_backend_available('SoX')) {
    my ($help, undef, $status) = qxy('sox', '-h');

    if (WIFEXITED($status)) {
        if ($help =~ /SUPPORTED FILE FORMATS: .*\b(?:ogg|vorbis)\b/i) {
            push @{$tests{SoX}{types}}, 'ogg';
        } else {
            warn "Your sox has no ogg\n";
        }
    } else {
        warn "couldn't run sox -h!";
    }
}



# Now calculate how many tests we have to run, for the plan.

my $testcount = 0;

for my $test (values %tests) {
    my @testfiles = map @$_, @files{@{$test->{types}}};
    $test->{testcount} = sum map {;scalar keys %{$_->{verify}}} @testfiles;

    # open/pcm test
    $test->{testcount} += @testfiles;
    # two length tests for each open
    $test->{testcount} += 2 * @testfiles if 'open' eq $test->{interface};

    # nonexistent file test
    $test->{testcount}++;

    # excluded tests for backend
    $test->{testcount} -= keys %{$test->{exclude}};

    $testcount += $test->{testcount};
}

plan tests => $testcount;


# Now the big game

for my $test (values %tests) {

    SKIP: {
        my $backend = $test->{backend};
        my $fullbackend = AEP . '::Backend::' . $backend;

        diag("Testing backend $backend");
        unless (AEP->_backend_available($backend)) {
            diag("Backend is not available");
            skip "no $backend", $test->{testcount};
        }

        my $versions = $fullbackend->used_versions;
        while (my ($product, $prodver) = each %$versions) {
            warn "Found $product version: $prodver\n";
        }

        my $badextractor = AEP->new('no-such-file.' . $test->{types}[0], backend => $backend);
        my $interface = $test->{interface};
        is (scalar($badextractor->$interface(undef, undef, undef)), undef,
            'test with nonexistent file name');

        for my $type (@{$test->{types}}) {
            for my $file (@{$files{$type}}) {
                diag('Testing with file ' . $file->{filename});
                my $extractor = AEP->new($file->{filename}, backend => $backend);

                # WAV_EXTENSIBLE was introduced in SoX 13.0.0
                my $doesntwork = $file->{WAV_EXTENSIBLE}
                    && 'SoX' eq $backend && $fullbackend->get_sox_version() < '13.0.0';

                diag("testing for brokenness (WAV_EXTENSIBLE is not available before SoX 13.0.0)") if $doesntwork;

                # Ideally the SoX backend should return "trynext" in this case.
                # However, it is designed to be a last resort anyway, and sox'
                # error message is more descriptive than "no suitable backend
                # found".

                SKIP: {
                    if ('pcm' eq $test->{interface}) {
                        ok(($extractor->pcm(undef, undef, undef) xor $doesntwork), 'pcm() works')
                            && !$doesntwork
                            or skip 'could not even extract', scalar keys %{$file->{verify}};
                    } elsif ('open' eq $test->{interface}) {
                        ok(($extractor->open(undef, undef, undef) xor $doesntwork), 'open() works')
                            && !$doesntwork
                            or skip 'could not even extract', 2 + scalar keys %{$file->{verify}};

                        # warns with 5.6.2:
                        # my $l = $extractor->read(my $buf, bytes => 4096);

                        my $l = $extractor->read(my ($buf), bytes => 4096);
                        cmp_ok($l, '>=', 4096);
                        is(length($buf), $l);
                    } else {
                        die $test->{interface};
                    }

                    while (my ($key, $value) = each %{$file->{verify}}) {
                        next if $test->{exclude}{$key};
                        is($extractor->format->$key(), $value, $key);
                    }
                }
            }
        }
    }
}
