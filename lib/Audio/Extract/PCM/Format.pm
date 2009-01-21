package Audio::Extract::PCM::Format;
use strict;
use warnings;
use Carp;
use base qw(Class::Accessor::Fast);
use List::Util qw(max);
use List::MoreUtils qw(any);

our @CARP_NOT = qw(Audio::Extract::PCM);


my %valid = (
    freq       => qr{^[0-9]+\z},
    samplesize => qr{^[0-9]+\z},
    endian     => qr{^(?:little|big)\z},
    channels   => qr{^[1-9]\z}, # empirical
    signed     => qr{^[01]\z},
    duration   => qr{^[0-9]+(?:\.[0-9]*)?\z},
);

my @fields = keys %valid;

__PACKAGE__->mk_accessors(@fields, 'required');

my $localendian = '10002000' eq unpack('h*', pack('s2', 1, 2))
    ? 'little'
    : 'big';

=head1 NAME 

Audio::Extract::PCM::Format - Format of PCM data

=head1 SYNOPSIS

This class is used by L<Audio::Extract::PCM> and its backends to represent the
format of PCM data.

=head1 ACCESSORS

=over 8

=item freq

Also known as the sample rate, in samples per second.

=item samplesize

In bytes per sample.

=item endian

The string C<little> or C<big>.  The constructor also accepts the string
C<native>.

This will print your native endianness ("little" or "big"):

    print Audio::Extract::PCM::Format->new(endian => 'native')->endian;

I've read somewhere that there are computers that have "middle endianness", and
maybe there are computers that don't use any of the three.  I only support
systems with either little or big endianness.

=item channels

A number.

=item signed

1 or 0, which means signed or unsigned, respectively.

=item duration

(seconds, may be fractional)

Of course, it doesn't make sense to specify the duration when you call
L<Audio::Extract::PCM/open>, however it will return you an object that has a
duration field, but it may be undefined if the backend does not support getting
the duration.

Once you have extracted all the pcm data, you can get the duration in seconds
using the formula:

    pcm_buffer_length / samplesize / channels / freq

=back

=head1 METHODS

=head2 new

Constructor.  You'll probably call this when you want to call
L<Audio::Extract::PCM/open> or L<Audio::Extract::PCM/pcm>.  In this case, the
following semantics apply:

Specify required values for frequency (samples per second), samplesize
(bytes per sample), channels, endianness and signedness:

    Audio::Extract::PCM::Format->new(
        freq => 44100,
        samplesize => 2,
        channels => 2,
        endian => 'native',
        signed => 1,
    );

If you omit a specification (or it is "undef"), the value will be chosen by the
back-end.

Additionally, there are some special ways to say what you want:

    Audio::Extract::PCM::Format->new(

        # The frequency *must* be one of 44100, 48000
        freq => [44100, 48000],

        # If *possibly*, you would like little endian, but you accept other
        # values too (aka "nice-to-have" values):
        endian => \['little'],
    );


Finally, there is a short form:

    Audio::Extract::PCM::Format->new($freq, $samplesize, $channels);

This is equivalent to:

    Audio::Extract::PCM::Format->new(
        freq        => $freq,
        samplesize  => $samplesize,
        channels    => $channels,
        endian      => 'native',
        signed      => 1,
    );

=cut

