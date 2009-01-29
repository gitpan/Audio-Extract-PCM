package Audio::Extract::PCM;
use strict;
use warnings;
use Carp;
use IO::CaptureOutput qw(qxx);
use Audio::Extract::PCM::Format;
use Class::Inspector;
use base qw(Exporter);

use constant AEP  => __PACKAGE__;
our @EXPORT = qw(AEP AEPF);

=head1 NAME

Audio::Extract::PCM - Extract PCM data from audio files

=head1 VERSION

Version 0.04_59

=cut

our $VERSION = '0.04_59';


=head1 SYNOPSIS

This module's purpose is to extract PCM data from various audio formats.  PCM
is the format in which you send data to your sound card driver.  This module
aims to provide a single interface for PCM extraction from various audio
formats, compressed and otherwise.

The distribution includes some backends which provide access to
CPAN's audio decoding modules.

Usage example:

    use Audio::Extract::PCM;
    my $extractor = Audio::Extract::PCM->new('song.ogg');

    $extractor->open(endian => 'native', samplesize => 2) or die $extractor->error;

    warn "Sampling frequency is " . $extractor->format->freq;

    my $l;
    while ($l = $extractor->read(my $buf, bytes => 4096)) {
        print $buf;
    }
    die $extractor->error unless defined $l;

=head1 METHODS

=head2 new

Parameters: C<filename>

Constructs a new object to access the specified file.

The extension of the filename will be used to determine which backends open()
or pcm() will try.

=cut

sub new {
    my $class = shift;
    my ($filename, %args) = @_;

    my $this = bless {
        filename => $filename,
    }, $class;

    my ($ext) = $filename =~ /\.([a-z0-9_]+)\z/i;
    $ext = '' unless defined $ext;

    $this->{backends} = {
        mp3  => [qw( Mad     SoX )],
        ogg  => [qw( Vorbis  SoX )],
        wav  => [qw( SndFile SoX )],
        au   => [qw( SndFile SoX )],
        aiff => [qw( SndFile SoX )],
    }->{lc $ext} || ['SoX'];

    # Undocumented for now
    if (exists $args{backends}) {
        $this->{backends} = delete $args{backends};
    }
    if (exists $args{backend}) {
        $this->{backends} = [delete $args{backend}];
    }
    if (keys %args) {
        croak "Unknown argument: " . join '/', keys %args;
    }

    return $this;
}


sub _initbackend {
    my $this = shift;
    my ($failed) = @_;

    if ($failed) {

        if ($ENV{DEBUG}) {
            warn 'Backend '.$this->{backends}[0]." failed\n";
            if (@{$this->{backends}} > 1) {
                warn 'Trying backend '.$this->{backends}[1];
            }
        }

        shift @{$this->{backends}};
    }
    unless (@{$this->{backends}}) {
        $this->{error} = 'no suitable backend found';
        return ();
    }
    my $backend_short =  $this->{backends}[0];
    my $backend = join '::', __PACKAGE__, 'Backend', $backend_short;

    if ($this->_backend_available($backend_short)) {
        $this->{backend} = $backend->new(filename => $this->{filename});
        return 1;
    }

    return $this->_initbackend('failed');
}


# =head2 backend_available
# 
# (Class method.)
# 
# Parameter: A backend name, e.g. C<"Mad">.
# 
# Checks whether a specific backend is available on this system.  This might load
# the backend module.
# 
# Returns true or false.
# 
# =cut

# (Pod removed and method made private.  I don't like the idea of having public
# methods that use string-eval on their parameters.)

my %dont_use_backends;

sub _backend_available {
    my $class = shift;
    croak('This is a (class) method') unless $class->isa(__PACKAGE__);
    croak('One parameter expected')   unless 1 == @_;
    my ($backend_short) = @_;

    # Better be sure before doing eval and such evil things
    # (However I hope that you don't pass untrusted strings to this method.)
    unless ($backend_short =~ /^[A-Z]\w*\z/) {
        croak("Bad backend name: $backend_short");
    }
    
    my $backend = join '::', __PACKAGE__, 'Backend', $backend_short;

    my $available_ref = do {no strict 'refs'; \${$backend . '::AVAILABLE'}};
    return 1 if $$available_ref;

    if (Class::Inspector->installed($backend) && ! $dont_use_backends{$backend}) {

        local $@;
        local $SIG{__DIE__};

        # The AVAILABLE check is done to make sure we avoid the problem
        # discussed at http://www.perlmonks.org/?node_id=646888

        # "require" won't fail if %INC has the backend.  %INC might have the
        # backend even though it does not load, maybe because it was already
        # tried to require in the test suite.
        # Therefore we have an extra check via the
        # $Audio::Extract::PCM::Backend::*::AVAILABLE variables.  They get set
        # only if the backend compiles fine.

        if (eval "require $backend; 1" && $$available_ref) {
            return 1;
        }
        unless ($@ =~ m{^\Q$backend\E - trynext\s}) {
            warn;
        }
        $dont_use_backends{$backend} = 1;
    }
    return 0;
}


