#!/usr/bin/env bash
# shellcheck disable=SC2199
# shellcheck source=/dev/null
#
# Copyright (C) 2020-22 UtsavBalar1231 <utsavbalar1231@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CLANG_DIR=~/android/aospa/prebuilts/clang/host/linux-x86/clang-r498229b
GCC_64_DIR=~/android/aospa/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9

DEVICE=${1:?"No device parameter provided. Usage: $0 <device>"}
DEFCONFIG=${DEVICE}_defconfig

DATE=$(date '+%Y%m%d-%H%M')
LOCALVERSION=$(sed -n 's/^.*CONFIG_LOCALVERSION="\([^"]*\)".*$/\1/p' arch/arm64/configs/"$DEFCONFIG")
zipname="AnyKernel3-${DEVICE}${LOCALVERSION}-${DATE}.zip"

function Build() {
	if ! [ -d "${CLANG_DIR}" ]; then
		echo "aosp clang not found! Cloning..."
		if ! git clone -q https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone.git --depth=1 $CLANG_DIR; then
			echo "Cloning failed! Aborting..."
			exit 1
		fi
	fi

	if ! [ -d "${GCC_64_DIR}" ]; then
		echo "aarch64-linux-android-4.9 not found! Cloning..."
		if ! git clone -q https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 --single-branch $GCC_64_DIR; then
			echo "Cloning failed! Aborting..."
			exit 1
		fi
	fi

	KBUILD_COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
	KBUILD_LINKER_STRING=$(${CLANG_DIR}/bin/ld.lld --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' | sed 's/(compatible with [^)]*)//')
	export KBUILD_COMPILER_STRING
	export KBUILD_LINKER_STRING

	#
	# Enviromental Variables
	#

	# Set our directory
	OUT_DIR=out/

	# How much kebabs we need? Kanged from @raphielscape :)
	if [[ -z "${KEBABS}" ]]; then
		COUNT="$(grep -c '^processor' /proc/cpuinfo)"
		export KEBABS="$((COUNT + 2))"
	fi

	echo "Jobs: ${KEBABS}"

	ARGS="ARCH=arm64 \
		O=${OUT_DIR} \
		CC=clang \
		LLVM=1 \
		LLVM_IAS=1 \
		CLANG_TRIPLE=aarch64-linux-gnu- \
		CROSS_COMPILE=${GCC_64_DIR}/bin/aarch64-linux-android- \
		-j${KEBABS}"

	dts_source=arch/arm64/boot/dts/vendor/qcom

	# Set compiler Path
	export PATH="${CLANG_DIR}/bin:$PATH"
	export LD_LIBRARY_PATH=${CLANG_DIR}/lib64:$LD_LIBRARY_PATH

	echo "------ Starting Compilation ------"

	# Make defconfig
	make -j${KEBABS} ${ARGS} ${DEFCONFIG}

	# Make olddefconfig
	cd ${OUT_DIR} || exit
	make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="cache g++" olddefconfig
	cd ../ || exit

	make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="ccache g++" 2>&1 | tee build.log

	find ${OUT_DIR}/$dts_source -name '*.dtb' -exec cat {} + >${OUT_DIR}/arch/arm64/boot/dtb

	git checkout arch/arm64/boot/dts/vendor &>/dev/null

	echo "------ Finishing Build ------"
}

function AnyKernel3() {
	echo -e "\nPackaging into AnyKernel3..."
	if [ ! -f "out/arch/arm64/boot/Image" ] \
	|| [ ! -f "out/arch/arm64/boot/dtbo.img" ] \
	|| [ ! -f "out/arch/arm64/boot/dtb" ]; then
		echo -e "\n Compilation Failed!"
		exit 1
	fi

	AK3_DIR=~/android/AnyKernel3

	if [ ! -d $AK3_DIR ]; then
		git clone https://github.com/madmax7896/AnyKernel3 -b "$DEVICE" --depth=1 $AK3_DIR || return 1
	fi

	cp -r $AK3_DIR ak3-tmp
	cp out/arch/arm64/boot/Image ak3-tmp
	cp out/arch/arm64/boot/dtb ak3-tmp
	cp out/arch/arm64/boot/dtbo.img ak3-tmp
	rm -f ./*zip
	cd ak3-tmp || exit
	zip -r9 "../${zipname}" ./* -x '*.git*' README.md ./*placeholder >>/dev/null
	cd ..
	rm -rf ak3-tmp
	echo -e "\n${zipname} is ready!"
}

Build "$@"
AnyKernel3

echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
