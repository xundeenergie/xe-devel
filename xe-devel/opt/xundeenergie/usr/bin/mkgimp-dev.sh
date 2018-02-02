#!/usr/bin/env bash
#########################################################################
#
#   NB  Development tools and dependencies will be installed by the script if needed
#
########################################################################
#
#   [QUOTE from <http://www.gimp.org/source/howtos/gimp-git-build.html>]
#     1.I use autoconf's config.site feature instead of setting up
#       environment variables manually
#     2.I install in my home directory
#       Making use of config.site nullifies the need to manually manage
#       environment variables, and installing in the home directory makes it
#       easy to tinker with an installation since you don't need to
#       be root. So, put this in $GIMP_DIR/share/config.site where $GIMP_DIR is in
#       your home directory eg GIMP_DIR=$HOME/.gimp-dev
#
#   THE SCRIPT DOES:
#   1)  export gimp_build_directory="$HOME/.gimp-build-dev"
#   2)  mkdir $gimp_build_directory
#       mkdir $gimp_build_directory/share
#   3)  creates $gimp_build_directory/share/config.site
#
#       and adds the following:
#
#       export PATH="$gimp_build_directory/bin:$PATH"
#       export PKG_CONFIG_PATH="$gimp_build_directory/lib/pkgconfig:$PKG_CONFIG_PATH"
#       export LD_LIBRARY_PATH="$gimp_build_directory/lib:$LD_LIBRARY_PATH"
#       export ACLOCAL_FLAGS="-I $gimp_build_directory/share/aclocal $ACLOCAL_FLAGS"
#
#       Now autogen will use the paths in this file, so they no longer
#       need to be managed manually
#
#   4)  Build libmypaint, babl, gegl, gimp from git 
#   5)  The script should be able to handle both initial builds and update builds
#       Before starting the build, if development binaries are already present,
#       they are copied to a backup location (bin.old and lib.old).
#       If the build fails, these backups are restored so the user can use the
#       binaries+libs from the previous build.
#
#########################################################################

die() {
  [[ "$#" -gt 0 ]] && printf >&2 '%s\n' "$@"
  exit 1
}

set_global_variables() {
    debug=${DEBUG-1}
    mode='i'                           # can be 'i' or 'u' (initial build vs update)
    start_build_date=$(date +'%s')
    local number_of_jobs
    # Most recent required dependencies:
    # for Debian jessie based distros
    # required_dependencies=( git scons libgtk2.0-bin libgexiv2-dev libjson-glib-dev libjson-c-dev)
    required_dependencies=( git libgtk2.0-bin libgexiv2-dev libjson-glib-dev libjson-c-dev python-cairo-dev libgtk2.0-dev libbz2-dev python-dev python-gtk2-dev libbz2-dev librsvg2-dev libtool autoconf intltool gtk-doc-tools xsltproc)
    # for Debian sid based distros
    # required_dependencies=( git scons libgtk2.0-bin libgexiv2-dev libjson-c-dev)
    optional_dependencies=( gegl libraw-dev graphviz-dev libaa1-dev asciiart libasound2-dev libgs-dev libwebkitgtk-dev libmng-dev libopenexr-dev libwebp-dev libpoppler-glib-dev libwmf-dev libxpm-dev libavcodec-dev appstream-util xvfb libgudev-1.0.dev)
    gimp_build_directory="$HOME/.gimp-build-dev"
    # Find number of cpu cores, to multi-thread the make
    number_of_jobs="$(($(grep '^processor' /proc/cpuinfo | wc -l)))"
    number_of_jobs=$(( number_of_jobs - 1 ))
    make_options="-j${number_of_jobs}"
    # set up an associative array with key = component and value = method + git repo
    declare -Ag components
    components=( [libmypaint]="make https://github.com/mypaint/libmypaint.git" 
                 [babl]="make git://git.gnome.org/babl"
                 [gegl]="make git://git.gnome.org/gegl"
                 [gimp]="make git://git.gnome.org/gimp"
               )
}

install_global_dependencies() {
    # Get dependencies (hopefully :) )
    sudo apt-get update &&
    sudo apt-get install --yes --no-install-recommends "${required_dependencies[@]}" "${optional_dependencies[@]}" 
    # sudo apt-get build-dep -y babl gegl gimp || die
}

setup_environment_for_local_builds() {
    local rcc config_site
    if [[ -d "${gimp_build_directory}" ]]
    then
        mode='u'
        [[ -d "${gimp_build_directory}/bin" ]] && {
            cp -au  "${gimp_build_directory}/bin" "${gimp_build_directory}/bin.old" &&
                rm -rf "${gimp_build_directory}/bin" || die
        }
        [[ -d "${gimp_build_directory}/lib" ]] && {
            cp -au  "${gimp_build_directory}/lib" "${gimp_build_directory}/lib.old" &&
            rm -rf "${gimp_build_directory}lib" ||  die 
        }
    else
        mkdir "${gimp_build_directory}" || die
    fi
    [[ -d "${gimp_build_directory}/share" ]] || {
        mkdir "${gimp_build_directory}/share" || die
    }
    config_site="${gimp_build_directory}/share/config.site"
    [[ -s "$config_site" ]] || {
        touch "$config_site" || die
        {
            echo 'export PATH="${gimp_build_directory}/bin:$PATH"' > "$config_site" &&
                echo 'export PKG_CONFIG_PATH="${gimp_build_directory}/lib/pkgconfig:$PKG_CONFIG_PATH"' >> "$config_site" &&
                echo 'export LD_LIBRARY_PATH="${gimp_build_directory}/lib:$LD_LIBRARY_PATH"' >> "$config_site" &&
                echo 'export ACLOCAL_FLAGS="-I ${gimp_build_directory}/share/aclocal $ACLOCAL_FLAGS"' >> "$config_site"
        } || die
    }
    # set up environment variables
    export PATH="${gimp_build_directory}/bin:$PATH"
    export PKG_CONFIG_PATH="${gimp_build_directory}/lib/pkgconfig:${gimp_build_directory}/share/pkgconfig"
}