sub _getformat {
    my $this = shift;

    my $format;
    if (1 == @_) {
        $format = $_[0];
        unless ($format->isa('Audio::Extract::PCM::Format')) {
            croak "open's argument is not an Audio::Extract::PCM::Format object";
        }
    } else {
        $format = Audio::Extract::PCM::Format->new(@_);
    }

    return $format;
}


=head2 pcm

Extracts all pcm data at once.

Returns a reference to a string buffer which contains PCM data.  The format of
these data can be found out using L</format>.

On error, an undefined value (or empty list) is returned.

Arguments are the same as to L</open>.

=cut

sub pcm {
    my $this = shift;

    $this->{backend} or $this->_initbackend() or return ();

    {
        my $ret = $this->{backend}->pcm($this->_getformat(@_));

        if ($ret && 'trynext' eq $ret) {
            $this->_initbackend('failed') or return ();
            redo;
        }
        return $this->_backendstatus($ret);
    }
}


=head2 open

Opens the stream, initializes a backend.

=over 8

=item Usage

    $obj->open(
        freq       => 44100,
        samplesize => 2,
        channels   => 2,
        endian     => 'native',
    );

If there is one single argument, it must be a L<Audio::Extract::PCM::Format>
object describing the desired format of the extracted PCM data.

Otherwise, the supplied arguments will be given to
L<Audio::Extract::PCM::Format/new>.  See its documentation for details.

Note that not all backends support resampling and channel transformation, so if
you don't really need 44100 Hz, better don't specify it.  You'll probably get
the best audio quality if you use the sample rate from the encoded file, which
most backends use as default.

=item Return value

Another L<Audio::Extract::PCM::Format> object which describes the actual
format of the PCM data.  They will be the same values as provided to this
method, or some fitting values if no required values were specified.  As I
said, see L<Audio::Extract::PCM::Format/new> for details.

=back

=cut

sub open {
    my $this = shift;

    $this->{backend} or $this->_initbackend() or return ();

    {
        my $ret = $this->{backend}->open($this->_getformat(@_));

        if ($ret && 'trynext' eq $ret) {
            $this->_initbackend('failed') or return ();
            redo;
        }
        return $this->_backendstatus($ret);
    }
}


=head2 read

Get decoded PCM samples.  Use this only after a successful call to open.

=over 8

=item Usage

    $extractor->read(
        $buffer,          # an lvalue
    
        append => 1,      # Optional: append to buffer
    
        # Either a known amount of bytes:
        bytes => 4096,
        # or a known amount of time:
        seconds => 2.5,
    );

The method will read I<at least> as many bytes or seconds as specified.  Under
special circumstances (near the end of file), it may read less.

You shouldn't specify both C<bytes> and C<seconds>.

Maybe I'll get rid of the C<append> option in future releases.  And maybe of
the I<at least>.

"Strange" lvalues, like the return value of substr(), are not supported as the
C<$buffer> argument (yet?) -- at least for most backends.

=item Return value

If C<seconds> were specified, the number of seconds of the read audio data will
be returned.  Otherwise, the number of read bytes will be returned.  On eof, 0
will be returned.  On error, C<undef> will be returned (in scalar context), and
the error may be retrieved via error().

=back

=cut

sub read {
    my $this = shift;

    my $ret = $this->{backend}->read(@_);

    return $this->_backendstatus($ret);
}


=head2 error

Returns the last error that occured for this object.

Unfortunately this is often not very readable for computers.  For instance, if
the file couldn't be opened because it is not there, the various backends have
different strings that describe this error.

Some of various possible errors:

=over 8

=item "no suitable backend found"

This means that either there is no backend for this file type, or none of the
possible backends have their dependencies installed, or none of the possible
backends was able to satisfy the PCM format request (i.e. try a less specific
format request).

