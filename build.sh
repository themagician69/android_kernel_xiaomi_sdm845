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
    
    # Disable IOMMU debug to fix struct dev_archdata mapping build error
    echo "CONFIG_IOMMU_DEBUG=n" >> out/.config
    
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

# --- PYTHON COMPILER-GCC.H PATCH ---
echo "Patching include/linux/compiler-gcc.h via Python..."
python3 -c '
file_path = "include/linux/compiler-gcc.h"
with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "version of GCC is too old" in line or "5.1 or newer" in line:
        new_lines.append("/* " + line.strip() + " */\n")
    elif "__GNUC__ < 5" in line:
        new_lines.append(line.replace("__GNUC__ < 5", "__GNUC__ < 4"))
    else:
        new_lines.append(line)

with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
print("compiler-gcc.h patched successfully.")
'
# ------------------------------------

# --- PATCH ADSPRPC PROTOTYPE ---
echo "Injecting forward declaration for ion_import_dma_buf_fd into drivers/char/adsprpc.c..."
python3 -c '
path = "drivers/char/adsprpc.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

declaration = "\nstruct ion_client;\nstruct ion_handle *ion_import_dma_buf_fd(struct ion_client *client, int fd);\n"
if "ion_import_dma_buf_fd" in content and "struct ion_handle *ion_import_dma_buf_fd" not in content:
    content = declaration + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected forward declaration successfully.")
'
# ---------------------------------

# --- PATCH EXTCON-GPIO PINCTRL HEADER ---
echo "Injecting pinctrl consumer header into drivers/extcon/extcon-gpio.c..."
python3 -c '
path = "drivers/extcon/extcon-gpio.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

include_str = "#include <linux/pinctrl/consumer.h>\n"
if "pinctrl/consumer.h" not in content:
    content = include_str + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected pinctrl header successfully.")
'
# ----------------------------------------

# --- PATCH HBTP_INPUT PINCTRL HEADER ---
echo "Injecting pinctrl consumer header into drivers/input/misc/hbtp_input.c..."
python3 -c '
path = "drivers/input/misc/hbtp_input.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

include_str = "#include <linux/pinctrl/consumer.h>\n"
if "pinctrl/consumer.h" not in content:
    content = include_str + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected pinctrl header into hbtp_input.c successfully.")
'
# ----------------------------------------

# --- PATCH FOCALTECH CORE PINCTRL HEADER ---
echo "Injecting pinctrl consumer header into Focaltech touchscreen core..."
python3 -c '
path = "drivers/input/touchscreen/focaltech_touch/focaltech_core.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

include_str = "#include <linux/pinctrl/consumer.h>\n"
if "pinctrl/consumer.h" not in content:
    content = include_str + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected pinctrl header into focaltech_core.c successfully.")
'
# -------------------------------------------

# --- PATCH NT36XXX TOUCHSCREEN PINCTRL HEADER ---
echo "Injecting pinctrl consumer header into NT36XXX touchscreen driver..."
python3 -c '
path = "drivers/input/touchscreen/nt36xxx/nt36xxx.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

include_str = "#include <linux/pinctrl/consumer.h>\n"
if "pinctrl/consumer.h" not in content:
    content = include_str + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected pinctrl header into nt36xxx.c successfully.")
'
# ----------------------------------------------

# --- PATCH SYNAPTICS_DSX TOUCHSCREEN PINCTRL HEADER ---
echo "Injecting pinctrl consumer header into Synaptics DSX touchscreen driver..."
python3 -c '
path = "drivers/input/touchscreen/synaptics_dsx/synaptics_dsx_core.c"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

include_str = "#include <linux/pinctrl/consumer.h>\n"
if "pinctrl/consumer.h" not in content:
    content = include_str + content
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Injected pinctrl header into synaptics_dsx_core.c successfully.")
'

# --- PATCH MSM_ION.H UNUSED FUNCTION WARNING ---
echo "Patching drivers/staging/android/ion/msm/msm_ion.h to suppress unused-function warning..."
python3 -c '
path = "drivers/staging/android/ion/msm/msm_ion.h"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "static bool is_buffer_hlos_assigned" in content and "__maybe_unused" not in content:
    content = content.replace("static bool is_buffer_hlos_assigned", "static __maybe_unused bool is_buffer_hlos_assigned")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Patched msm_ion.h successfully.")
'
# -----------------------------------------------

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
