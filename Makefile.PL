use inc::Module::Install;

# Define metadata
name           'Ubic';
all_from       'lib/Ubic/Catalog.pm';

# Specific dependencies
install_script 'bin/ubic-daemon';

WriteMakefile(
    clean => { FILES => 'tfiles' },
);
