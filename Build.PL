use strict;
use warnings;
use Module::Build;

if (eval 'use Audio::Mad; 1' and not eval 'use Sys::Mmap::Simple; 1') {
    warn "WARNING!  Audio::Mad is installed, but Sys::Mmap::Simple isn't.\n";
    warn "To make sure that MP3 decoding doesn't waste lots of memory,\n";
    warn "please install Sys::Mmmap::Simple.\n";
    warn "See the perldoc (and maybe source) of Audio::Extract::PCM::Backend::Mad\n";
    warn "for details.\n";
}

my $builder = Module::Build->new(
    create_readme               => 1,
    create_makefile_pl          => 'small',
    module_name         => 'Audio::Extract::PCM',
    license             => 'perl',
    dist_author         => 'Christoph Bussenius <pepe@cpan.org>',
    dist_version_from   => 'lib/Audio/Extract/PCM.pm',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Compress::Zlib' => 0,
        'Test::More' => 0,
        'Module::Build' => 0,
    },
    requires => {
        'IO::CaptureOutput' => '1.10', # need 1.10 for success flag and error code
        'Class::Inspector'  => 0,
        'Class::Accessor'   => 0,
        'version'           => 0,
        'List::MoreUtils'   => 0,
    },
    recommends => {
        'Sys::Mmap::Simple' => 0, # only recommended for the Mad backend
    },
    no_index => {
        directory => 'example',
    },
#    recommends_external_bin => {
#        sox => 0,
#    },
    add_to_cleanup      => [ 'Audio-Extract-PCM-*' ],
);

$builder->create_build_script();
