#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: platforms/macos/homebrew-deps.sh [print|check|install]

print    Print the Homebrew packages used by the macOS shared runner.
check    Report which packages are missing.
install  Install missing packages with Homebrew.
EOF
}

packages=(
  pkgconf
  nasm
  yasm
  openssl@3
  aom
  aribb24
  libass
  libbluray
  dav1d
  freetype
  fribidi
  game-music-emu
  gsm
  harfbuzz
  jpeg-xl
  kvazaar
  libmodplug
  lame
  libmysofa
  openjpeg
  opus
  rabbitmq-c
  rav1e
  librsvg
  rtmpdump
  snappy
  libsoxr
  speex
  srt
  libssh
  svt-av1
  theora
  twolame
  libvmaf
  libvorbis
  libvpx
  vvenc
  webp
  libxml2
  zimg
  zeromq
)

mode=${1:-print}

case "$mode" in
  print)
    printf '%s\n' "${packages[@]}"
    ;;
  check|install)
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew is required for '$mode' but brew was not found." >&2
      exit 1
    fi

    installed=$(brew list --formula -1)
    missing=()
    for package in "${packages[@]}"; do
      if ! grep -qx "$package" <<< "$installed"; then
        missing+=("$package")
      fi
    done

    if ((${#missing[@]} == 0)); then
      echo "OK: all macOS build dependencies are installed."
      exit 0
    fi

    if [[ "$mode" == "check" ]]; then
      printf 'Missing Homebrew packages:\n' >&2
      printf '  %s\n' "${missing[@]}" >&2
      exit 1
    fi

    brew install "${missing[@]}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
