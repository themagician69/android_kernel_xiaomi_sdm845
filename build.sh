#!/bin/bash

print_help() {
    echo "Usage: $0 [device] [options]"
    echo "Remove out directory if compiling for a different device"
    echo
    echo "Device:"
    echo "  --beryllium    Compile kernel for beryllium (POCO F1)"
    echo
    echo "Options:"
    echo "  --ksu            With KernelSU-Next support"
    echo "  --all            Compile with KernelSU-Next for beryllium"
    echo "  --help           Display this help message"
    echo
    exit 1
}

echo -e "*************************************************"
echo -e "**                                             **"
echo -e "** Building Etude-KSU via Prelude-Clang        **"
echo -e "**                                             **"
echo -e "*************************************************"

# --- CLEAN PREVIOUS ARTIFACTS ---
echo "Cleaning up previous build artifacts..."
rm -rf out
rm -rf AnyKernel3
rm -rf clang
rm -f *.zip
# --------------------------------

# --- DEPENDENCY SETUP ---
echo "Installing build prerequisites (ccache, arm cross-compilers)..."
sudo apt-get update && sudo apt-get install -y ccache gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu binutils-arm-linux-gnueabi binutils-aarch64-linux-gnu
# ------------------------

# KernelSU-Next setup
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1

# General variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
DEVICE="beryllium"
KERNEL_DIR="$(pwd)"

# --- TOOLCHAIN SETUP (Prelude-Clang) ---
echo "Downloading Prelude-Clang..."
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang
CLANGDIR="${KERNEL_DIR}/clang"
# --------------------------------------

# Stock Masking Overrides
rm -f localversion*
touch localversion
export KBUILD_BUILD_USER="root"
export KBUILD_BUILD_HOST="localhost"
export USE_CCACHE=1

# Files & Output
IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
echo "Cloning AnyKernel3..."
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git AnyKernel3

ZIPNAME=Etude-KSU-Next-beryllium
FINAL_ZIP=${ZIPNAME}-${DEVICE}.zip

compile_kernel() {
    DEV=$1
    CFG=$2
    OUTPUT_DIR=$3

    echo "Compiling for device: $DEV with config: $CFG"

    # Merge base config and device config just like the maintainer script
    cat arch/arm64/configs/vendor/xiaomi/$CFG \
        arch/arm64/configs/vendor/xiaomi/$DEV.config \
        > arch/arm64/configs/generated_defconfig

    # Disable VDSO32 to prevent Clang 16 assembler compilation crashes on runners
    echo "CONFIG_VDSO32=n" >> arch/arm64/configs/generated_defconfig

    DEFCONFIG="generated_defconfig"

    if [ -f out/compile.log ]; then
        rm out/compile.log
    fi

    mkdir -p out

    export PATH="$CLANGDIR/bin:$PATH"

    make O=out ARCH=arm64 $DEFCONFIG

    BUILD_START=$(date +"%s")
    yellow='\033[0;33m'
    nocol='\033[0m'

    # --- NATIVE CLANG/LLVM BUILD ---
    echo "Starting compilation using Prelude-Clang with LLVM=1..."

    make -j$(nproc --all) O=out LLVM=1 \
        ARCH=arm64 \
        CC="clang" \
        LD=ld.lld \
        AR=llvm-ar \
        AS=llvm-as \
        NM=llvm-nm \
        STRIP=llvm-strip \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        READELF=llvm-readelf \
        HOSTCC=clang \
        HOSTCXX=clang++ \
        HOSTAR=llvm-ar \
        HOSTLD=ld.lld \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee -a out/compile.log

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))

    if [ ! -f "$IMAGE" ]; then
        echo "Build failed: Image.gz-dtb not generated."
        exit 1
    else
        echo -e "$yellow Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds.$nocol"
    fi

    mkdir -p $OUTPUT_DIR
    cp $IMAGE AnyKernel3/
    cd AnyKernel3 || exit 1
    zip -r9 ${FINAL_ZIP} *
    MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
    cd ..
    mv AnyKernel3/${FINAL_ZIP} .
    echo "Flashable zip created: ${FINAL_ZIP}"
}

# Argument handling matching maintainer style
if [ $# -eq 0 ]; then
    compile_kernel "beryllium" "mi845_defconfig" "."
elif [ "$1" = "--all" ]; then
    compile_kernel "beryllium" "mi845_defconfig" "."
else
    case "$1" in
        --beryllium)
            compile_kernel "beryllium" "mi845_defconfig" "."
            ;;
        --help)
            print_help
            ;;
        *)
            echo "Error: Unknown option '$1'"
            print_help
            ;;
    esac
fi
