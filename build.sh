#!/usr/bin/env bash
# =========================================
#         _____              _
#        |  ___| __ ___  ___| |__
#        | |_ | '__/ _ \/ __| '_ \
#        |  _|| | |  __/\__ \ | | |
#        |_|  |_|  \___||___/_| |_|
#
# =========================================
#
#  Minty - The kernel build script for Mint
#  The Fresh Project
#  Copyright (C) 2019-2021 TenSeventy7
#                2024-2025 PeterKnecht93
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#  =========================
#
# shellcheck disable=SC1090
#

# [
# Directories
TOP="$(pwd)"
TOOLCHAIN="$TOP/toolchain"
OUT_DIR="$TOP/out"
TMP_DIR="$OUT_DIR/tmp"
DEVICE_DB_DIR="$TOP/Documentation/device-db"
BUILD_CONFIG_DIR="$TOP/arch/arm64/configs"
SUB_CONFIG_DIR="$TOP/kernel/configs"

# Toolchain options
BUILD_PREF_COMPILER="clang"
BUILD_PREF_COMPILER_VERSION="proton"

# Build variables - DO NOT CHANGE
export ARCH="arm64"
export SUBARCH="arm64"
export ANDROID_MAJOR_VERSION="r"
export PLATFORM_VERSION="11.0.0"

VERSION=$(grep -m 1    VERSION "$TOP/Makefile"    | sed 's/^.*= //g')
PATCHLEVEL=$(grep -m 1 PATCHLEVEL "$TOP/Makefile" | sed 's/^.*= //g')
SUBLEVEL=$(grep -m 1   SUBLEVEL "$TOP/Makefile"   | sed 's/^.*= //g')

BUILD_DATE="$(date +%s)"
BUILD_KERNEL_BRANCH="${GITHUB_REF##*/}"
[[ -z $BUILD_KERNEL_BRANCH ]] && BUILD_KERNEL_BRANCH="user"
[[ $BUILD_KERNEL_BRANCH == *"android-"* ]] && BUILD_KERNEL_BRANCH="mainline"

# Defaults
BUILD_KERNEL_KSU=false
BUILD_KERNEL_CI=false
BUILD_KERNEL_DIRTY=false
BUILD_KERNEL_PERMISSIVE=false

# Script commands
script_echo() { echo "  $1"; }
exit_script() { kill -INT $$; }

merge_config() {
	if [[ ! -f "$SUB_CONFIG_DIR/mint_$1.config" ]]; then
		script_echo "E: Subconfig not found on config DB!"
		script_echo "   \"$SUB_CONFIG_DIR/mint_$1.config\""
		script_echo "   Make sure it is in the proper directory."
		script_echo " "
		exit_script
	else
		cat "$SUB_CONFIG_DIR/mint_$1.config" >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"
	fi
}

# Script functions
VERIFY_TOOLCHAIN() {
    sleep 2
    script_echo " "

    if [ -d "$TOOLCHAIN" ]; then
        script_echo "I: Toolchain found at repository root"
        cd "$TOOLCHAIN" || exit
        git pull
        cd "$TOP" || exit

        if $BUILD_KERNEL_CI; then
            if [[ $BUILD_PREF_COMPILER_VERSION == proton ]]; then
                sudo mkdir -p '/root/build/install/aarch64-linux-gnu'
                sudo cp -r "$TOOLCHAIN/lib" '/root/build/install/aarch64-linux-gnu'
                sudo chown -R "$(whoami)" '/root'
            fi
        fi
    else
        script_echo "I: Toolchain not found at repository root"
        script_echo "   Downloading recommended toolchain at \"$TOOLCHAIN\"..."
        git clone 'https://gitlab.com/TenSeventy7/exynos9610_toolchains_fresh.git' "$TOOLCHAIN" --single-branch -b "$BUILD_PREF_COMPILER_VERSION" --depth 1 2>&1 | sed 's/^/     /'
    fi

    export PATH="${TOOLCHAIN}/bin:$PATH"
	export LD_LIBRARY_PATH="${TOOLCHAIN}/lib:$LD_LIBRARY_PATH"

    # Proton Clang 13
    export CROSS_COMPILE="aarch64-linux-gnu-"
	export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
	export CC="$BUILD_PREF_COMPILER"
}
VERIFY_DEFCONFIG() {
    if [ ! -f "$BUILD_CONFIG_DIR/$BUILD_DEVICE_CONFIG" ]; then
        script_echo "E: Defconfig not found!"
        script_echo "   \"$BUILD_CONFIG_DIR/$BUILD_DEVICE_CONFIG\""
        script_echo "   Make sure it is in the proper directory."
        script_echo " "
        exit_script
    else
        cat "$BUILD_CONFIG_DIR/$BUILD_DEVICE_CONFIG" > "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"
    fi
}

