#!/usr/bin/env perl
#===============================================================================
#
#         FILE: offline-upgrade.pl
#
#        USAGE: ./offline-upgrade.pl  
#
#  DESCRIPTION:  Offline upgrade Archlinux's packages
#
# REQUIREMENTS: perl-string-approx(String::Approx), perl-libwww(LWP::Simple), 
# perl-list-moreutils(List::MoreUtils), perl-io-interactive(IO::Interactive),
# pacman(makepkg)
#       AUTHOR: Piotr Rogoża (piecia), rogoza.piotr@gmail.com
#      COMPANY: dracoRP
#      CREATED: 20.02.2012 09:07:05
#     REVISION: ---
#===============================================================================

# core modules
use strict;
use warnings;
use feature qw(say);
use Carp;
use File::Find;
use File::Copy;
use File::Basename;
use Archive::Tar;
use Cwd;
use English qw(-no_match_vars);
use Getopt::Long;
Getopt::Long::Configure('bundling');
use Readonly;
# other modules
use String::Approx qw(amatch);
use List::MoreUtils qw(any none);
use IO::Interactive qw(is_interactive);
use LWP::Simple;

# about the program
my $AUTHOR  = 'Piotr Rogoża';
my $NAME    = 'offline-upgrade';
my $BASENAME = basename $PROGRAM_NAME;
use version; our $VERSION = qv(0.3);

# declare of subroutines
sub help;
sub version;
sub get_manual;

# global variables
my (%option, %env);                             # option for the program, local environment like as %ENV
my (@local_packages);                           # list of local packages
GetOptions(
    'i|in=s'      => \$option{input_file},    # only for local packages
    'o|out=s'     => \$option{output_file},   # only for local packages
    'g|get-local'   => \$option{get_local},     # get local package from system
    'e=s'           => \$option{export_dir},
    'b=s'           => \$option{build_dir},
    's|install-dep' => \$option{install_dep},   # Install missing dependencies using pacman in makepkg process
    'c|clean'       => \$option{clean_build},   # clean the build_dir/$package directory in makepkg process
    'L|log'         => \$option{log_build},     # Enable makepkg build logging to pkgname-pkgver-pkgrel-arch.log
    'v|version'     => sub{version; exit;},
    'h|help'        => sub{help; exit;},
    'man'           => sub{get_manual; exit;},
);

# readonly variables
Readonly my $NOT_FOUND => 404;
Readonly my $PROGRAM_FAILED => -1;

my $package_ext = 'pkg.tar.xz';
my $aur_url     = 'http://aur.archlinux.org';

# local packages 
$option{program} = 'pacman -Qm';

# configuration files
my $FILE_MAKEPKG = '/etc/makepkg.conf';
my $FILE_PACMAN  = '/etc/pacman.conf';

# for push, popd and dirs
my @DIRS;

sub get_manual { #{{{
    my $perldoc = `which perldoc`;
    chomp $perldoc;
    if ( $perldoc ){
        exec "$perldoc $PROGRAM_NAME";
    }
    else {
        say qq{The 'perldoc' program was not found on this computer.\nYou need to install it if you want see the manual\n};
        exit;
    }
    return ;
} ## --- end of sub get_manual }}}
sub dirs { #{{{
#===  FUNCTION  ================================================================
#         NAME: dirs
#      PURPOSE: print @DIRS
#   PARAMETERS: none
#      RETURNS: none
#  DESCRIPTION: print actual directories in stack @DIRS
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
    say "@DIRS";
    return;
} #}}}

sub pushd { #{{{
#===  FUNCTION  ================================================================
#         NAME: pushd
#      PURPOSE: modify @DIRS
#   PARAMETERS: new directory name
#      RETURNS: current directory or false
#  DESCRIPTION: Change directory and save the current directory in a stack
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
#    unshift @stack_dirs, shift;
#    chdir $stack_dirs[0];
#    dirs;
    my ($dir) = @_;
    push @DIRS, cwd; 
    if (chdir $dir) {
        return cwd;
    } else {
        return;
    }
} #}}}

sub popd { #{{{
#===  FUNCTION  ================================================================
#         NAME: popd
#      PURPOSE: modify @DIRS
#   PARAMETERS: none or number of directories
#      RETURNS: current directory or false
#  DESCRIPTION: Change directory to last place where pushd was called
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
#    @stack_dirs > 1 and shift @stack_dirs;
#    chdir $stack_dirs[0];
#    dirs;
    my ($count) = @_;
    my $dir;
    if ( !defined $count || (defined $count && $count == 1) ){
        $dir = pop @DIRS;
    }
    elsif ( $count > 1 ){
        while ( $count > 0 ){
            $dir = pop @DIRS;
            $count--;
        }
    }
    if (chdir $dir) {
        return cwd;
    } else {
        return;
    }
} #}}}