=back

=cut

sub error {
    my $this = shift;

    if (@_) {
        my ($msg) = @_;
        return $this->{error} = $msg;
    }

    return $this->{error};
}


# Give this method the return value of a backend method (or () for definite
# failure), then return the return value of this method.
#
# When the return value is an error, this will set the error descripton from
# the backend.
sub _backendstatus {
    my $this = shift;
    my (@status) = @_;

    unless (defined $status[0]) {
        $this->{error} = $this->{backend}->error();
    }

    return @status ? $status[0] : ();
}


=head2 format

Returns a L<Audio::Extract::PCM::Format> object which describes the format of
the extracted pcm data.

You should only call this method after a I<successfull> call to L</open> or
L</pcm>.  If you called L</open>, this method shall return the same format
that L</open> has returned.

=cut

sub format {
    my $this = shift;

    unless ($this->{backend}) {
        croak 'No backend has been initialized. (Call format() only after a successfull call to open() or pcm())';
    }

    return $this->{backend}->format;
}


=head1 EXPORTS

This module exports the following constants:

    AEP  = "Audio::Extract::PCM"
    AEPF = "Audio::Extract::PCM::Format"

This enables you to write:

    use Audio::Extract::PCM;
    my $aep = AEP->new($filename);

=head1 SEE ALSO

=over 8

=item *

L<http://en.wikipedia.org/wiki/Pulse-code_modulation> - PCM (Pulse-code modulation)

=back


=head1 DEPENDENCIES


Apart from the dependencies that should be automatically installed by CPAN,
there are some (optional) other dependencies.  It's okay not to install all of
them, especially if you don't need all file formats.

=over 8

=item sox

An external audio processing program (should be in the PATH).

This is for the SoX backend (L<Audio::Extract::PCM::Backend::SoX>).  It will
usually be used as a last resort, and it's quite clumsy as it uses an external
program, and it doesn't support open/read yet (only pcm()).  However, it
supports a lot of formats.

=item L<Audio::Mad>

Used for MP3 decoding (sox supports that too) by
L<Audio::Extract::PCM::Backend::Mad>.  Please note that as of January 2009,
there are some problems with this module (at least with recent perl and gcc
versions), and you can find a patch by me at
L<http://rt.cpan.org/Public/Bug/Display.html?id=42338>.

L<Audio::Mad> requires the libmad library, and its development headers for
compiling.

=item L<Ogg::Vorbis::Decoder>

This is used for Ogg/Vorbis decoding (sox supports that too) by
L<Audio::Extract::PCM::Backend::Vorbis>.

L<Ogg::Vorbis::Decoder> requires the vorbis library, and its development
headers for compiling.

=item L<Audio::SndFile>

This is a module that supports a wide variety of audio formats and it is used
by L<Audio::Extract::PCM::Backend::SndFile>.

L<Audio::SndFile> requires the libsndfile library, and its development headers
for compiling.

libsndfile had been supporting mainly uncompressed formats for a while, but
newer releases seem to support Ogg/Vorbis and FLAC too.  At the moment the
SndFile backend won't be tried for these formats because my system segfaults.
Well, I'm going to make that configurable anyway.

About the vorbis support:  As I understand it, libsndfile's read function isn't
able to return an error status, while libvorbisfile's read function is.  As
both the Vorbis backend and libsndfile make use of libvorbisfile, you should
use the former if you want to have full error control.

=back


=head1 TODO / PLANS

=over 8

=item *

Maybe I should add functionality for resampling and sample format
transformation of the returned PCM data of I<any> backend.  Some backends (Mad,
SoX) support it, but others don't (Vorbis).  The point of the abstract
interface is that the user needn't worry about the backends' capabilities, and
he shouldn't have to know that he shouldn't try resampling for ogg files.

=item *

The list (and order) of the backends should be made configurable.  For now it's
hard-coded, which makes it more or less impossible to write new backend modules
without changing this one, however I'm planning to change that.

=item *

Seeking.

=back

If you have any good ideas how to implement these todo items, please let me
know.

=head1 AUTHOR

Christoph Bussenius, C<< <pepe at cpan.org> >>

Please include the name of this module in the subject of your emails so they
won't get lost in spam.

If you find this module useful, I'll be glad if you drop me a note.


=head1 COPYRIGHT & LICENSE

Copyright 2008 Christoph Bussenius, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Audio::Extract::PCM