SET_ANDROIDVERSION() {
    echo "CONFIG_MINT_PLATFORM_VERSION=$BUILD_ANDROID_PLATFORM" >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"
}
SET_LOCALVERSION() {
    case "$BUILD_KERNEL_BRANCH" in
    mainline) export LOCALVERSION=" - Mint $KERNEL_BUILD_VERSION" ;;
    user)     export LOCALVERSION=" - Mint-user $BUILD_DATE" ;;
    *)        export LOCALVERSION=" - Mint Beta $GITHUB_RUN_NUMBER"
    esac
}
SET_ZIPNAME() {
    local MINT_TYPE MINT_SELINUX ONEUI_VERSION ROOT_SOLUTION
    MINT_VERSION="$BUILD_DATE"
    MINT_TYPE="UB"
    MINT_SELINUX="Enforcing"

    if $BUILD_KERNEL_CI; then
        if [[ $BUILD_KERNEL_BRANCH == mainline ]]; then
            MINT_VERSION="$KERNEL_BUILD_VERSION"
        else
            MINT_VERSION="$GITHUB_RUN_NUMBER"
        fi
        MINT_TYPE="CI"
    fi

    $BUILD_KERNEL_KSU && ROOT_SOLUTION="-KSU"
    $BUILD_KERNEL_PERMISSIVE && MINT_SELINUX="Permissive"

    case "$BUILD_VARIANT" in
    aosp)
        MINT_VARIANT="AOSP"
        ;;
    oneui)
        MINT_VARIANT="OneUI"
        ONEUI_VERSION="$((BUILD_ANDROID_PLATFORM - 8))"
        ;;
    recovery)
        MINT_VARIANT="Recovery"
        ;;
    esac

    if [[ $BUILD_KERNEL_BRANCH == mainline ]]; then
        ZIP_NAME="Mint-${MINT_VERSION}.A${BUILD_ANDROID_PLATFORM}.${MINT_VARIANT}${ONEUI_VERSION}${ROOT_SOLUTION}_${BUILD_DEVICE_NAME^}.zip"
    else
        ZIP_NAME="MintBeta-${MINT_VERSION}.A${BUILD_ANDROID_PLATFORM}.${MINT_VARIANT}${ONEUI_VERSION}-${MINT_SELINUX}${ROOT_SOLUTION}_${BUILD_DEVICE_NAME^}.${MINT_TYPE}.zip"
    fi
}

