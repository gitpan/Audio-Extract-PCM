package Audio::Extract::PCM::Backend::Vorbis;
use strict;
use warnings;
use base qw(Audio::Extract::PCM::Backend);
use Audio::Extract::PCM::Format;

# If required stuff cannot be found, we must fail with a special error message,
# so that AEPCM knows that this is not a real error (otherwise it would show
# the error message to the user).
BEGIN {
    use Class::Inspector;

    unless (Class::Inspector->installed('Ogg::Vorbis::Decoder')) {
        die __PACKAGE__ . " - trynext\n"; # try next backend
    }
}
use Ogg::Vorbis::Decoder;

__PACKAGE__->mk_accessors(qw(_decoder));


=head1 NAME

Audio::Extract::PCM::Backend::Vorbis - ogg/vorbis backend for audio extraction

=head1 SYNOPSIS

This module makes L<Audio::Extract::PCM> capable to use the vorbisfile library
(specifically L<Ogg::Vorbis::Decoder>) for audio extraction.

=head1 METHODS

=head2 new

See L<Audio::Extract::PCM::Backend/new>.

=cut


sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    my $decoder = Ogg::Vorbis::Decoder->open($this->filename);

    $this->_decoder($decoder);

    return $this;
}


=head2 open_back

See L<Audio::Extract::PCM::Backend/open>.

=cut

sub open_back {
    my $this = shift;
    my ($format) = @_;

    my $decoder = $this->_decoder;

    my $signed     = defined($format->signed) ? $format->signed : 1;
    my $samplesize = $format->samplesize || 2;

    if ($samplesize != 1 && $samplesize != 2) {
        $samplesize = 2;
    }

    # And now we get to the undocumented parts of Ogg::Vorbis::Decoder:
    my $srcfreq  = $decoder->{INFO}{rate}     or die 'uh, no rate?';
    my $channels = $decoder->{INFO}{channels} or die 'uh, no channels?';

    my $endformat = Audio::Extract::PCM::Format->new(
        freq       => $srcfreq,
        duration   => $decoder->time_total(),
        samplesize => $samplesize,
        channels   => $channels,
        signed     => $signed,

        # Although libvorbisfile supports the other endianness,
        # Ogg::Vorbis::Decoder always sets the local one.
        endian     => 'native',
    );
    return $endformat;
}


=head2 read_back

See L<Audio::Extract::PCM::Backend/read>.

=cut

sub read_back {
    my $this = shift;
    my $buf = \shift;
    my (%args) = @_;

    my $format = $this->format;

    my $bytes = $args{bytes};
    $bytes = $this->_decoder->raw_total unless defined $bytes;

    my $workbuf = $args{append} ? do{\my($x)} : $buf;
    $$workbuf = '';

    my $l = $this->_decoder->read($$workbuf, $bytes, $format->samplesize, $format->signed);
    if ($l < 0) {
        $this->error("Ogg::Vorbis::Decoder::read returned $l");
        return ();
    }
    $$buf .= $$workbuf if $args{append};
    return $l;
}


1
