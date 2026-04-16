#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

OSKI_VERSION=${OSKI_VERSION:-8.0}
FFMPEG_VERSION=${FFMPEG_VERSION:-8.0}
FFMPEG_URL=${FFMPEG_URL:-"https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2"}
FFMPEG_SHA256=${FFMPEG_SHA256:-3e74acc48ddb9f5f70b6747d3f439d51e7cc5497f097d58e5975c84488f4d186}

BUILD_ROOT=${OSKI_MACOS_BUILD_ROOT:-"$REPO_ROOT/dist/macos/build"}
SOURCE_ROOT=${OSKI_MACOS_SOURCE_ROOT:-"$REPO_ROOT/dist/macos/src"}
STAGE_ROOT=${OSKI_MACOS_STAGE_ROOT:-"$REPO_ROOT/dist/macos/stage"}
PREFIX=${OSKI_MACOS_PREFIX:-"$REPO_ROOT/dist/macos/oski-${OSKI_VERSION}-macos-shared"}
DEPLOYMENT_TARGET=${OSKI_MACOS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-12.0}}
JOBS=${OSKI_MACOS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || printf '4')}
NATIVE_ARCH=$(uname -m)
ARCHS_TEXT=${OSKI_MACOS_ARCHS:-$NATIVE_ARCH}
ALLOWLIST=${OSKI_MACOS_ALLOWLIST:-"$SCRIPT_DIR/allowed-external-libs.tsv"}
DISABLED_LIBS_TEXT=${OSKI_MACOS_DISABLED_LIBS:-libsvtav1}

dependency_search_dirs=()