sub new {
    my $class = shift;

    my %args = (3 == @_ ? (
            freq       => $_[0],
            samplesize => $_[1],
            channels   => $_[2],
            endian     => 'native',
            signed     => 1,
        ) : @_);

    my $this = $class->SUPER::new();

    my %required;

    for my $field (@fields) {
        my $spec = delete $args{$field};

        if (defined $spec) {

            if ('ARRAY' eq ref $spec) {
                croak "$field has no values (try undef)" unless @$spec;

                for (@$spec) {

                    if ('endian' eq $field && 'native' eq $_) {
                        $_ = $localendian;
                    }

                    unless ($valid{$field}) {
                        croak "Not a valid $field: $_";
                    }
                }

                $required{$field} = [@$spec];
                $spec = $spec->[0];

            } elsif ('REF' eq ref $spec) {

                croak "bad argument for $field" unless 'ARRAY' eq ref $$spec;
                croak "(currently) only one argument is supported for nice-to-have" unless 1 == @$$spec;

                $spec = ${$spec}->[0];

            } else {

                $required{$field} = 1;
            }

            if ('endian' eq $field && 'native' eq $spec) {
                $spec = $localendian;
            }

            unless ($spec =~ $valid{$field}) {
                croak "Not a valid $field: $spec";
            }

            $this->$field($spec);
        }
    }

    if (keys %args) {
        croak 'Unknown argument(s): ' . join '/', keys %args;
    }

    $this->required(\%required);

    return $this;
}


=head2 findvalue

This is a useful method if you want to write your own backend.  You give it a
list of the formats that your backend can provide, and it tells you which one
fits the user's wishes best (according to the rules described under L</new>).

See the source of the provided backends for how to use it.

=cut

sub findvalue {
    my $this = shift;
    my ($values) = @_;

    my %scores;

    VAL: for (@$values) {
        my $score = 0;

        for my $field (@fields) {
            my $provided = $_->{$field};
            my $wanted = $this->$field();

            next unless defined $provided;

            unless ($provided =~ $valid{$field}) {
                confess "Probably a badly-written backend ($provided is not a valid $field)";
            }

            if (defined $wanted) {

                my @wanted = ($wanted);
                @wanted = @{$this->required->{$field}} if 'ARRAY' eq ref $this->required->{$field};

                if (any {_equal($_, $provided)} @wanted) {

                    # Increment the score for values we want.

                    $score += 10;

                } else {

                    # Don't return values that differ from required
                    # characteristics
                    next VAL if $this->required->{$field};

                    # See the test "choosing the smaller evil" in the test
                    # suite for the reason why we decrement so much here
                    $score -= 1000;
                }
            }

            elsif ('endian' eq $field) {

                # If no particular endian-ness is requested, we score the local
                # endianness a little higher.

                if ($provided ne $localendian) {
                    $score--;
                }
            }
        }

        if ($ENV{DEBUG}) {
            warn "Scoring $score for " . $_->{value} . "\n";
        }

        $scores{$score} = $_;
    }

    return undef unless keys %scores;

    my $maxscore = max keys %scores;
    my $found= $scores{$maxscore};

    return $found->{value} unless wantarray;

    my %specs;
    @specs{@fields} = @{$found}{@fields};

    my $foundformat = __PACKAGE__->new(%specs);

    return ($found->{value}, $foundformat);
}


# Compares numbers or strings
sub _equal {
    my ($x, $y) = @_;

    my $number_re = qr(^[0-9]+\z);

    if ($x =~ $number_re && $y =~ $number_re) {
        return $x == $y;
    } else {
        return $x eq $y;
    }
}



=head2 combine

Argument: another format object

Combines the values of two format objects.  Modifies C<$this> and returns it.

=cut

sub combine {
    my $this = shift;
    my ($other) = @_;

    if (@_ != 1) {
        $other = __PACKAGE__->new(@_);
    }

    for my $field (@fields) {
        if (defined $other->$field()) {
            $this->$field($other->$field());
            $this->required->{$field} = $other->required->{$field};
        }
    }

    return $this;
}


=head2 satisfied

Argument: another format object

If more than one argument is given, the arguments will be interpreted like
those of L</new>.

Returs whether the other format satisfies all I<required> properties of this
object.

=cut

sub satisfied {
    my $this = shift;
    my ($other) = @_;

    if (@_ > 1) {
        $other = __PACKAGE__->new(@_);
    }

    for my $field (@fields) {
        next unless $this->required->{$field};
        next unless defined $other->$field();

        my @required = $this->$field();
        @required = @{$this->required->{$field}} if 'ARRAY' eq ref $this->required->{$field};

        return () unless any {_equal($other->$field(), $_)} @required;
    }

    return 1;
}


1
