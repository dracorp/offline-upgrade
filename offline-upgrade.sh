#!/bin/bash
#===============================================================================
#
#          FILE:  offline.upgrade.sh
# 
#         USAGE:  ./offline.upgrade.sh
# 
#   DESCRIPTION:  
# 
#       OPTIONS:  [-i input_file] [-e export_dir] [-lhsv]
#  REQUIREMENTS:  makepkg, pacman
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR: Piotr Rogoża (piecia), <rogoza dot piotr at gmail dot com>
#       LICENCE: Copyright (c) 2012, Piotr Rogoża
#       COMPANY: dracoRP
#       CREATED: 31.01.2012 12:20:22 CET
#      REVISION:  ---
#===============================================================================

NAME=offline-upgrade
VERSION=0.2
AUTHOR='Piotr Rogoża'

OPTIONS="e:b:i:hlsv"
set -- `getopt -o $OPTIONS -n $NAME -- $*`
AURURL='http://aur.archlinux.org'

requirements(){ #{{{
    if ! which pacman &>/dev/null; then
        echo "Required program 'pacman' not found" >&2
        exit 1
    fi
    if ! which makepkg &>/dev/null; then
        echo "Required makepkg 'pacman' not found" >&2
        exit 1
    fi
    if ! which curl &>/dev/null; then
        echo "Required curl 'pacman' not found" >&2
        exit 1
    fi
} #}}}

get_local_package(){ #{{{
    pacman -Qm
    if [ $? -ne 0 ]; then
        echo "Retrieve a list of local packages failed" >&2
    fi
} #}}}

usage(){ #{{{
    echo "Usage: `basename $0` [-i input_file] [-e export_dir] [-b build_directory] [-lhsv]"
} #}}}

help(){ #{{{
    usage
    cat<<-HELP
    -i input file with package to build or use STDIN
    -e export directory, default ./export_dir
    -b build directory, default ./build_dir
    -s install missing dependencies with pacman
    -l get info about local packages
    -v show version
    -h show this help
HELP
} #}}}

build_package(){ #{{{
    version=${1#* }
    package=${1% *}
    ext=pkg.tar.xz

    echo -e "Building $1"

    # check local package isn't built already
    if [  -f $EXPORT_DIR/$package-$version-*.$ext ]; then
        echo -e "The package $package-$version is already built.\n"
        return
    elif [ -f $package/$package-$version-*.$ext ]; then
        echo -e "The package $package-$version is already built.\nMoving it to $EXPORT_DIR"
        mv -fv $package/$package-$version-*.$ext $EXPORT_DIR/
        return
    else
        pushd $BUILD_DIR &>/dev/null || return
        
        # get the newest package from AUR
        if [ ! -d $package ]; then
            mkdir $package
        fi
        pushd $package &>/dev/null || return
        local pkgurl="$AURURL/packages/$package/$package.tar.gz"
        if ! curl -fs $pkgurl -o $package.tar.gz; then
            echo -e "The package $package not found in AUR.\n" >&2
            return
        fi
        bsdtar --strip-components 1 -xf $package.tar.gz
        rm $package.tar.gz

        # check version local package with package from AUR
        source PKGBUILD
        aur_version="$pkgver-$pkgrel"
        
        if [ -f $EXPORT_DIR/$package-$aur_version-*.$ext ]; then
            echo -e "The latest package $package-$aur_version from AUR is already built.\n"
            return
        elif [ -f $package-$aur_version-*.$ext ]; then
            echo -e "The latest package $package-$aur_version from AUR is already built.\nMoving it to $EXPORT_DIR"
            mv -fv $package/$package-$aur_version-*.$ext $EXPORT_DIR/
            return
        fi

        # build new package if versions are different
        if [ "$aur_version" != "$version" ]; then
            MAKEPKG_OPT="fs"
            if [ $INSTALL_DEP -eq 1 ]; then
                MAKEPKG_OPT+=" --noconfirm"
            fi
            makepkg $MAKEPKG_OPT
            ERROR_PKG=$?

            # for some packages installed from git
            source PKGBUILD
            aur_version="$pkgver-$pkgrel"
            if [ $ERROR_PKG -eq 0 ]; then

                mv -vf $package-$aur_version-*.pkg.tar.xz $EXPORT_DIR || \
                    echo -e "Moving $package-$aur_version failed.\n" >&2
            else
                echo -e "Building $package-$aur_version failed\n" >&2
            fi
        else
            echo -e "Local version of the package: $package-$version is the same as in AUR: $aur_version\n"
        fi
        popd +1 &>/dev/null
        popd &>/dev/null
    fi
} #}}}

requirements

while getopts "$OPTIONS" OPT; do
    case $OPT in
        i)
            INPUT_FILE=$OPTARG
            ;;
        e)
            EXPORT_DIR=$OPTARG
            ;;
        b)
            BUILD_DIR=$OPTARG
            ;;
        l)
            GET_LOCAL_PACKAGE=1
            ;;
        s)
            INSTALL_DEP=1
            ;;
        h)
            help
            exit
            ;;
        v)
            echo "Version: $VERSION"
            exit
            ;;
        *)
            usage
            exit
            ;;
    esac
done

# get local package and exit
if [ -n "$GET_LOCAL_PACKAGE" ]; then
    get_local_package
    exit
fi

#{{{ check export dir
if [ -z "$EXPORT_DIR" ]; then
    EXPORT_DIR=$PWD/export_dir
else
    if [[ $EXPORT_DIR =~ ^[^/] ]]; then
        # without slash at begin
        EXPORT_DIR=$PWD/$EXPORT_DIR
    fi
fi
# doesn't exist
if [ ! -d $EXPORT_DIR ]; then
    mkdir $EXPORT_DIR
    if [ $? -ne 0 ]; then
        echo "Failed make directory $BUILD_DIR" >&2
        exit 1
    fi
fi
#}}}

#{{{ check build dir
if [ -z "$BUILD_DIR" ]; then
    BUILD_DIR=$PWD/build_dir
else
    if [[ $BUILD_DIR =~ ^[^/] ]]; then
        # without slash at begin
        BUILD_DIR=$PWD/$BUILD_DIR
    fi
fi
# doesn't exist
if [ ! -d $BUILD_DIR ]; then
    mkdir $BUILD_DIR
    if [ $? -ne 0 ]; then
        echo "Failed make directory $BUILD_DIR" >&2
        exit 1
    fi
fi
#}}}

# run interactive or not?
if [ ! -t 0 ]; then
    while read package; do
        build_package "$package"
    done
elif [ -r "$INPUT_FILE" ]; then
    while read package; do
        build_package "$package"
    done < $INPUT_FILE
else
    usage
    exit
fi

exit

=pod

=head1 NAME

=encoding utf8

offline-upgrade - offline upgrade AUR's packages

=head1 SYNOPSIS

offline-upgrade [OPTION]

=head1 DESCRIPTION

The script generate list of local packages belong from AUR. Based on this list, the script downloads the latest packages from AUR, check the versions and if it are different then builds packages.

=head1 OPTIONS

B<-i> input_file

The input file with local packages coming from AUR, or use STDIN:
./offline-upgrade < input_file

B<-e> export_directory

Export pkg's files to the directory, default is set to ./export_dir

B<-b> build_directory

Build directory for PKGBUILDs, default is set to ./build_dir

B<-l>

Generates a list of local packages, coming from AUR (most probaly)

B<-v>

Show version

B<-h>

Show help

=head1 AUTHOR

Written by Piotr Rogoża

=head1 BUGS

Report bugs to <rogoza dot piotr at gmail dot com>

=head1 LICENSE

MIT

=cut

