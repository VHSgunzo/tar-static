#!/bin/bash

export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1
# NO_SYS_MUSL=1

tar_version="latest"
musl_version="latest"

platform="$(uname -s)"
platform_arch="$(uname -m)"

if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt update && apt install -y \
            build-essential clang pkg-config git autoconf libtool \
            gettext autopoint po4a upx
fi

[ "$tar_version" == "latest" ] && \
  tar_version="$(curl -s https://ftp.gnu.org/gnu/tar/|tac|grep -v 'latest'|\
                 grep -om1 'tar-.*\.tar\.xz'|cut -d'>' -f2|\
                 sed 's|tar-||g;s|.tar.xz||g')"

[ "$musl_version" == "latest" ] && \
  musl_version="$(curl -s https://www.musl-libc.org/releases/|tac|grep -v 'latest'|\
                  grep -om1 'musl-.*\.tar\.gz'|cut -d'>' -f2|sed 's|musl-||g;s|.tar.gz||g')"

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [ -d release ]
    then
        echo "= removing previous release directory"
        rm -rf release
fi

# create build and release directory
mkdir build
mkdir release
pushd build

# download tarballs
echo "= downloading tar v${tar_version}"
curl -LO https://ftp.gnu.org/gnu/tar/tar-${tar_version}.tar.xz

echo "= extracting tar"
tar -xJf tar-${tar_version}.tar.xz

if [ "$platform" == "Linux" ]
    then
        echo "= setting CC to musl-gcc"
        if [[ ! -x "$(which musl-gcc 2>/dev/null)" || "$NO_SYS_MUSL" == 1 ]]
            then
                echo "= downloading musl v${musl_version}"
                curl -LO https://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

                echo "= extracting musl"
                tar -xf musl-${musl_version}.tar.gz

                echo "= building musl"
                working_dir="$(pwd)"

                install_dir="${working_dir}/musl-install"

                pushd musl-${musl_version}
                env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" LDFLAGS='-Wl,--gc-sections' ./configure --prefix="${install_dir}"
                make install
                popd # musl-${musl-version}
                export CC="${working_dir}/musl-install/bin/musl-gcc"
            else
                export CC="$(which musl-gcc 2>/dev/null)"
        fi
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building tar"
pushd tar-${tar_version}
env FORCE_UNSAFE_CONFIGURE=1 CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" LDFLAGS="$LDFLAGS -Wl,--gc-sections" ./configure
make
popd # tar-${tar_version}

popd # build

shopt -s extglob

echo "= extracting tar binary"
mv "build/tar-${tar_version}/src/tar" release 2>/dev/null

echo "= striptease"
strip -s -R .comment -R .gnu.version --strip-unneeded "release/tar" 2>/dev/null

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        upx -9 --best "release/tar" 2>/dev/null
fi

echo "= create release tar.xz"
tar --xz -acf tar-static-v${tar_version}-${platform_arch}.tar.xz release

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= tar v${tar_version} done"