BUILD_KERNEL() {
    local JOBS
    JOBS="$(nproc --all)"

    sleep 3
    script_echo " "

    case "$BUILD_PREF_COMPILER_VERSION" in
    proton)
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip "$BUILD_DEVICE_TMP_CONFIG" LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip -j$JOBS LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        ;;
    clang)
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" LLVM=1 "$BUILD_DEVICE_TMP_CONFIG" LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" LLVM=1 -j$JOBS LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        ;;
    *)
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" "$BUILD_DEVICE_TMP_CONFIG" LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        make -C "$TOP" CC="$BUILD_PREF_COMPILER" -j$JOBS LOCALVERSION="$LOCALVERSION" 2>&1 | sed 's/^/     /'
        ;;
    esac

    if [ ! -f "$TOP/arch/arm64/boot/Image" ]; then
        script_echo "E: Image not built successfully!"
        script_echo "   Errors can be found above."
        sleep 3
        exit_script
    fi
}
BUILD_RAMDISK() {
    local comptype compcmd
    comptype="cpio"
    RAMDISK="ramdisk-new.cpio"

    case "$comptype" in
    gzip)  compcmd="gzip";                          RAMDISK="$RAMDISK.gz" ;;
    lzop)  compcmd="lzop";                          RAMDISK="$RAMDISK.lzo" ;;
    xz)    compcmd="xz -1 -Ccrc32";                 RAMDISK="$RAMDISK.xz" ;;
    lzma)  compcmd="xz -9 -Flzma";                  RAMDISK="$RAMDISK.lzma" ;;
    bzip2) compcmd="bzip2";                         RAMDISK="$RAMDISK.bz2" ;;
    lz4)   compcmd="$TOP/tools/make/bin/lz4 -9";    RAMDISK="$RAMDISK.lz4" ;;
    lz4-l) compcmd="$TOP/tools/make/bin/lz4 -9 -l"; RAMDISK="$RAMDISK.lz4" ;;
    cpio)  compcmd="cat";                           RAMDISK="$RAMDISK" ;;
    esac

    script_echo " "
    script_echo "I: Building ramdisk..."
    script_echo "Compression type: $comptype"

    cd "$TOP/tools/make/ramdisk" || exit
    find . | cpio -R 0:0 -H newc --quiet -o | $compcmd > "$TOP/tools/make/$RAMDISK"
    cd "$TOP" || exit

    if [ ! -f "$TOP/tools/make/$RAMDISK" ]; then
        script_echo " "
		script_echo "E: Ramdisk not built successfully!"
		script_echo "   Errors can be found above."
		sleep 3
		exit_script
    fi
}
BUILD_IMAGE() {
    script_echo " "
	script_echo "I: Building kernel image..."
	script_echo "    Header/Page size: $DEVICE_KERNEL_HEADER/$DEVICE_KERNEL_PAGESIZE"
	script_echo "      Board and base: $DEVICE_KERNEL_BOARD/$DEVICE_KERNEL_BASE"
	script_echo " "
	script_echo "     Android Version: $PLATFORM_VERSION"
	script_echo "Security patch level: $PLATFORM_PATCH_LEVEL"

    "$TOP/tools/make/bin/mkbootimg" \
        --kernel "$TOP/arch/arm64/boot/Image" --ramdisk "$TOP/tools/make/$RAMDISK" \
        --cmdline "androidboot.selinux=permissive loop.max_part=7" --board "$DEVICE_KERNEL_BOARD" \
        --base "$DEVICE_KERNEL_BASE" --pagesize "$DEVICE_KERNEL_PAGESIZE" \
        --kernel_offset "$DEVICE_KERNEL_OFFSET" --ramdisk_offset "$DEVICE_RAMDISK_OFFSET" \
        --second_offset "$DEVICE_SECOND_OFFSET" --tags_offset "$DEVICE_TAGS_OFFSET" \
		--os_version "$PLATFORM_VERSION" --os_patch_level "$PLATFORM_PATCH_LEVEL" \
		--header_version "$DEVICE_KERNEL_HEADER" --hashtype "$DEVICE_DTB_HASHTYPE" \
		-o "$OUT_DIR/boot.img"

	if [[ ! -f "$OUT_DIR/boot.img" ]]; then
		script_echo " "
		script_echo "E: Kernel image not built successfully!"
		script_echo "   Errors can be found above."
		sleep 3
		exit_script
	fi
}
BUILD_PACKAGE() {
    script_echo " "
    script_echo "I: Creating kernel ZIP..."

    # Import kernel image
    mv "$TOP/arch/arm64/boot/Image" "$TMP_DIR"

    # Import DTB image
    mv "$TOP/arch/arm64/boot/dtb_exynos.img" "$TMP_DIR/dtb.img"

    # Import ramdisk
    mv "$TOP/tools/make/$RAMDISK" "$TMP_DIR/$RAMDISK"

    # Import AnyKernel3
    cp -r "$TOP/tools/make/package/"* "$TMP_DIR"

    # Nuke product from fstab when building AOSP
    if [[ $BUILD_VARIANT == aosp ]]; then
        script_echo "I: Remove product from fstab for use with AOSP ROMs."
        sed -i '/product/d' "$TOP/tools/make/ramdisk/fstab.exynos9610"
        sed -i '/product/d' "$TOP/tools/make/ramdisk/fstab.exynos9610"
    fi

    # Generate manifest
    {
        echo "ro.mint.build.date=$BUILD_DATE"
        echo "ro.mint.build.branch=$BUILD_KERNEL_BRANCH"
        echo "ro.mint.build.ksu=$BUILD_KERNEL_KSU"
        echo "ro.mint.droid.device=${BUILD_DEVICE_NAME^}"
        echo "ro.mint.droid.variant=$MINT_VARIANT"

        if [[ $BUILD_KERNEL_BRANCH == mainline ]]; then
            echo "ro.mint.droid.beta=false"
        else
            echo "ro.mint.droid.beta=true"
        fi
        echo "ro.mint.build.version=$MINT_VERSION"

        echo "ro.mint.droid.android=$BUILD_ANDROID_PLATFORM"
        echo "ro.mint.droid.platform=11-$BUILD_ANDROID_PLATFORM"

        # Device support
        echo "ro.mint.device.name1=${BUILD_DEVICE_NAME}"
        echo "ro.mint.device.name2=${BUILD_DEVICE_NAME}xx"
        echo "ro.mint.device.name3=${BUILD_DEVICE_NAME}dd"
        echo "ro.mint.device.name4=${BUILD_DEVICE_NAME}ser"
        echo "ro.mint.device.name5=${BUILD_DEVICE_NAME}ltn"
        [ "$BUILD_DEVICE_NAME" == "a50" ] && echo "ro.mint.device.name6=a505f"
    } >> "$TMP_DIR/mint.prop"

    # Create zip file
    cd "$TMP_DIR" && zip -9 -r "$OUT_DIR/$ZIP_NAME" ./* 2>&1 | sed 's/^/     /'
}

show_usage() {
	script_echo "Usage: $0 -d|--device <device> -v|--variant <variant> [main options]"
	script_echo " "
	script_echo "Main options:"
	script_echo "-d, --device <device>     Set build device to build the kernel for. Required."
	script_echo "-a, --android <version>   Set Android version to build the kernel for. (Default: 11)"
	script_echo "-v, --variant <variant>   Set build variant to build the kernel for. Required."
	script_echo " "
	script_echo "-k, --kernelsu            Pre-root the kernel with KernelSU."
	script_echo "                          Not available for 'recovery' variant."
	script_echo "-n, --no-clean            Do not clean up before build."
	script_echo "-p, --permissive          Build kernel with SELinux fully permissive. NOT RECOMMENDED!"
	script_echo " "
	script_echo "-h, --help                Show this message."
	script_echo " "
	script_echo "Variant options:"
	script_echo "    oneui: Build Mint for use with stock and One UI-based ROMs."
	script_echo "     aosp: Build Mint for use with AOSP and AOSP-based Generic System Images (GSIs)."
	script_echo " recovery: Build Mint for use with recovery device trees. Doesn't build a ZIP."
	script_echo " "
	script_echo "Supported devices:"
	script_echo "  a50 (Samsung Galaxy A50)"
	exit_script
}
# ]

script_echo " "
script_echo "==============================================="
script_echo "                       _       _               "
script_echo "                 /\/\ (_)_ __ | |_             "
script_echo "                /    \| | '_ \| __|            "
script_echo "               / /\/\ \ | | | | |_             "
script_echo "               \/    \/_|_| |_|\__|            "
script_echo "                                               "
script_echo "==============================================="
script_echo "           Minty - Kernel Build Script         "
script_echo "            Part of The Fresh Project          "
script_echo "       by TenSeventy7 - Licensed in GPLv3      "
script_echo "                                               "
script_echo "       Originally built for Project ShadowX    "
script_echo "==============================================="
script_echo " "

# Process arguments
POSITIONAL=()
while [ $# -gt 0 ]; do
    key="$1"

    case "$key" in
    -d|--device)
        BUILD_DEVICE_NAME="$2"
        shift; shift ;;
    -a|--android)
        BUILD_ANDROID_PLATFORM="$2"
        shift; shift ;;
    -v|--variant)
        BUILD_VARIANT="$2"
        shift; shift ;;
    -c|--automated)
        BUILD_KERNEL_CI=true
        shift ;;
    -k|--kernelsu)
        BUILD_KERNEL_KSU=true
        shift ;;
    -n|--no-clean)
        BUILD_KERNEL_DIRTY=true
        shift ;;
    -p|--permissive)
        BUILD_KERNEL_PERMISSIVE=true
        shift ;;
    -h|--help)
        show_usage ;;
    *)
        POSITIONAL+=("$1")
        shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

# Verify selections
if [ -z "$BUILD_DEVICE_NAME" ]; then
    script_echo "E: No device selected!"
    script_echo " "
    show_usage
elif [ ! -f "$DEVICE_DB_DIR/$BUILD_DEVICE_NAME.sh" ]; then
    script_echo "E: Device is not valid!"
    script_echo " "
    show_usage
fi

[[ -z $BUILD_ANDROID_PLATFORM ]]     && BUILD_ANDROID_PLATFORM=11
[[ $BUILD_ANDROID_PLATFORM -lt 11 ]] && BUILD_ANDROID_PLATFORM=11
[[ $BUILD_ANDROID_PLATFORM -gt 13 ]] && BUILD_ANDROID_PLATFORM=12

if [ -z "$BUILD_VARIANT" ]; then
    script_echo "E: No variant selected!"
    script_echo " "
    show_usage
elif [ ! -f "$SUB_CONFIG_DIR/mint_variant_$BUILD_VARIANT.config" ]; then
    script_echo "E: Variant is not valid!"
    script_echo " "
    show_usage
fi

# Set variables
source "$DEVICE_DB_DIR/kernel_info.sh"
source "$DEVICE_DB_DIR/$BUILD_DEVICE_NAME.sh"
BUILD_DEVICE_CONFIG="exynos9610-${BUILD_DEVICE_NAME}_core_defconfig"
BUILD_DEVICE_TMP_CONFIG="tmp_exynos9610-${BUILD_DEVICE_NAME}_${BUILD_VARIANT}_defconfig"
export KCONFIG_BUILTINCONFIG="$BUILD_CONFIG_DIR/exynos9610-${BUILD_DEVICE_NAME}_default_defconfig"

SET_ANDROIDVERSION
SET_LOCALVERSION
SET_ZIPNAME

# Print build information
script_echo "I: Selected device:    $BUILD_DEVICE_NAME"
script_echo "   Selected variant:   $MINT_VARIANT"
script_echo "   Kernel version:     $VERSION.$PATCHLEVEL.$SUBLEVEL"
script_echo "   Android version:    $BUILD_ANDROID_PLATFORM"
script_echo "   KernelSU-enabled:   $BUILD_KERNEL_KSU"
script_echo "   Output ZIP file:    $OUT_DIR/$ZIP_NAME"

# Setup build environment
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

VERIFY_TOOLCHAIN
VERIFY_DEFCONFIG

git submodule update --init "$TOP/KernelSU"

if $BUILD_KERNEL_CI; then
	export KBUILD_BUILD_USER="Clembot"
	export KBUILD_BUILD_HOST="Lumiose-CI"

	script_echo " "
	script_echo "I: Beep boop! CI build!"
fi

if $BUILD_KERNEL_DIRTY; then
	script_echo " "
	script_echo "I: Dirty build!"
else
	script_echo " "
	script_echo "I: Clean build!"
	make CC="$BUILD_PREF_COMPILER" clean 2>&1 | sed 's/^/     /'
	make CC="$BUILD_PREF_COMPILER" mrproper 2>&1 | sed 's/^/     /'
fi

# Merge subconfigs
merge_config "partial-deknox-$BUILD_ANDROID_PLATFORM"
merge_config "mali-$BUILD_ANDROID_PLATFORM"
merge_config "variant_$BUILD_VARIANT"

if $BUILD_KERNEL_KSU; then
    if [[ $BUILD_VARIANT == recovery ]]; then
        script_echo "I: Recovery variant selected."
        script_echo "   KernelSU is not an available option to allow recovery to boot."
        merge_config root-none
        sleep 3
    else
        merge_config root-kernelsu
    fi
else
    merge_config root-none
fi

if $BUILD_KERNEL_PERMISSIVE; then
	script_echo "WARNING! You're building this kernel in permissive mode!"
	script_echo "         This is insecure and may make your device vulnerable."
	script_echo "         This kernel has NO RESPONSIBILITY on whatever happens next."
	merge_config selinux-permissive
fi

# Build Mint
BUILD_KERNEL
if [[ $BUILD_VARIANT == recovery ]]; then
	script_echo " "
	script_echo "I: Exporting kernel image..."
	mv -f "$TOP/arch/arm64/boot/Image" "$OUT_DIR"
else
    BUILD_RAMDISK
    BUILD_IMAGE
	BUILD_PACKAGE
fi

# Print end message
TIME_NOW=$(date +%s)
BUILD_TIME=$((TIME_NOW-BUILD_DATE))
BUILD_TIME_STR=$(printf '%02dh:%02dm:%02ds\n' $((BUILD_TIME/3600)) $((BUILD_TIME%3600/60)) $((BUILD_TIME%60)))

script_echo " "
script_echo "I: Yay! Kernel build is done!"
script_echo "   Kernel build took ${BUILD_TIME_STR}"
script_echo "   File can be found at:"
script_echo "   \"$OUT_DIR/$ZIP_NAME\""
rm -f "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"
sleep 5

exit 0
