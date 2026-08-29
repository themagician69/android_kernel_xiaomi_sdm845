#!/bin/sh

echo -e "*************************************************"
echo -e "**                                             **"
echo -e "** Building Etude-KSU via Standalone Clang     **"
echo -e "** (Based on Nathan Chancellor's guidelines)   **"
echo -e "*************************************************"

# --- CLEAN PREVIOUS ARTIFACTS ---
echo "Cleaning up previous build artifacts..."
rm -rf out
rm -rf AnyKernel3
rm -rf clang
rm -f *.zip
# --------------------------------

# KernelSU-Next
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1

# Some general variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
ARCH="arm64"
SUBARCH="arm64"
DEVICE="beryllium"
KERNEL_DIR="$(pwd)"

# --- CLANG TOOLCHAIN SETUP ---
echo "Downloading Prelude-Clang..."
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

COMPILERDIR="${KERNEL_DIR}/clang"
# -----------------------------

# --- OFFICIAL / STOCK MASKING OVERRIDES ---
rm -f localversion*
touch localversion
export KBUILD_BUILD_USER="root"
export KBUILD_BUILD_HOST="localhost"
# ------------------------------------------

# Files
IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb

# Clone AnyKernel
echo "Cloning AnyKernel3"
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git AnyKernel3

# Create Logs
exec 2> >(tee -a out/error.log >&2)

# Specify Final Zip Name
ZIPNAME=Etude-KSU-Next-beryllium
FINAL_ZIP=${ZIPNAME}-${DEVICE}.zip

# Colors
BUILD_START=$(date +"%s")
yellow='\033[0;33m'
nocol='\033[0m'

# --- DEFCONFIG & MERGING STEP ---
echo "Making base sdm845-perf_defconfig..."
PATH="${COMPILERDIR}/bin:${PATH}" \
make O=out ARCH=${ARCH} SUBARCH=${SUBARCH} sdm845-perf_defconfig

if [ -f "arch/arm64/configs/vendor/xiaomi/beryllium.config" ]; then
    echo "Merging beryllium device-specific config..."
    ./scripts/kconfig/merge_config.sh -O out out/.config arch/arm64/configs/vendor/xiaomi/beryllium.config
    PATH="${COMPILERDIR}/bin:${PATH}" \
    make O=out ARCH=${ARCH} SUBARCH=${SUBARCH} olddefconfig
else
    echo "Error: arch/arm64/configs/vendor/xiaomi/beryllium.config not found!"
    exit 1
fi

if [ $? -ne 0 ]
then
    echo "Defconfig/Merge failed"
    exit 1
else
    echo "Configs merged successfully"
fi
# --------------------------------

# --- NATHAN CHANCELLOR STANDALONE BUILD FUNCTION ---
Build_Standalone_Clang () {
echo "Starting compilation using Nathan Chancellor's standalone Clang variables..."

PATH="${COMPILERDIR}/bin:${PATH}" \
make -j$(nproc --all) O=out \
ARCH=${ARCH} \
SUBARCH=${SUBARCH} \
CC=clang \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
LD=ld.lld \
AR=llvm-ar \
NM=llvm-nm \
OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump \
STRIP=llvm-strip \
KCFLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion" \
KBUILD_COMPILER_STRING="Nathan Chancellor Standalone Clang"
}
# ----------------------------------------------------

# Run compilation
Build_Standalone_Clang

if [ $? -ne 0 ]
then
    echo "Build failed"
    exit 1
else
    echo "Build successful"
fi

##----------------------------------------------------------------##
zipping() {
	# Copy Files To AnyKernel3 Zip
	cp $IMAGE AnyKernel3/
	
	# Zipping and Push Kernel
	cd AnyKernel3 || exit 1
    zip -r9 ${FINAL_ZIP} *
    MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
    cd ..
}
##----------------------------------------------------------##

# Run zipping function
zipping

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
