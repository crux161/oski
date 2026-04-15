#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: build-ffmpeg.sh static|shared|amr|openh264}
shift

common_flags=(
  --extra-cflags="-fopenmp"
  --extra-ldflags="-fopenmp -Wl,--allow-multiple-definition -Wl,-z,stack-size=2097152"
  --disable-debug
  --disable-ffplay
  --disable-libdrm
  --disable-libmfx
  --disable-vaapi
  --disable-v4l2-m2m
  --disable-encoder=h264_qsv
  --disable-encoder=h264_v4l2m2m
  --disable-encoder=h264_vaapi
  --enable-version3
  --enable-fontconfig
  --enable-gray
  --enable-iconv
  --enable-lcms2
  --enable-libaom
  --enable-libaribb24
  --enable-libass
  --enable-libbluray
  --enable-libdav1d
  --enable-libfreetype
  --enable-libfribidi
  --enable-libgme
  --enable-libgsm
  --enable-libharfbuzz
  --enable-libjxl
  --enable-libkvazaar
  --enable-libmodplug
  --enable-libmp3lame
  --enable-libmysofa
  --enable-libopenjpeg
  --enable-libopus
  --enable-librabbitmq
  --enable-librav1e
  --enable-librsvg
  --enable-librtmp
  --enable-libshine
  --enable-libsnappy
  --enable-libsoxr
  --enable-libspeex
  --enable-libsrt
  --enable-libssh
  --enable-libsvtav1
  --enable-libtheora
  --enable-libtwolame
  --enable-libuavs3d
  --enable-libvmaf
  --enable-libvorbis
  --enable-libvpl
  --enable-libvpx
  --enable-libvvenc
  --enable-libwebp
  --enable-libxevd
  --enable-libxeve
  --enable-libxml2
  --enable-libzimg
  --enable-libzmq
  --enable-openssl
)

case "$mode" in
  static)
    target_flags=(--toolchain=hardened --pkg-config-flags="--static" --disable-shared --enable-static)
    ;;
  shared)
    target_flags=(
      --toolchain=hardened
      --pkg-config-flags="--static"
      --enable-shared
      --disable-static
    )
    ;;
  amr)
    target_flags=(
      --toolchain=hardened
      --pkg-config-flags="--static"
      --disable-shared
      --enable-static
      --enable-libopencore-amrnb
      --enable-libopencore-amrwb
      --enable-libvo-amrwbenc
    )
    ;;
  openh264)
    target_flags=(
      --toolchain=hardened
      --pkg-config-flags="--static"
      --disable-shared
      --enable-static
      --enable-libopenh264
    )
    ;;
  *)
    echo "unknown FFmpeg build mode: $mode" >&2
    exit 2
    ;;
esac

./configure "${common_flags[@]}" "${target_flags[@]}" "$@" || {
  cat ffbuild/config.log
  exit 1
}

if [[ "$mode" == "openh264" ]]; then
  # Keep the sidecar target dynamically linked only to libopenh264. FFmpeg's
  # per-library EXTRALIBS variables are folded into FFEXTRALIBS by the makefiles,
  # so every external-libs bucket has to be wrapped, not just the aggregate.
  # GCC adds dynamic libgomp for -fopenmp; replace that with a static libgomp
  # link so OpenH264 remains the only external runtime sidecar.
  sed -i -E \
    -e '/(^|_)LDFLAGS=/ s/(^| )-fopenmp( |$)/ /g' \
    -e '/^(EXTRALIBS[^=]*|FFEXTRALIBS)=/ s|=|=-Wl,-Bstatic |' \
    -e '/^(EXTRALIBS[^=]*|FFEXTRALIBS)=/ s|-lopenh264|-Wl,-Bdynamic -lopenh264 -Wl,-Bstatic|g' \
    -e '/^(EXTRALIBS[^=]*|FFEXTRALIBS)=/ s|$| -lgomp -Wl,-Bdynamic|' \
    ffbuild/config.mak
fi

make -j"$(nproc)"
if [[ -n "${DESTDIR:-}" ]]; then
  make DESTDIR="$DESTDIR" install
else
  make install
fi
