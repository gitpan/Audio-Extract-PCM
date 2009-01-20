package Audio::Extract::PCM::Backend;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw(filename error format));

=head1 NAME

Audio::Extract::PCM::Backend - base class for audio extraction backends

=head1 SYNOPSIS

This is the base class for the backends for L<Audio::Extract::PCM>.  The
backend classes provide a common interface to other modules:

=over 8

=item *

L<Audio::Extract::PCM::Backend::SoX> - uses the external "sox" program

=item *

L<Audio::Extract::PCM::Backend::Mad> - uses L<Audio::Mad>

=back

Apart from these backends that are provided with this distribution, it should
be fairly easy (and soon fully documented) to design backends to interface with
other modules/libraries/codecs.

Ideally, L<Audio::Extract::PCM> should find an appropriate backend for a given
file automatically.

=head1 INHERITANCE

This module inherits from L<Class::Accessor::Fast>.  If you write your own
backend, you should inherit from this class and thus you can add your own
accessors using CA's API.

=head1 ACCESSORS

=head2 filename

The file name.  This is expected to be given to the constructor.

=head2 error

Contains the description of the last error.

=head2 format

Contains a L<Audio::Extract::PCM::Format> object describing the format of the
PCM data after a successfull call to L</pcm> or L</open>.

=head1 METHODS

=head2 new

Constructor.  Accepts key-value pairs as arguments (i.e. not a hash reference
like Class::Accessor's constructor).

=cut

sub new {
    my $class = shift;
    my (%args) = @_;

    return $class->SUPER::new(\%args);
}


=head2 pcm

Extract all pcm data from the file.

In your backend, you should not override this method.  Rather you provide
C<open_back> and (optionally) C<pcm_back> methods.  If you provide a
C<pcm_back> method, it will be used to extract the audio data.  Otherwise, your
C<open_back> and C<read_back> methods will be used.

The single parameter for both C<pcm> and C<pcm_back> is a
L<Audio::Extract::PCM::Format> object which describes the desired format of the
PCM data.

If you provide a C<pcm_back> method, it is supposed to store the actual PCM
format with the L</format> accessor.

The return value is a reference to the PCM string buffer.

On error, C<undef> is returned (in scalar context) and the error should be set
with the C</error> accessor.

=cut

sub pcm {
    my $this = shift;

    unless ($this->can('pcm_back')) {

        my $ret = $this->open_back(@_);
        return $ret unless $ret;

        $this->format($ret);

        my %foohash = (buf => '');
        my $bufref = \$foohash{buf};

        1 while $this->read_back($$bufref, append => 1, bytes => 8192);

        return $bufref;
    }

    return $this->pcm_back(@_);
}


=head2 open

Open, i.e. prepare for L</read>.

You should not override this method but rather provide a C<open_back> method
with the same specifications.

The argument is a L<Audio::Extract::PCM::Format> object which describes the
desired format of the PCM data.

The return value is another format object which describes the actual format of
the audio data.  You need not bother setting the L</format> accessor in
C<open_back>; C<open> does this for you.

On error, C<undef> is returned (in scalar context) and the error should be set
with the C</error> accessor.

If the backend decides that it cannot open the file but some other backend
might be able to, the string "trynext" should be returned.  If C<open_back>
returns a format that does not satisfy the format request, C<open> treats this
as though C<open_back> had returned "trynext".

=cut


sub open {
    my $this = shift;
    my ($format) = @_;

    my $ret = $this->open_back(@_);

    return 'trynext' unless $format->satisfied($ret);

    $this->format($ret) if $ret;

    return $ret;
}


=head2 read

The backend should provide a C<read_back> method which will be called like this:

    $backend->read_back(
        $buffer,           # lvalue

        bytes => 100000,   # how many bytes to read at least.  Should default
                           # to all bytes

        append => 1,       # If this is specified, the buffer shall be appended to.
                           # Some backends can do this efficiently.
    );

The buffer shall be an lvalue, but the backend need not care about "strange"
lvalues like C<substr()>.  This would be too troublesome because many backends
make use of XS modules.

In scalar context, C<read_back> shall return the number of bytes read, 0 on eof
and C<undef> on error.

=cut

sub read {
    my $this = shift;
    my $buf = \shift;
    my (%args) = @_;
    my %orig_args = %args;

    my $format = $this->format;

    my $bytes = $args{bytes};
    unless (defined $bytes) {
        if (defined $args{seconds}) {
            $bytes = int(delete ($args{seconds})
                * $format->freq * $format->channels * $format->samplesize);
        }
    }
    $args{bytes} = $bytes if defined $bytes;

    my $bytes_read = $this->read_back($$buf, %args);

    return () unless defined $bytes_read;

    if (exists $orig_args{seconds}) {
        return $bytes_read / ($format->freq * $format->channels * $format->samplesize);
    } else {
        return $bytes_read;
    }
}


1
