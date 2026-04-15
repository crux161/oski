## Oski

Oski builds FFmpeg 8.0 and ffprobe as hardened Alpine/musl artifacts for CLI use
and downstream library consumers.

The default image is LGPL-3.0-or-later, GPL-free, and FFmpeg `nonfree`-free. It
does not include GPL encoders such as x264/x265/xvid, and it does not include
patent-gated AMR or OpenH264 code.

### Which image do I pull?

| Use case | Image target | Tag |
| --- | --- | --- |
| Standalone CLI | `ffmpeg-bin` | `oski:8.0` |
| Static-link consumer | `ffmpeg-dev` | `oski:8.0-dev` |
| Dynamic-link consumer | `ffmpeg-shared` | `oski:8.0-shared` |
| H.264 encoding through Cisco OpenH264 sidecar | `openh264-runtime` | `oski:8.0-openh264` |
| AMR-NB/WB opt-in build | `amr-runtime` | `oski:8.0-amr` |

For application/library consumers such as kiri, use `oski:8.0-shared` by
default. Dynamic linking keeps LGPL compliance straightforward because end users
can replace the FFmpeg shared libraries.

### CLI Usage

```Dockerfile
COPY --from=oski:8.0 /ffmpeg /usr/local/bin/
COPY --from=oski:8.0 /ffprobe /usr/local/bin/
```

```sh
docker run -i --rm -u "$UID:$GROUPS" -v "$PWD:$PWD" -w "$PWD" oski:8.0 -i file.wav file.mp3
docker run -i --rm -u "$UID:$GROUPS" -v "$PWD:$PWD" -w "$PWD" --entrypoint=/ffprobe oski:8.0 -i file.wav
```

### Libraries

The default build keeps modern, non-GPL codec and media support:

- fontconfig, freetype, fribidi, harfbuzz, lcms2, libass, librsvg
- libaom, libdav1d, librav1e, libsvtav1, libvpx
- libkvazaar, libvvenc, libxevd, libxeve
- libopus, libvorbis, libmp3lame, libshine, libspeex, libtheora, libtwolame
- libaribb24, libbluray, libgme, libgsm, libjxl, libmodplug, libmysofa
- libopenjpeg, libwebp, libvmaf, libvpl, libxml2, libzimg
- librabbitmq, librtmp, libsrt, libssh, libzmq, openssl
- native FFmpeg decoders, demuxers, muxers, filters, and protocols enabled by the LGPL build

The default build intentionally excludes davs2, fdk-aac, rubberband, vid.stab,
x264, x265, xavs2, xvid, AMR, and OpenH264.

### Decoding H.264 and HEVC

H.264 and HEVC decode/remux workflows continue to use FFmpeg's native LGPL
decoders and demuxers. H.264 encoding is only available through
`oski:8.0-openh264`; HEVC encoding is provided by retained non-GPL encoders such
as libkvazaar.

### Linking Against Oski

Shared linking is the recommended downstream path:

```sh
docker create --name oski-shared oski:8.0-shared
docker cp oski-shared:/usr/local ./oski-ffmpeg
docker rm oski-shared

export PKG_CONFIG_PATH="$PWD/oski-ffmpeg/lib/pkgconfig"
cc -o app app.c $(pkg-config --cflags --libs libavformat libavcodec libavutil libswresample)
LD_LIBRARY_PATH="$PWD/oski-ffmpeg/lib" ./app
```

Static linking is available for consumers that can satisfy LGPL relinking
obligations:

```sh
docker create --name oski-dev oski:8.0-dev
docker cp oski-dev:/usr/local ./oski-ffmpeg
docker rm oski-dev

export PKG_CONFIG_PATH="$PWD/oski-ffmpeg/lib/pkgconfig"
cc -o app app.o $(pkg-config --static --libs libavformat libavcodec libavutil libswresample)
```

### OpenH264 Sidecar

`oski:8.0-openh264` does not ship Cisco's `libopenh264` binary. The helper
downloads the sidecar only when the user opts in:

```sh
docker run --rm --entrypoint=/usr/local/bin/oski-openh264 oski:8.0-openh264 license
docker run --rm --entrypoint=/bin/sh oski:8.0-openh264 -c \
  'oski-openh264 enable --accept-license && /ffmpeg -i input.y4m -c:v libopenh264 output.mp4'
```

Every enable/disable operation displays:

```text
OpenH264 Video Codec provided by Cisco Systems, Inc.
```

Cisco's OpenH264 binary license is at
https://www.openh264.org/BINARY_LICENSE.txt. Source-built OpenH264 is not used
for the default patent-license path.

### AMR Runtime

`oski:8.0-amr` enables opencore-amr and vo-amrwbenc. The source licenses permit
redistribution, but Oski does not grant AMR-NB or AMR-WB patent licenses.
Commercial users must obtain any required patent licenses independently.

```sh
docker run --rm --entrypoint=/usr/local/bin/oski-amr oski:8.0-amr license
```

### Files In Images

- `/ffmpeg` and `/ffprobe` in runtime targets
- `/usr/local/include`, `/usr/local/lib`, and `/usr/local/lib/pkgconfig` in dev/shared targets
- `/versions.json` with source versions and FFmpeg shared-library SONAMEs
- `/license.json` with effective target license and enabled external libraries
- `/doc`, `/etc/ssl/cert.pem`, and font/fontconfig files in runtime targets

### TLS And Fonts

TLS verification works with:

```sh
ffprobe -tls_verify 1 -ca_file /etc/ssl/cert.pem -i https://github.com/favicon.ico
```

The runtime images include small font packages and a populated fontconfig cache.
If you copy only `/ffmpeg` and `/ffprobe` into another image, install fonts and
fontconfig data there as needed.

### Version And License Inspection

```sh
docker run --rm --entrypoint=/ffmpeg oski:8.0 -hide_banner -buildconf
docker run --rm --entrypoint=/ffmpeg oski:8.0 -hide_banner -L
docker run --rm --entrypoint=/ffmpeg oski:8.0 -v quiet -f data -i /license.json -map 0 -c copy -f data -
```

### Kiri Coordination

Kiri should consume `oski:8.0-shared` by default and ship its library alongside
the FFmpeg `.so.N` files. SONAME changes in `/versions.json` are breaking Oski
releases and require a coordinated kiri release.
