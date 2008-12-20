use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    create_readme               => 1,
    create_makefile_pl          => 'small',
    module_name         => 'Audio::Extract::PCM',
    license             => 'perl',
    dist_author         => 'Christoph Bussenius <pepe@cpan.org>',
    dist_version_from   => 'lib/Audio/Extract/PCM.pm',
    build_requires => {
        'Compress::Zlib' => 0,
        'Test::More' => 0,
    },
    requires => {
        'IO::CaptureOutput' => '1.10', # need 1.10 for success flag and error code
    },
#    requires_external_bin => {
#        sox => 0,
#    },
    add_to_cleanup      => [ 'Audio-Extract-PCM-*' ],
);

$builder->create_build_script();