sub source_file { #{{{
#===  FUNCTION  ================================================================
#         NAME: source_file
#      PURPOSE: like bash source sets %env
#   PARAMETERS: file to read, variable to read(optional)
#      RETURNS: hash of environments
#  DESCRIPTION: read variables from source file and sets hash %env, with environment as key
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
    my ($input_file, $env_ref)  = @_;
    if ( ! -f $input_file || !ref $env_ref ){
        croak q{Bad subroutine call. It was expected 'file name', a reference to hash};
    }
    my ($key, $value);
    open my $fh, q{<}, $input_file
        or croak qq{could not open $input_file $ERRNO};

ENV:
    while (<$fh>){
        chomp;
        unless ( ($key, $value) = m/\A\s*(\w+)\s*=\s*([^#]+)\z/xms ){
            next ENV;
        }
        $value =~ s{\A['"]}{}xms;
        $value =~ s{['"]\z}{}xms;
            if ( $value =~ m/\$/xms ){
               croak unless eval {
                    $value =~ s{
                        \$
                        \{?
                        ([_0-9a-zA-Z]+)
                        \}?
                    }{
                        no strict 'refs';
                        if (defined $$1){
                            $$1;
                        }
                        else {
                            "";
                        }
                    }egx;
                };
                croak $EVAL_ERROR if $EVAL_ERROR;
            }
            {
                no strict 'refs';
                $$key = "$value";
            }
            $env_ref->{$key} = $value;
    }
    close $fh or croak qq{Could not close $input_file: $ERRNO};
    return;
} ## --- end of sub source_file }}}

sub search_local_package { #{{{
#===  FUNCTION  ================================================================
#         NAME: search_local_package
#      PURPOSE: modify the global array @local_packages
#   PARAMETERS: none
#      RETURNS: none
#  DESCRIPTION: for sub find(), for defined directory reads file 'desc' and 
#  looking for local(from makepkg) or unknown packager 
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================

    my $fullname    = $File::Find::name;
    my $file = $_;

    my ($package_name, $package_version);

    if ( ! -f $file || $file ne 'desc' ){
        return;
    }
    local $RS = q{};                            # rekordy rodzielone pustą linią
    open my ($fh), q{<}, $fullname or croak qq{could not open $fullname: $ERRNO};
    while(my $file_record = <$fh>){
        my @lines = split /\n/, $file_record;
        if ( $lines[0] eq '%NAME%' ){
            $package_name = $lines[1];
        }

        if ( $lines[0] eq '%VERSION%' ){
            $package_version = $lines[1];
        }

        if ( $lines[0] eq '%PACKAGER%' ){
            if ( my @match = amatch( $env{PACKAGER}, [ 'i 40%' ], $lines[1] ) ){
                push @local_packages, "$package_name $package_version";
            }
            elsif ( $lines[1] eq 'Unknown Packager' ){
                push @local_packages, "$package_name $package_version";
            }
        }
    }
    close $fh or croak qq{Could not close $fullname: $ERRNO};
    return;
} ## --- end of sub search_local_package }}}

sub get_local_package { #{{{
#===  FUNCTION  ================================================================
#         NAME: get_local_package
#      PURPOSE: 
#   PARAMETERS: none
#      RETURNS: none
#  DESCRIPTION: search local packages in the direcotry '/var/lib/pacman/local' 
#  and compare with result of 'pacman -Qm'
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
    my ($fh_output, @local_pacman_packages);

    find(\&search_local_package, $env{DBPath});

    # get local packages from comman 'pacman -Qm'
    open my ($fh_pacman), q{-|}, "$option{program}" 
        or croak q{Could not execute the program pacman};
    @local_pacman_packages = <$fh_pacman>;
    close $fh_pacman or croak q{Could close the program pacman};
    @local_pacman_packages = sort @local_pacman_packages;

    # compare two arrays
    foreach my $package (@local_pacman_packages){
        chomp $package;
        if ( none { $package eq $_ } @local_packages ){
            push @local_packages, $package;
        }
    }
    @local_packages = sort @local_packages;

    # get local packages from directory defined in pacman.conf
    if ( $option{output_file} ){
        open $fh_output, q{>}, "$option{output_file}"
            or croak qq{Could not open for write '$option{output_file}: $ERRNO};
        *STDOUT = $fh_output;
    }
    # jeśli zdefiniowano plik wyjściowy lub przekierowano do pliku to drukuj
    if ( $option{output_file} || !is_interactive ){
        local $LIST_SEPARATOR = "\n";
        print "@local_packages";
    }
    if ( $option{output_file} ){
        close $fh_output or croak qq{Could not close $option{output_file}: $ERRNO};
    }
    return ;
} ## --- end of sub get_local_package }}}

sub usage { #{{{
    say qq{Usage: $BASENAME [-i input_file] [-o output_file] [-e export_dir] [-b build_directory] [-s|--instal-dep] [-v|--version] [-L|--log] [-g|--get-local] [-c|--clean] [-h|--help] [--man]};
    return ;
} ## --- end of sub usage }}}

sub help { #{{{
    usage;
    print <<'HELP';

    -i - input file with package to build or use STDIN
    -o - output file for local packages or use STDOUT
    -g - get local packages from the system
    -e - export directory, default ./export_dir
    -b - build directory, default ./build_dir
    -s|--install-dep - install missing dependencies with pacman
    -c|--clean - clean the build_dir/$package directory after build (in the makepkg process)
    -L|--log - enable makepkg build logging to pkgname-pkgver-pkgrel-arch.log

    -v|--version - show version
    -h|--help - show this help
    --man - show man page
HELP
    return;
} ## --- end of sub help }}}

sub version { #{{{
    say "Version: $VERSION";
    return ;
} ## --- end of sub version }}}

sub say_warn { #{{{
    my ( $message ) = @_;
    if ( defined $message ){ 
        say {*STDERR} $message;
    }
    return ;
} ## --- end of sub say_warn }}}

sub build_package { #{{{
#===  FUNCTION  ================================================================
#         NAME: build_package
#      PURPOSE: 
#   PARAMETERS: 'name and version' of local package, separated by space
#      RETURNS: none
#  DESCRIPTION: builds the latest package from AUR baed on a list of local packages
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
    my ( $package_version ) = @_;
    my ( $package, $version ) = split q{ }, $package_version;
    if ( !$package || !$version ){
        return;
    }

    my $pkgurl="$aur_url/packages/$package/$package.tar.gz";
    my $file_glob;                              # for glob()

    # sprawdzamy czy paczka nie jest już zbudowana
    if ( defined( $file_glob = (glob "$option{export_dir}/$package-$version-*.$package_ext" )[0] ) && -f $file_glob ){
        say "The package $package $version is already built.";
        return;
    }

    # poczka zrobiona ale nie przeniesiona
    if ( defined( $file_glob = (glob "$option{build_dir}/$package-$version-*.$package_ext" )[0] ) && -f $file_glob ){
        say "The package $package $version is already built.\nMoving it to $option{export_dir}";
        move($file_glob,$option{export_dir});
        return;
    }

    # budujemy paczkę w katalogu build_dir
    pushd $option{build_dir};

    if ( getstore($pkgurl,"$package.tar.gz") == $NOT_FOUND ){
        say_warn "The archive $package not found in AUR site";
        popd;
        return;
    }
    
    my $archive = Archive::Tar->new("$package.tar.gz");

    # sprawdź czy archiwum zawiera katalog główny $package
    if ( dirname( ($archive->list_files)[0] ) ne $package ){
        if ( ! -d $package ){
            mkdir $package;
            if ( $ERRNO ){
                say_warn qq{Could not create the directory $package: $ERRNO};
                popd;
                return;
            }
        }
    }
    if ( $archive->extract() == 0 ){
        say_warn qq{Unpacking the archive $package failed, check the directory:} . cwd;
        popd;
        return;
    }

    # release memory
    $archive->clear();
    
    if ( (unlink cwd . "/$package.tar.gz") != 1 ){
        croak q{Wrong unlink } . cwd . qq{$package.tar.gz};
    }
    pushd $package;
    if ( -f 'PKGBUILD' ){
        source_file('PKGBUILD', \%env);
    }
    else{
        say_warn q{PKGBUILD not found in } . cwd;
        popd(2);
        return;
    }
    my $aur_version = "$env{pkgver}-$env{pkgrel}";

    if ( defined( $file_glob = (glob "$option{export_dir}/$package-$aur_version-*.$package_ext" )[0] ) && -f $file_glob ){
        say "The latest package $package $aur_version from AUR is already built.";
        popd(2);
        return;
    }
    elsif ( defined( $file_glob = (glob "$package/$package-$aur_version-*.$package_ext" )[0] ) && -f $file_glob ){
        say "The latest package $package $aur_version from AUR is already built.\nMoving it to $option{export_dir}";
        move($file_glob,$option{export_dir});
        if ( !$ERRNO ){
            say_warn qq{Moving $package-$aur_version failed.};
        }
        popd(2);
        return;
    }

    # build new package if versions are different
    if ( $aur_version ne $version ){
        my $MAKEPKG_OPT='--noconfirm';
        if ( $option{install_dep} ){
            $MAKEPKG_OPT .= ' -s';
        }
        if ( $option{clean_build} ){
            $MAKEPKG_OPT .= ' -c';
        }
        if ( $option{log_build} ){
            $MAKEPKG_OPT .= ' -L';
        }
        say "Building the package: $package-$aur_version (local version: $version)";
        `makepkg $MAKEPKG_OPT`;
        my $ERROR_PKG=$CHILD_ERROR;

        # for some packages installed from git
        if ( -f 'PKGBUILD' ){
            source_file('PKGBUILD', \%env);
        }
        else{
            say_warn q{PKGBUILD not found in } . cwd;
            popd(2);
            return;
        }

        # new aur version
        $aur_version="$env{pkgver}-$env{pkgrel}";
        if ( $ERROR_PKG == $PROGRAM_FAILED ){
            say_warn "Building $package-$aur_version failed";
            popd(2);
            return;
        }
        else {
            
            if ( defined( $file_glob = (glob "$package-$aur_version-*.$package_ext" )[0] ) && -f $file_glob ){
                move($file_glob,$option{export_dir});
                if ( !$ERRNO ){
                    say_warn "Moving $package-$aur_version failed.";
                }
            }
        }
    }
    else {
        say "Local version of the package: $package $version is the same as in AUR: $aur_version";
    }
    popd(2);
    return ;
} ## --- end of sub build_package }}}

sub check_dirs { #{{{
# sprawdzenie katalogu export_dir i ew. utworzenie go
    if ( !$option{export_dir} ){
        $option{export_dir} = cwd . '/export_dir';
    }

    if ( ! -d $option{export_dir} ){
        mkdir $option{export_dir} 
            or croak qq{Could not mkdir $option{export_dir}: $ERRNO};
    }

# sprawdzenie katalogu build_dir i ew. utworzenie go
    if ( !$option{build_dir} ){
        $option{build_dir} = cwd . '/build_dir';
    }

    if ( ! -d $option{build_dir} ){
        mkdir $option{build_dir} 
            or croak qq{Could not mkdir $option{build_dir}: $ERRNO};
    }
    return ;
} ## --- end of sub check_dirs }}}

#-------------------------------------------------------------------------------
# Main program
#-------------------------------------------------------------------------------

source_file($FILE_MAKEPKG, \%env);
source_file($FILE_PACMAN, \%env);

if ( !defined $env{DBPath} ){
    $env{DBPath} = '/var/lib/pacman/local';
}
else {
    $env{DBPath} .= '/local';
}

if ( $option{get_local} ){
    get_local_package;
    # jeżeli wystąpiło przekierowanie lub czytanie z pliku to wyjdź an koniec
    if ( $option{output_file} || !is_interactive ){
    # jeżeli wystąpiło przekierowanie do pliku to wyjdź po zakończeniu
#    if ( !is_interactive ){
        exit;
    }
}

# uruchomiony interaktywnie lub nie
my $fh_input;
if ( @local_packages == 0 && $option{input_file} ){
    # czytaj z pliku
    open $fh_input, q{<}, $option{input_file} 
        or croak qq{Could not open $option{input_file}: $ERRNO};
}
elsif ( !is_interactive ){
    # czytaj z stdin
    $fh_input = *STDIN;
}
elsif ( !$option{get_local} ){
    usage;
    exit;
}

# reads local packages from file
if ( @local_packages == 0 ){
    @local_packages = <$fh_input>;
    close $fh_input or croak qq{Could not close $option{input_file}: $ERRNO};
}
check_dirs;
foreach my $package(@local_packages){
    build_package $package;
}

__END__

=pod

=head1 NAME

=encoding utf8

offline-upgrade - offline upgrade AUR's packages

=head1 SYNOPSIS

offline-upgrade [OPTION]

=head1 DESCRIPTION

The script generate list of local packages belong from AUR. Based on this list, the script downloads the latest packages from AUR, check the versions and if it are different then builds packages.

=head1 OPTIONS

B<-i|--in> input_file

The input file with local packages, or use STDIN:
./offline-upgrade < input_file

B<-o|--out> output_file

The output file for local packages, or use STDIN:
./offline-upgrade -l > output_file

B<-g|--get-local>

Generates a list of local packages, building from AUR (most probaly) and local PKGBUILD

B<-e> export_directory

Export pkg's files to the directory, default is set to ./export_dir

B<-b> build_directory

Build directory for PKGBUILDs, default is set to ./build_dir

B<-s|--install-dep>

Install missing dependencies using pacman (in the makepkg process)

B<-c|--clean>

Clean the build_dir/$package directory after build (in the makepkg process)

B<-L|--log>

Enable makepkg build logging to pkgname-pkgver-pkgrel-arch.log

B<-v|--version>

Show version

B<-h|--help>

Show help

B<--man>

Show man page

=head1 AUTHOR

Written by Piotr Rogoża

=head1 BUGS

Report bugs to <rogoza dot piotr at gmail dot com>

=head1 LICENSE

MIT

=cut

