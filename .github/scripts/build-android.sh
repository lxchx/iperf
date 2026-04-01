#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_NDK_VERSION:=r26d}"
: "${ANDROID_API:=21}"
: "${ANDROID_TARGET:?ANDROID_TARGET must be set to arm32 or arm64}"

work_root="${RUNNER_TEMP:-/tmp}"
ndk_root="${work_root}/android-ndk-${ANDROID_NDK_VERSION}"
ndk_zip="${work_root}/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"
toolchain="${ndk_root}/toolchains/llvm/prebuilt/linux-x86_64"

case "${ANDROID_TARGET}" in
    arm32)
        host="arm-linux-androideabi"
        clang_target="armv7a-linux-androideabi${ANDROID_API}"
        out_dir="${PWD}/out/android-arm32"
        out_gz="iperf3-android-arm32.gz"
        ;;
    arm64)
        host="aarch64-linux-android"
        clang_target="aarch64-linux-android${ANDROID_API}"
        out_dir="${PWD}/out/android-arm64"
        out_gz="iperf3-android-arm64.gz"
        ;;
    *)
        echo "Unsupported ANDROID_TARGET: ${ANDROID_TARGET}" >&2
        exit 1
        ;;
esac

if [ ! -d "${ndk_root}" ]; then
    curl -fL -o "${ndk_zip}" \
        "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"
    unzip -q "${ndk_zip}" -d "${work_root}"
fi

export CC="${toolchain}/bin/${clang_target}-clang"
export CXX="${toolchain}/bin/${clang_target}-clang++"
export AR="${toolchain}/bin/llvm-ar"
export AS="${CC}"
export RANLIB="${toolchain}/bin/llvm-ranlib"
export STRIP="${toolchain}/bin/llvm-strip"

make distclean >/dev/null 2>&1 || true

./configure \
    --host="${host}" \
    --disable-shared \
    --enable-static \
    --with-openssl=no

make -j"$(nproc)"

mkdir -p "${out_dir}"
cp -a src/iperf3 "${out_dir}/iperf3"
"${STRIP}" "${out_dir}/iperf3" || true
gzip -9 -n -c "${out_dir}/iperf3" > "${out_dir}/${out_gz}"