# Build_and_install components from git
build_and_install_component() {
    local component temp method repo gitargs
    component="$1"
    temp="${components[${component}]}"
    method="${temp%% *}"
    repo="${temp##* }"
    case "$method" in

        "make" )
            cd $gimp_build_directory || { printf 'Could not cd into %s\n' $gimp_build_directory; return 1; }
            if [[ -d "${gimp_build_directory}/${component}/.git" ]]
            then
                gitargs=( pull --rebase  "$repo" )
                cd "$component"
            else
                gitargs=( clone "$repo" )
            fi
            git "${gitargs[@]}"  || die
            
            [[ "${gitargs}" = clone ]] && { cd $component || die; }
            [[ -x './configure' ]] || ./autogen.sh --prefix=$PREFIX
            ./configure --prefix=$PREFIX
            # case $mode in
            #     "i")
            #         ./autogen.sh --prefix=$gimp_build_directory || die
            #         ;;
            #     "u")
            #         ./configure --prefix=$gimp_build_directory || die
            #         ;;
            #     *)
            #         die "mode \"$mode\" is not implemented"
            # esac
            
            make $make_options || die
            make install || die
            ;;

        "scons")
            cd $gimp_build_directory || { printf 'Could not cd into %s\n' $gimp_build_directory; return 1; }
            if [[ -d "${gimp_build_directory}/${component}/.git" ]]
            then
                gitargs=( pull --rebase  "$repo" )
                cd "$component"
            else
                gitargs=( clone "$repo" )
            fi
            git "${gitargs[@]}"  || die
            [[ "${gitargs}" = clone ]] && { cd $component || die;}
            scons prefix=$gimp_build_directory install || die
            ;;

        *)
            die 'unknown build and install method "%s"\n' "$method"
            ;;
    esac
}

build_and_install_local_components() {
    # build and install components
    local component
    for component in libmypaint babl gegl gimp
    do
        if ! build_and_install_component $component
        then
            die 'failed to build component %s\n' $component
        fi
        printf 'building component %s\n' "$component"
    done
    :
}

finish() {
    (( debug )) && printf 'entered finish ...\n'
    local rc filesize filesizeOK executable executableOK 
    rc=$?
    # we suppose the build was successfull when we have an executable 'gimp' in the
    # build directory with an acceptable file size and mdate > start_build_date
    filesizeOK=false
    executableOK=false
    local gimp
    executable=( ${gimp_build_directory}/bin/gimp-[0-9]*.[0-9]* )
    (( debug )) && declare -p executable
    (( ${#executable[@]} == 1 )) && {
        filesize=$(stat --format=%s $executable)
        (( filesize > 1000000 )) && filesizeOK=true
        executable_date=$(stat --format=%Y $executable)
        (( debug )) && {
            printf 'executable date: %d\n' $executable_date
            printf 'start_build_date: %d\n' $start_build_date
        }
        (( $executable_date > $start_build_date )) && executableOK=true
    }
    if $filesizeOK && $executableOK
    then
        printf 'gimp development has been successfully built\n'
        printf 'the new binaries are in %s\n' "${gimp_build_directory}/bin"
        [[ $mode = u ]] || {
            printf 'if you experience problems with the new binaries\n'
            printf 'you can find the old executables and libraries in %s\n' "${gimp_build_directory}/bin.old"
            }
    else
        printf 'gimp development failed to  build\n'
        if  [[ $mode = u ]]
        then
            printf 'restoring the old gimp binaries\n'
            cp -au "${gimp_build_directory}/bin.old" "${gimp_build_directory}/bin" &&
            cp -au "${gimp_build_directory}/lib.old" "${gimp_build_directory}/lib" || {
                printf 'error restoring old binaries/libraries\n'
            }
        fi            
        printf 'you should have seen one or more error messages\n'
        printf 'hopefully explaining what went wrong :)\n'
    fi
    return $rc
}

get_to_it() {
    local rc rcc=0

    set_global_variables
    rc=$?
    (( ! rc == 0 )) && {
        rcc=$((rcc+1))
        printf 'WARNING: %s returned %d\n' "set_global_variables" $rc
    }
    install_global_dependencies
    rc=$?
    (( ! rc == 0 )) && {
        rcc=$((rcc+1))
        printf 'WARNING: %s returned %d\n' "install_global_dependencies" $rc
    }
    setup_environment_for_local_builds
    rc=$?
    (( ! rc == 0 )) && {
        rcc=$((rcc+1))
        printf 'WARNING: %s returned %d\n' "setup_environment_for_local_builds" $rc
    }
    build_and_install_local_components
    rc=$?
    (( ! rc == 0 )) && {
        rcc=$((rcc+1))
        printf 'WARNING: %s returned %d\n' "build_and_install_local_components" $rc
    }

# ###------------------------------------------------------
# ## If you add a menu item "INSTALL GIMP-dev", then uncomment below
# ## to update menu.xml:

# #f="$HOME/.config/openbox/menu.xml"

# #sed -i 's|INSTALL GIMP|GIMP-2.9|g' "$f"
# #sed -i 's|x-terminal-emulator -e gimp-build|~/.gimp-dev/bin/gimp-2.9|g' "$f"

# #openbox --reconfigure

    return $rcc
}

PREFIX="$HOME/.gimp-build-dev"
shopt -s nullglob
trap finish EXIT
get_to_it
