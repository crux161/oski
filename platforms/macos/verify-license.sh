#!/usr/bin/env bash
set -euo pipefail

prefix=${1:-${OSKI_MACOS_PREFIX:-dist/macos/oski-8.0-macos-shared}}
ffmpeg=${FFMPEG:-"$prefix/bin/ffmpeg"}
ffprobe=${FFPROBE:-"$prefix/bin/ffprobe"}
libdir=${LIBDIR:-"$prefix/lib"}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$ffmpeg" ]] || fail "ffmpeg not found at $ffmpeg"
[[ -x "$ffprobe" ]] || fail "ffprobe not found at $ffprobe"

export DYLD_LIBRARY_PATH="${libdir}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${libdir}/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

buildconf=$("$ffmpeg" -hide_banner -buildconf 2>&1)
for flag in \
  --enable-gpl \
  --enable-nonfree \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libxvid \
  --enable-libfdk-aac \
  --enable-libdavs2 \
  --enable-libxavs2 \
  --enable-librubberband \
  --enable-libvidstab \
  --enable-libopenh264 \
  --enable-libopencore-amrnb \
  --enable-libopencore-amrwb \
  --enable-libvo-amrwbenc
do
  if grep -q -- "$flag" <<< "$buildconf"; then
    fail "forbidden configure flag present: $flag"
  fi
done

encoders=$("$ffmpeg" -hide_banner -encoders 2>&1)
for codec in \
  libx264 \
  libx265 \
  libxvid \
  libfdk_aac \
  libdavs2 \
  libxavs2 \
  libopenh264 \
  libopencore_amrnb \
  libopencore_amrwb \
  libvo_amrwbenc \
  h264_videotoolbox \
  hevc_videotoolbox \
  prores_videotoolbox
do
  if grep -qw "$codec" <<< "$encoders"; then
    fail "forbidden encoder registered: $codec"
  fi
done

license_text=$("$ffmpeg" -hide_banner -L 2>&1)
if grep -qE '\bGPL\b' <<< "$license_text" && ! grep -qE '\bLGPL\b' <<< "$license_text"; then
  fail "binary reports GPL license"
fi
if grep -qi 'nonfree' <<< "$license_text"; then
  fail "binary reports nonfree license"
fi

for binary in "$ffmpeg" "$ffprobe"; do
  if ! otool -l "$binary" | grep -q '@executable_path/../lib'; then
    fail "$(basename "$binary") does not include @executable_path/../lib rpath"
  fi
done

for lib in \
  libavformat \
  libavcodec \
  libavdevice \
  libavfilter \
  libavutil \
  libswresample \
  libswscale
do
  link="$libdir/$lib.dylib"
  [[ -e "$link" ]] || fail "expected dylib link missing: $link"
  if [[ -L "$link" ]]; then
    target=$(readlink "$link")
  else
    target=$(basename "$link")
  fi
  path="$libdir/$target"
  [[ -f "$path" ]] || fail "expected dylib target missing: $path"
  id=$(otool -D "$path" | tail -n 1)
  [[ "$id" == "@rpath/$target" ]] || fail "$target install name is '$id', expected '@rpath/$target'"
done

while IFS= read -r file; do
  while IFS= read -r dep; do
    case "$dep" in
      /opt/homebrew/*|/usr/local/*|/opt/local/*)
        fail "$(basename "$file") still references non-system dependency path: $dep"
        ;;
    esac
  done < <(otool -L "$file" 2>/dev/null | awk 'NR > 1 { print $1 }')

  if [[ "$file" == "$libdir"/*.dylib ]]; then
    base=$(basename "$file")
    id=$(otool -D "$file" | tail -n 1)
    [[ "$id" == "@rpath/$base" ]] || fail "$base install name is '$id', expected '@rpath/$base'"
  fi
done < <(
  {
    find "$(dirname "$ffmpeg")" -type f 2>/dev/null
    find "$libdir" -type f -name '*.dylib' 2>/dev/null
  } | sort
)

if command -v pkg-config >/dev/null 2>&1; then
  pkg-config --libs libavformat libavcodec libavutil libswresample libswscale >/dev/null
fi

echo "OK: macOS shared license gate passed for $prefix"