die() {
  echo "error: $*" >&2
  exit 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

add_dependency_search_dir() {
  local dir=$1
  local existing
  [[ -d "$dir" ]] || return 0
  if ((${#dependency_search_dirs[@]} > 0)); then
    for existing in "${dependency_search_dirs[@]}"; do
      [[ "$existing" == "$dir" ]] && return 0
    done
  fi
  dependency_search_dirs+=("$dir")
}

join_by_colon() {
  local out=""
  local item
  for item in "$@"; do
    [[ -d "$item" ]] || continue
    out="${out:+$out:}$item"
  done
  printf '%s' "$out"
}

init_pkg_config_path() {
  local paths=()
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix=$(brew --prefix)
    paths+=("$brew_prefix/lib/pkgconfig" "$brew_prefix/share/pkgconfig")
    add_dependency_search_dir "$brew_prefix/lib"

    local formula formula_prefix
    for formula in openssl@3 libffi; do
      if formula_prefix=$(brew --prefix "$formula" 2>/dev/null); then
        paths+=("$formula_prefix/lib/pkgconfig" "$formula_prefix/share/pkgconfig")
        add_dependency_search_dir "$formula_prefix/lib"
      fi
    done
  fi

  local joined
  joined=$(join_by_colon "${paths[@]}")
  if [[ -n "$joined" ]]; then
    export PKG_CONFIG_PATH="${joined}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  fi
}

prepare_source() {
  mkdir -p "$SOURCE_ROOT"

  local archive="$SOURCE_ROOT/ffmpeg-${FFMPEG_VERSION}.tar.bz2"
  FFMPEG_SOURCE_DIR="$SOURCE_ROOT/ffmpeg-${FFMPEG_VERSION}"

  if [[ ! -x "$FFMPEG_SOURCE_DIR/configure" ]]; then
    if [[ ! -f "$archive" ]]; then
      echo "Downloading FFmpeg $FFMPEG_VERSION..."
      curl -fL "$FFMPEG_URL" -o "$archive"
    fi

    echo "${FFMPEG_SHA256}  ${archive}" | shasum -a 256 -c -

    local tmp="$SOURCE_ROOT/.extract-$$"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    tar -xjf "$archive" -C "$tmp"
    rm -rf "$FFMPEG_SOURCE_DIR"
    mv "$tmp"/ffmpeg-* "$FFMPEG_SOURCE_DIR"
    rm -rf "$tmp"
  fi
}

enabled_records=()
external_flags=()
external_cflags=""
external_ldflags=""

is_disabled_lib() {
  local candidate=$1
  local disabled
  for disabled in $DISABLED_LIBS_TEXT; do
    [[ "$candidate" == "$disabled" ]] && return 0
  done
  return 1
}

collect_external_flags() {
  require_tool pkg-config
  [[ -f "$ALLOWLIST" ]] || die "missing macOS external library allowlist: $ALLOWLIST"

  local name pc flag license version3 version
  while IFS='|' read -r name pc flag license version3; do
    [[ -n "${name:-}" ]] || continue
    [[ "$name" != \#* ]] || continue

    if ! pkg-config --exists "$pc"; then
      continue
    fi

    if is_disabled_lib "$name"; then
      echo "Skipping $name; disabled for this macOS build profile." >&2
      continue
    fi

    version=$(pkg-config --modversion "$pc" | head -n 1)
    if [[ "$name" == "libaribb24" && "$version" == "1.0.3" ]]; then
      echo "Skipping libaribb24 1.0.3; Oski requires post-1.0.3 LGPLv3 licensing." >&2
      continue
    fi

    external_flags+=("$flag")
    external_cflags+=" $(pkg-config --cflags "$pc")"
    external_ldflags+=" $(pkg-config --libs "$pc")"
    enabled_records+=("$name|$version|$license|$version3")
  done < "$ALLOWLIST"
}

configure_flags_for_arch() {
  local arch=$1
  local prefix=$2
  local sdk_path=$3
  local clang=$4
  local clangxx=$5
  local cflags="-arch ${arch} -isysroot ${sdk_path} -mmacosx-version-min=${DEPLOYMENT_TARGET} -O3 -fno-strict-overflow -fstack-protector-strong -fPIC ${external_cflags}"
  local ldflags="-arch ${arch} -isysroot ${sdk_path} -mmacosx-version-min=${DEPLOYMENT_TARGET} ${external_ldflags}"
  local host_cflags="-isysroot ${sdk_path} -mmacosx-version-min=${DEPLOYMENT_TARGET}"
  local host_ldflags="-isysroot ${sdk_path} -mmacosx-version-min=${DEPLOYMENT_TARGET}"

  CONFIGURE_FLAGS=(
    "--prefix=$prefix"
    "--install-name-dir=@rpath"
    "--target-os=darwin"
    "--arch=$arch"
    "--cc=$clang"
    "--cxx=$clangxx"
    "--host-cc=$clang"
    "--host-cflags=$host_cflags"
    "--host-ld=$clang"
    "--host-ldflags=$host_ldflags"
    "--pkg-config=pkg-config"
    "--disable-debug"
    "--disable-doc"
    "--disable-ffplay"
    "--disable-libxcb"
    "--disable-xlib"
    "--enable-pic"
    "--enable-shared"
    "--disable-static"
    "--enable-version3"
    "--enable-gray"
    "--enable-iconv"
    "--disable-encoder=h264_videotoolbox"
    "--disable-encoder=hevc_videotoolbox"
    "--disable-encoder=prores_videotoolbox"
    "--disable-encoder=libopenh264"
    "--disable-encoder=libx264"
    "--disable-encoder=libx265"
    "--disable-encoder=libxvid"
    "--disable-encoder=libfdk_aac"
    "--disable-encoder=libopencore_amrnb"
    "--disable-encoder=libopencore_amrwb"
    "--disable-encoder=libvo_amrwbenc"
    "--extra-cflags=$cflags"
    "--extra-cxxflags=$cflags"
    "--extra-ldflags=$ldflags"
    "${external_flags[@]}"
  )
}

relocate_install_names() {
  local root=$1
  local file dep base dylib

  while IFS= read -r dylib; do
    base=$(basename "$dylib")
    install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
  done < <(find "$root/lib" -type f -name 'lib*.dylib' 2>/dev/null | sort)

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    while IFS= read -r dep; do
      base=$(basename "$dep")
      install_name_tool -change "$dep" "@rpath/$base" "$file" 2>/dev/null || true
    done < <(otool -L "$file" 2>/dev/null | awk -v prefix="$root/lib/" 'index($1, prefix) == 1 { print $1 }')

    case "$file" in
      "$root"/bin/*)
        install_name_tool -add_rpath "@executable_path/../lib" "$file" 2>/dev/null || true
        ;;
      "$root"/lib/*.dylib)
        install_name_tool -add_rpath "@loader_path" "$file" 2>/dev/null || true
        ;;
    esac
  done < <(
    {
      find "$root/bin" -type f 2>/dev/null
      find "$root/lib" -type f -name 'lib*.dylib' 2>/dev/null
    } | sort
  )
}

mach_o_files() {
  local root=$1
  {
    find "$root/bin" -type f 2>/dev/null
    find "$root/lib" -type f -name '*.dylib' 2>/dev/null
  } | sort
}

is_system_dependency() {
  local dep=$1
  case "$dep" in
    @rpath/*|@loader_path/*|@executable_path/*)
      return 0
      ;;
    /usr/lib/*|/System/Library/*)
      return 0
      ;;
  esac
  return 1
}

resolve_dependency_path() {
  local root=$1
  local file=$2
  local dep=$3
  local base rel candidate dir

  case "$dep" in
    /usr/lib/*|/System/Library/*)
      return 1
      ;;
    @rpath/*)
      base=$(basename "$dep")
      if [[ -f "$root/lib/$base" ]]; then
        printf '%s\n' "$root/lib/$base"
        return 0
      fi
      if ((${#dependency_search_dirs[@]} > 0)); then
        for dir in "${dependency_search_dirs[@]}"; do
          candidate="$dir/$base"
          if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
      fi
      return 2
      ;;
    @loader_path/*)
      rel=${dep#@loader_path/}
      candidate="$(dirname "$file")/$rel"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      base=$(basename "$dep")
      if ((${#dependency_search_dirs[@]} > 0)); then
        for dir in "${dependency_search_dirs[@]}"; do
          candidate="$dir/$base"
          if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
      fi
      return 2
      ;;
    @executable_path/*)
      rel=${dep#@executable_path/}
      candidate="$root/bin/$rel"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      base=$(basename "$dep")
      if ((${#dependency_search_dirs[@]} > 0)); then
        for dir in "${dependency_search_dirs[@]}"; do
          candidate="$dir/$base"
          if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
      fi
      return 2
      ;;
    /*)
      [[ -f "$dep" ]] || return 2
      printf '%s\n' "$dep"
      return 0
      ;;
  esac

  return 1
}

rewrite_dependency_paths() {
  local root=$1
  local file dep base

  while IFS= read -r file; do
    while IFS= read -r dep; do
      is_system_dependency "$dep" && continue
      base=$(basename "$dep")
      if [[ -f "$root/lib/$base" ]]; then
        install_name_tool -change "$dep" "@rpath/$base" "$file" 2>/dev/null || true
      fi
    done < <(otool -L "$file" 2>/dev/null | awk 'NR > 1 { print $1 }')
  done < <(mach_o_files "$root")
}

bundle_dynamic_dependencies() {
  local root=$1
  local changed=1
  local pass=0
  local file dep source_dep status base dest dylib

  while ((changed)); do
    changed=0
    pass=$((pass + 1))
    ((pass < 50)) || die "dynamic dependency bundling did not converge"

    while IFS= read -r file; do
      while IFS= read -r dep; do
        if source_dep=$(resolve_dependency_path "$root" "$file" "$dep"); then
          :
        else
          status=$?
          [[ "$status" -eq 1 ]] && continue
          die "non-system dependency not found for $(basename "$file"): $dep"
        fi

        base=$(basename "$source_dep")
        dest="$root/lib/$base"
        add_dependency_search_dir "$(dirname "$source_dep")"
        if [[ ! -e "$dest" ]]; then
          cp -p "$source_dep" "$dest"
          chmod u+w "$dest" 2>/dev/null || true
          install_name_tool -id "@rpath/$base" "$dest" 2>/dev/null || true
          changed=1
        fi
      done < <(otool -L "$file" 2>/dev/null | awk 'NR > 1 { print $1 }')
    done < <(mach_o_files "$root")

    rewrite_dependency_paths "$root"
  done

  while IFS= read -r dylib; do
    base=$(basename "$dylib")
    install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
  done < <(find "$root/lib" -type f -name '*.dylib' 2>/dev/null | sort)

  rewrite_dependency_paths "$root"
}

ad_hoc_sign_mach_o() {
  local root=$1
  local file

  command -v codesign >/dev/null 2>&1 || return 0
  while IFS= read -r file; do
    codesign --force --sign - "$file" >/dev/null 2>&1 || true
  done < <(mach_o_files "$root")
}

build_arch() {
  local arch=$1
  local sdk_path=$2
  local clang=$3
  local clangxx=$4
  local build_dir="$BUILD_ROOT/shared/$arch"
  local prefix="$STAGE_ROOT/$arch"

  echo "Building FFmpeg $FFMPEG_VERSION for macOS $arch..."
  rm -rf "$build_dir" "$prefix"
  mkdir -p "$build_dir" "$prefix"

  configure_flags_for_arch "$arch" "$prefix" "$sdk_path" "$clang" "$clangxx"

  (
    export SDKROOT="$sdk_path"
    export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    cd "$build_dir"
    "$FFMPEG_SOURCE_DIR/configure" "${CONFIGURE_FLAGS[@]}" || {
      cat ffbuild/config.log
      exit 1
    }
    make -j"$JOBS"
    make install
  )

  relocate_install_names "$prefix"
}

copy_tree() {
  local from=$1
  local to=$2
  mkdir -p "$to"
  (cd "$from" && tar -cf - .) | (cd "$to" && tar -xf -)
}

rewrite_pkgconfig_prefixes() {
  [[ -d "$PREFIX/lib/pkgconfig" ]] || return 0
  while IFS= read -r pc; do
    sed -i '' \
      -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
      -e 's|^libdir=.*|libdir=${prefix}/lib|' \
      -e 's|^includedir=.*|includedir=${prefix}/include|' \
      "$pc"
  done < <(find "$PREFIX/lib/pkgconfig" -type f -name '*.pc' | sort)
}

merge_arches() {
  local archs=("$@")
  local first="${archs[0]}"
  local first_root="$STAGE_ROOT/$first"
  local arch root file base lib inputs=()

  rm -rf "$PREFIX"
  mkdir -p "$PREFIX"

  if ((${#archs[@]} == 1)); then
    copy_tree "$first_root" "$PREFIX"
    rewrite_pkgconfig_prefixes
    relocate_install_names "$PREFIX"
    return 0
  fi

  echo "Merging macOS architectures: ${archs[*]}"
  mkdir -p "$PREFIX/bin" "$PREFIX/lib"
  [[ -d "$first_root/include" ]] && copy_tree "$first_root/include" "$PREFIX/include"
  [[ -d "$first_root/lib/pkgconfig" ]] && copy_tree "$first_root/lib/pkgconfig" "$PREFIX/lib/pkgconfig"
  [[ -d "$first_root/share" ]] && copy_tree "$first_root/share" "$PREFIX/share"

  for file in ffmpeg ffprobe; do
    inputs=()
    for arch in "${archs[@]}"; do
      root="$STAGE_ROOT/$arch"
      [[ -f "$root/bin/$file" ]] && inputs+=("$root/bin/$file")
    done
    if ((${#inputs[@]} > 0)); then
      lipo -create "${inputs[@]}" -output "$PREFIX/bin/$file"
      chmod 755 "$PREFIX/bin/$file"
    fi
  done

  while IFS= read -r lib; do
    base=$(basename "$lib")
    inputs=()
    for arch in "${archs[@]}"; do
      root="$STAGE_ROOT/$arch"
      [[ -f "$root/lib/$base" ]] && inputs+=("$root/lib/$base")
    done
    if ((${#inputs[@]} == ${#archs[@]})); then
      lipo -create "${inputs[@]}" -output "$PREFIX/lib/$base"
      local unversioned=${base%%.*}.dylib
      ln -sf "$base" "$PREFIX/lib/$unversioned"
    fi
  done < <(find "$first_root/lib" -maxdepth 1 -type f -name 'lib*.dylib' | sort)

  rewrite_pkgconfig_prefixes
  relocate_install_names "$PREFIX"
}

json_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    if ((first)); then
      first=0
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

bundled_dependency_names() {
  local dylib base
  while IFS= read -r dylib; do
    base=$(basename "$dylib")
    case "$base" in
      libav*|libsw*)
        continue
        ;;
    esac
    printf '%s\n' "$base"
  done < <(find "$PREFIX/lib" -maxdepth 1 -type f -name '*.dylib' | sort)
}

write_versions_json() {
  local archs=("$@")
  local avformat avcodec avdevice avfilter avutil swresample swscale
  local bundled=()
  avformat=$(resolved_dylib_name libavformat)
  avcodec=$(resolved_dylib_name libavcodec)
  avdevice=$(resolved_dylib_name libavdevice)
  avfilter=$(resolved_dylib_name libavfilter)
  avutil=$(resolved_dylib_name libavutil)
  swresample=$(resolved_dylib_name libswresample)
  swscale=$(resolved_dylib_name libswscale)
  while IFS= read -r dep; do
    [[ -n "$dep" ]] && bundled+=("$dep")
  done < <(bundled_dependency_names)

  cat > "$PREFIX/versions.json" <<EOF
{
  "ffmpeg": "$(json_escape "$FFMPEG_VERSION")",
  "target": "macos-shared",
  "platform": "macos",
  "deployment_target": "$(json_escape "$DEPLOYMENT_TARGET")",
  "archs": $(json_array "${archs[@]}"),
  "dylibs": {
    "libavformat": "$(json_escape "$avformat")",
    "libavcodec": "$(json_escape "$avcodec")",
    "libavdevice": "$(json_escape "$avdevice")",
    "libavfilter": "$(json_escape "$avfilter")",
    "libavutil": "$(json_escape "$avutil")",
    "libswresample": "$(json_escape "$swresample")",
    "libswscale": "$(json_escape "$swscale")"
  },
  "bundled_dynamic_dependencies": $(json_array "${bundled[@]}")
}
EOF
}

resolved_dylib_name() {
  local lib=$1
  local link="$PREFIX/lib/${lib}.dylib"
  local target

  if [[ -L "$link" ]]; then
    readlink "$link"
    return 0
  fi

  target=$(find "$PREFIX/lib" -maxdepth 1 -type f -name "${lib}*.dylib" | sort | head -n 1)
  [[ -n "$target" ]] || die "could not resolve dylib for $lib"
  basename "$target"
}

write_license_json() {
  local record name version license version3 first
  local version3_items=()

  for record in "${enabled_records[@]}"; do
    IFS='|' read -r name version license version3 <<< "$record"
    [[ "$version3" == "-" ]] || version3_items+=("$version3")
  done

  {
    printf '{\n'
    printf '  "effective_license": "LGPL-3.0-or-later",\n'
    printf '  "ffmpeg_version": "%s",\n' "$(json_escape "$FFMPEG_VERSION")"
    printf '  "target": "macos-shared",\n'
    printf '  "platform": "macos",\n'
    printf '  "version3_required_by": '
    json_array "${version3_items[@]}"
    printf ',\n'
    printf '  "enabled_external_libs": [\n'
    first=1
    for record in "${enabled_records[@]}"; do
      IFS='|' read -r name version license version3 <<< "$record"
      if ((first)); then
        first=0
      else
        printf ',\n'
      fi
      printf '    { "name": "%s", "version": "%s", "license": "%s" }' \
        "$(json_escape "$name")" "$(json_escape "$version")" "$(json_escape "$license")"
    done
    printf '\n  ],\n'
    printf '  "gpl": false,\n'
    printf '  "nonfree": false,\n'
    printf '  "patent_encumbered_opt_in_only": ["h264", "amr"],\n'
    printf '  "bundled_dynamic_dependency_policy": "non-system dylibs are copied beside FFmpeg dylibs and rewritten to @rpath; system libraries and Apple frameworks are not bundled"\n'
    printf '}\n'
  } > "$PREFIX/license.json"
}

main() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS shared builds must run on macOS"
  require_tool xcrun
  require_tool curl
  require_tool shasum
  require_tool make
  require_tool otool
  require_tool install_name_tool
  require_tool lipo

  init_pkg_config_path
  prepare_source
  collect_external_flags

  read -r -a ARCHS <<< "$ARCHS_TEXT"
  ((${#ARCHS[@]} > 0)) || die "OSKI_MACOS_ARCHS produced no architectures"

  if ((${#ARCHS[@]} > 1)); then
    echo "Note: universal macOS builds require all external dependencies to contain ${ARCHS[*]} slices." >&2
  fi

  local sdk_path clang clangxx arch
  sdk_path=$(xcrun --sdk macosx --show-sdk-path)
  clang=$(xcrun --sdk macosx --find clang)
  clangxx=$(xcrun --sdk macosx --find clang++)

  for arch in "${ARCHS[@]}"; do
    case "$arch" in
      arm64|x86_64)
        build_arch "$arch" "$sdk_path" "$clang" "$clangxx"
        ;;
      *)
        die "unsupported macOS architecture '$arch' (expected arm64 or x86_64)"
        ;;
    esac
  done

  merge_arches "${ARCHS[@]}"
  bundle_dynamic_dependencies "$PREFIX"
  ad_hoc_sign_mach_o "$PREFIX"
  write_versions_json "${ARCHS[@]}"
  write_license_json

  "$SCRIPT_DIR/verify-license.sh" "$PREFIX"
  echo "macOS shared artifact staged at $PREFIX"
}

main "$@"
