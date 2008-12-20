use strict;
use warnings;
use Module::Build;

use IO::CaptureOutput qw(qxx);

my ($vers_output, $vers_error, $success) = qxx('sox', '--version');
print STDERR $vers_error;

if ($success) {
    my ($soxver) = $vers_output =~ /v([\d.]+)/
        or die "Strange sox --version output: $vers_output\n";
    warn "SoX version $soxver found.\n";
} else {
    die "Could not run the sox program; please make sure it is installed.\n";
}

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
        'IO::CaptureOutput' => '1.10',
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
