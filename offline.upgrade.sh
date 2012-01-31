#!/bin/bash
#===============================================================================
#
#          FILE:  offline.upgrade.sh
# 
#         USAGE:  ./offline.upgrade.sh
# 
#   DESCRIPTION:  
# 
#       OPTIONS:  [-i input_file] [-l] [-d export_dir] [-h]
#  REQUIREMENTS:  makepkg, package-query(not required but recomend for faster search local packages)
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR: Piotr Rogoża (piecia), <rogoza dot piotr at gmail dot com>
#       LICENCE: Copyright (c) 2012, Piotr Rogoża
#       COMPANY: dracoRP
#       CREATED: 31.01.2012 12:20:22 CET
#       VERSION:
#      REVISION:  ---
#===============================================================================

OPTIONS="d:i:lh"
set -- `getopt $OPTIONS $*`
AURURL='http://aur.archlinux.org'

get_local_package(){ #{{{
    local_package=()
    if [ -x /usr/bin/package-query ]; then
        # faster method
        local_package=($(/usr/bin/package-query -Q | grep '^local' | awk '{print $1}' | awk -F'/' '{print $2}' | tr '\n' ' '))
    else
        # slower method
        DBPath=$(grep DBPath /etc/pacman.conf | sed 's/^[^=]\+=\s\+//')
        [ ! -d "$DBPath" -o -z "$DBPath" ] && DBPath="/var/lib/pacman/"

        # only local database
        DBPath+='/local'

        # packager
        source /etc/makepkg.conf
        [ -z "$PACKAGER" ] && PACKAGER='Unknown Packager'
        cd $DBPath
        for package in *; do
            if grep -q "$PACKAGER" $package/desc; then
                local_package+=($(echo $package | sed 's/-[^-]\+-[0-9]\+$//'))
            fi
        done
    fi
    local IFS=$'\n'
    echo "${local_package[*]}"
} #}}}

usage(){ #{{{
    echo "Usage: `basename $0` [-i input_file] [-d export_dir] [-l] [-h]"
} #}}}

help(){ #{{{
    usage
    cat<<-HELP
    -i input file with package to build or use STDIN
    -d export directory, default ./
    -l get info about local packages
    -h show this help
HELP
} #}}}

build_package(){ #{{{
    package=$1
    if [  -f $EXPORT_DIR/$package*.pkg.tar.xz ]; then
        echo -e "The package $package is already built.\n"
        return
    elif [ -f $package/$package*.pkg.tar.xz ]; then
        echo -e "The package $package is already built.\nMoving it to $EXPORT_DIR..."
        mv -fv $package*.pkg.tar.xz $EXPORT_DIR/
        return
    else
#        echo -e "Building the package '$package"
        if [ ! -d $package ]; then
            mkdir $package
        fi
        cd $package
        local pkgurl="$AURURL/packages/$package/$package.tar.gz"
        if ! curl -fs $pkgurl -o $package.tar.gz; then
            echo -e "The package $package not found in AUR.\n"
            return
        fi
        bsdtar --strip-components 1 -xvf $package.tar.gz
        rm $package.tar.gz
        makepkg -fs 
        if [ $? -eq 0 ]; then
            mv -vf $package*.pkg.tar.xz $EXPORT_DIR || \
                echo -e "Moving $package failed.\n"
        else
            echo -e "Building $package failed\n"
        fi
        cd -
    fi
} #}}}

while getopts $OPTIONS OPT; do
    case $OPT in
        i)
            INPUT_FILE=$OPTARG
            ;;
        d)
            EXPORT_DIR=$OPTARG
            ;;
        l)
            GET_LOCAL_PACKAGE=1
            ;;
        h)
            help
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

# check export dir
if [ -z "$EXPORT_DIR" ]; then
    EXPORT_DIR=$PWD
else
    if [[ $EXPORT_DIR =~ ^[^/] ]]; then
        # without slash at begin
        EXPORT_DIR=$PWD/$EXPORT_DIR
    fi
    # doesn't exist
    if [ ! -d $EXPORT_DIR ]; then
        mkdir $EXPORT_DIR || \
            exit 1
    fi
fi

# is interactive or no?
if [ ! -t 0 ]; then
    while read line; do
       echo $line | tr ' ' '\n' | \
           while read package; do
              build_package  $package
           done
    done
elif [ -r "$INPUT_FILE" ]; then
    while read line; do
       echo $line | tr ' ' '\n' | \
           while read package; do
               build_package $package
           done
    done < $INPUT_FILE
else
    usage
    exit
fi

