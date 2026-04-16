# Oski macOS

This directory is the native macOS build lane. It is intentionally separate
from the Linux Docker implementation so Darwin SDK, Mach-O, `lipo`, and
install-name details cannot leak into the Alpine/musl build.

The first supported target is `macos-shared`: FFmpeg 8.0 shared libraries,
`ffmpeg`, `ffprobe`, headers, pkg-config files, `versions.json`, and
`license.json`.

## License Policy

The default macOS target keeps Oski's Linux policy:

- LGPL-3.0-or-later FFmpeg
- no `--enable-gpl`
- no FFmpeg `nonfree`
- no x264, x265, xvid, fdk-aac, davs2, xavs2, rubberband, or vid.stab
- no AMR or OpenH264 in the default target
- no Apple VideoToolbox H.264/HEVC/ProRes encoders in the default target

VideoToolbox encoders are gated for the same reason as OpenH264 and AMR: they
expose patent-encumbered encode paths. Native FFmpeg H.264/HEVC decode and
remux workflows remain available.

## Prerequisites

Run on macOS with Xcode command line tools installed. Homebrew is used only for
native build dependencies and optional non-GPL external FFmpeg libraries.

```sh
platforms/macos/homebrew-deps.sh check
platforms/macos/homebrew-deps.sh install
```

The install command is explicit on purpose; release jobs should provision these
dependencies before invoking the build.

## Build

From the repository root:

```sh
make macos-shared
make verify-macos-shared
make package-macos-shared
```

The default architecture is the native host architecture. To request a specific
slice:

```sh
make macos-shared MACOS_ARCHS=arm64
make macos-shared MACOS_ARCHS=x86_64
```

Universal builds are supported only when every enabled external dependency
contains all requested slices:

```sh
make package-macos-shared MACOS_ARCHS="arm64 x86_64"
```

The Homebrew-backed runner skips libraries listed in `OSKI_MACOS_DISABLED_LIBS`.
The default skip list currently includes `libsvtav1` because Homebrew's current
SVT-AV1 headers have drifted past FFmpeg 8.0's expected API. Once Oski pins and
source-builds that dependency for macOS, it can be moved back into the default
enabled set.

The staged artifact lands at:

```text
dist/macos/oski-8.0-macos-shared/
```

The packaged tarball lands at:

```text
dist/packages/oski-8.0-macos-shared.tar.gz
```

## Output Layout

```text
bin/ffmpeg
bin/ffprobe
include/
lib/libav*.dylib
lib/libsw*.dylib
lib/<bundled non-system dependency dylibs>
lib/pkgconfig/
versions.json
license.json
```

The binaries include `@executable_path/../lib` rpaths. FFmpeg dylibs use
`@rpath` install names so downstream projects can bundle and replace the
libraries in an LGPL-friendly way. Non-system dynamic dependencies discovered
from the build host are copied into `lib/` and rewritten to `@rpath`; Apple
frameworks and `/usr/lib` system libraries are referenced from the host OS.
