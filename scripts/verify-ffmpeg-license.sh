#!/bin/sh
set -eu

FFMPEG=${FFMPEG:-/ffmpeg}
PROBE=${PROBE:-/ffprobe}
TARGET=${TARGET:-unknown}
LIBDIR=${LIBDIR:-/usr/local/lib}

BUILDCONF=$("$FFMPEG" -hide_banner -buildconf 2>&1)
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
    --enable-libvidstab
do
    if echo "$BUILDCONF" | grep -q -- "$flag"; then
        echo "FAIL: forbidden flag present: $flag" >&2
        exit 1
    fi
done

ENCODERS=$("$FFMPEG" -hide_banner -encoders 2>&1)
for codec in libx264 libx265 libxvid libfdk_aac libdavs2 libxavs2 h264_qsv h264_v4l2m2m h264_vaapi; do
    if echo "$ENCODERS" | grep -qw "$codec"; then
        echo "FAIL: forbidden encoder registered: $codec" >&2
        exit 1
    fi
done

case "$TARGET" in
    openh264-runtime)
        ;;
    *)
        if echo "$ENCODERS" | grep -qw 'libopenh264'; then
            echo "FAIL: OpenH264 encoder present outside openh264-runtime" >&2
            exit 1
        fi
        ;;
esac

case "$TARGET" in
    amr-runtime)
        ;;
    *)
        for codec in libopencore_amrnb libvo_amrwbenc; do
            if echo "$ENCODERS" | grep -qw "$codec"; then
                echo "FAIL: AMR encoder present outside amr-runtime: $codec" >&2
                exit 1
            fi
        done
        ;;
esac

LICENSE_TEXT=$("$FFMPEG" -hide_banner -L 2>&1)
if echo "$LICENSE_TEXT" | grep -qE '\bGPL\b' && ! echo "$LICENSE_TEXT" | grep -qE '\bLGPL\b'; then
    echo "FAIL: binary reports GPL license" >&2
    exit 1
fi
if echo "$LICENSE_TEXT" | grep -qi 'nonfree'; then
    echo "FAIL: binary reports nonfree license" >&2
    exit 1
fi

case "$TARGET" in
    ffmpeg-bin|amr-runtime)
        /checkelf "$FFMPEG"
        /checkelf "$PROBE"
        ;;
    ffmpeg-dev)
        pkg-config --static --libs libavformat libavcodec libavutil libswresample libswscale >/dev/null
        ;;
    ffmpeg-shared)
        for lib in libavformat libavcodec libavdevice libavfilter libavutil libswresample libswscale; do
            actual=$(readelf -d "${LIBDIR}/${lib}.so" | awk '/SONAME/ {print $NF}' | tr -d '[]')
            expected=$(jq -r ".sonames.${lib}" /versions.json)
            if [ "$actual" != "$expected" ]; then
                echo "FAIL: ${lib} SONAME mismatch: built=$actual expected=$expected" >&2
                exit 1
            fi
        done
        ;;
    openh264-runtime)
        needed=$(readelf -d "$FFMPEG" | awk '/NEEDED/ {print $NF}' | tr -d '[]')
        for lib in $needed; do
            case "$lib" in
                libopenh264.so.*|libc.musl-*.so.*)
                    ;;
                *)
                    echo "FAIL: unexpected OpenH264 runtime dependency: $lib" >&2
                    exit 1
                    ;;
            esac
        done
        ;;
esac

echo "OK: license gate passed for target $TARGET"
