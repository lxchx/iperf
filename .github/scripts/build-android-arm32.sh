#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_NDK_VERSION:=r26d}"
: "${ANDROID_API:=21}"

work_root="${RUNNER_TEMP:-/tmp}"
ndk_root="${work_root}/android-ndk-${ANDROID_NDK_VERSION}"
ndk_zip="${work_root}/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"
toolchain="${ndk_root}/toolchains/llvm/prebuilt/linux-x86_64"
out_dir="${PWD}/out/android-arm32"

if [ ! -d "${ndk_root}" ]; then
    curl -fL -o "${ndk_zip}" \
        "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"
    unzip -q "${ndk_zip}" -d "${work_root}"
fi

export CC="${toolchain}/bin/armv7a-linux-androideabi${ANDROID_API}-clang"
export CXX="${toolchain}/bin/armv7a-linux-androideabi${ANDROID_API}-clang++"
export AR="${toolchain}/bin/llvm-ar"
export AS="${CC}"
export RANLIB="${toolchain}/bin/llvm-ranlib"
export STRIP="${toolchain}/bin/llvm-strip"

make distclean >/dev/null 2>&1 || true

./configure \
    --host=arm-linux-androideabi \
    --disable-shared \
    --enable-static \
    --with-openssl=no

make -j"$(nproc)"

mkdir -p "${out_dir}"
cp -a src/iperf3 "${out_dir}/iperf3"
"${STRIP}" "${out_dir}/iperf3" || true
gzip -9 -n -c "${out_dir}/iperf3" > "${out_dir}/iperf3-android-arm32.gz"
