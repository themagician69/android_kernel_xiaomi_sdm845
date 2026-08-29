#!/bin/bash

echo -e "*************************************************"
echo -e "**                                             **"
echo -e "** Building Etude-KSU via LineageOS GCC 4.9    **"
echo -e "**                                             **"
echo -e "*************************************************"

# --- CLEAN PREVIOUS ARTIFACTS ---
echo "Cleaning up previous build artifacts..."
rm -rf out
rm -rf AnyKernel3
rm -rf gcc64
rm -rf gcc32
rm -f *.zip
# --------------------------------

# KernelSU-Next setup
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1

# General variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
ARCH="arm64"
SUBARCH="arm64"
DEVICE="beryllium"
KERNEL_DIR="$(pwd)"

# --- TOOLCHAIN SETUP (LineageOS GCC 4.9) ---
echo "Downloading LineageOS AArch64 GCC 4.9..."
git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 gcc64

echo "Downloading LineageOS ARM 32-bit GCC 4.9..."
git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git --depth=1 gcc32

export PATH="${KERNEL_DIR}/gcc64/bin:${KERNEL_DIR}/gcc32/bin:${PATH}"
# ------------------------------------------

# Stock Masking Overrides
rm -f localversion*
touch localversion
export KBUILD_BUILD_USER="root"
export KBUILD_BUILD_HOST="localhost"

# Files & Output
IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
echo "Cloning AnyKernel3..."
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git AnyKernel3

# Create Logs
exec 2> >(tee -a out/error.log >&2)

ZIPNAME=Etude-KSU-Next-beryllium
FINAL_ZIP=${ZIPNAME}-${DEVICE}.zip

BUILD_START=$(date +"%s")
yellow='\033[0;33m'
nocol='\033[0m'

# --- DEFCONFIG & MERGING STEP ---
echo "Making base sdm845-perf_defconfig..."
make O=out ARCH=${ARCH} SUBARCH=${SUBARCH} sdm845-perf_defconfig

if [ -f "arch/arm64/configs/vendor/xiaomi/beryllium.config" ]; then
    echo "Merging beryllium device-specific config..."
    ./scripts/kconfig/merge_config.sh -O out out/.config arch/arm64/configs/vendor/xiaomi/beryllium.config
    make O=out ARCH=${ARCH} SUBARCH=${SUBARCH} olddefconfig
else
    echo "Error: arch/arm64/configs/vendor/xiaomi/beryllium.config not found!"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo "Defconfig/Merge failed"
    exit 1
else
    echo "Configs merged successfully"
fi
# --------------------------------

# --- BYPASS GCC VERSION CHECK (XDA FIX) ---
echo "Applying XDA patch to bypass compiler-gcc.h version lock..."
if [ -f "include/linux/compiler-gcc.h" ]; then
    sed -i 's/#error Sorry, your version of GCC is too old - please use 5.1 or newer./\/\/#error Sorry, your version of GCC is too old - please use 5.1 or newer./g' include/linux/compiler-gcc.h
fi
# ------------------------------------------

# --- NATIVE GCC BUILD FUNCTION ---
Build_GCC () {
echo "Starting compilation using LineageOS GCC 4.9..."

make -j$(nproc --all) O=out \
    ARCH=${ARCH} \
    SUBARCH=${SUBARCH} \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi-
}
# ---------------------------------

# Run compilation
Build_GCC

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
else
    echo "Build successful"
fi

##----------------------------------------------------------------##
zipping() {
	cp $IMAGE AnyKernel3/
	cd AnyKernel3 || exit 1
    zip -r9 ${FINAL_ZIP} *
    MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
    cd ..
}
##----------------------------------------------------------##

zipping

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
