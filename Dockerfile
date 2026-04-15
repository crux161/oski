# bump: alpine /ALPINE_VERSION=alpine:([\d.]+)/ docker:alpine|^3
# bump: alpine link "Release notes" https://alpinelinux.org/posts/Alpine-$LATEST-released.html
ARG ALPINE_VERSION=alpine:3.20.3
FROM $ALPINE_VERSION AS builder

# Alpine Package Keeper options
ARG APK_OPTS=""

RUN apk add --no-cache $APK_OPTS \
  coreutils \
  pkgconfig \
  wget \
  rust cargo cargo-c \
  openssl-dev openssl-libs-static \
  ca-certificates \
  bash \
  tar \
  build-base \
  autoconf automake \
  libtool \
  diffutils \
  cmake meson ninja \
  git \
  yasm nasm \
  texinfo \
  jq \
  zlib-dev zlib-static \
  bzip2-dev bzip2-static \
  libxml2-dev libxml2-static \
  expat-dev expat-static \
  fontconfig-dev fontconfig-static \
  freetype freetype-dev freetype-static \
  graphite2-static \
  tiff tiff-dev \
  libjpeg-turbo libjpeg-turbo-dev \
  libpng-dev libpng-static \
  giflib giflib-dev \
  fribidi-dev fribidi-static \
  brotli-dev brotli-static \
  soxr-dev soxr-static \
  tcl \
  numactl-dev \
  cunit cunit-dev \
  vo-amrwbenc-dev vo-amrwbenc-static \
  snappy snappy-dev snappy-static \
  xxd \
  xz-dev xz-static \
  python3 py3-packaging \
  linux-headers \
  curl \
  libdrm-dev

# linux-headers need by rtmpdump
# python3 py3-packaging needed by glib

# -O3 makes sure we compile with optimization. setting CFLAGS/CXXFLAGS seems to override
# default automake cflags.
# -static-libgcc is needed to make gcc not include gcc_s as "as-needed" shared library which
# cmake will include as a implicit library.
# other options to get hardened build (same as ffmpeg hardened)
ARG CFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG CXXFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG LDFLAGS="-Wl,-z,relro,-z,now"

# retry dns and some http codes that might be transient errors
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503"

# --no-same-owner as we don't care about uid/gid even if we run as root. fixes invalid gid/uid issue.
ARG TAR_OPTS="--no-same-owner --extract --file"

# before aom as libvmaf uses it
# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
ARG VMAF_VERSION=3.0.0
ARG VMAF_URL="https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz"
ARG VMAF_SHA256=7178c4833639e6b989ecae73131d02f70735fdb3fc2c7d84bc36c9c3461d93b1
RUN \
  wget $WGET_OPTS -O vmaf.tar.gz "$VMAF_URL" && \
  echo "$VMAF_SHA256  vmaf.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS vmaf.tar.gz && cd vmaf-*/libvmaf && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dbuilt_in_models=true \
    -Denable_tests=false \
    -Denable_docs=false \
    -Denable_avx512=true \
    -Denable_float=true && \
  ninja -j$(nproc) -vC build install
# extra libs stdc++ is for vmaf https://github.com/Netflix/vmaf/issues/788
RUN sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc

# own build as alpine glib links with libmount etc
# bump: glib /GLIB_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/glib.git|^2
# bump: glib after ./hashupdate Dockerfile GLIB $LATEST
# bump: glib link "NEWS" https://gitlab.gnome.org/GNOME/glib/-/blob/main/NEWS?ref_type=heads
ARG GLIB_VERSION=2.84.1
ARG GLIB_URL="https://download.gnome.org/sources/glib/2.84/glib-$GLIB_VERSION.tar.xz"
ARG GLIB_SHA256=2b4bc2ec49611a5fc35f86aca855f2ed0196e69e53092bab6bb73396bf30789a
RUN \
  wget $WGET_OPTS -O glib.tar.xz "$GLIB_URL" && \
  echo "$GLIB_SHA256  glib.tar.xz" | sha256sum --status -c - && \
  tar $TAR_OPTS glib.tar.xz && cd glib-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dlibmount=disabled && \
  ninja -j$(nproc) -vC build install

# bump: harfbuzz /LIBHARFBUZZ_VERSION=([\d.]+)/ https://github.com/harfbuzz/harfbuzz.git|*
# bump: harfbuzz after ./hashupdate Dockerfile LIBHARFBUZZ $LATEST
# bump: harfbuzz link "NEWS" https://github.com/harfbuzz/harfbuzz/blob/main/NEWS
ARG LIBHARFBUZZ_VERSION=12.1.0
ARG LIBHARFBUZZ_URL="https://github.com/harfbuzz/harfbuzz/releases/download/$LIBHARFBUZZ_VERSION/harfbuzz-$LIBHARFBUZZ_VERSION.tar.xz"
ARG LIBHARFBUZZ_SHA256=e5c81b7f6e0b102dfb000cfa424538b8e896ab78a2f4b8a5ec8cae62ab43369e
RUN \
  wget $WGET_OPTS -O harfbuzz.tar.xz "$LIBHARFBUZZ_URL" && \
  echo "$LIBHARFBUZZ_SHA256  harfbuzz.tar.xz" | sha256sum --status -c - && \
  tar $TAR_OPTS harfbuzz.tar.xz && cd harfbuzz-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

# bump: cairo /CAIRO_VERSION=([\d.]+)/ https://gitlab.freedesktop.org/cairo/cairo.git|^1
# bump: cairo after ./hashupdate Dockerfile CAIRO $LATEST
# bump: cairo link "NEWS" https://gitlab.freedesktop.org/cairo/cairo/-/blob/master/NEWS?ref_type=heads
ARG CAIRO_VERSION=1.18.4
ARG CAIRO_URL="https://cairographics.org/releases/cairo-$CAIRO_VERSION.tar.xz"
ARG CAIRO_SHA256=445ed8208a6e4823de1226a74ca319d3600e83f6369f99b14265006599c32ccb
RUN \
  wget $WGET_OPTS -O cairo.tar.xz "$CAIRO_URL" && \
  echo "$CAIRO_SHA256  cairo.tar.xz" | sha256sum --status -c - && \
  tar $TAR_OPTS cairo.tar.xz && cd cairo-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dtests=disabled \
    -Dquartz=disabled \
    -Dxcb=disabled \
    -Dxlib=disabled \
    -Dxlib-xcb=disabled && \
  ninja -j$(nproc) -vC build install

# TODO: there is weird "1.90" tag, skip it
# bump: pango /PANGO_VERSION=([\d.]+)/ https://github.com/GNOME/pango.git|/\d+\.\d+\.\d+/|*
# bump: pango after ./hashupdate Dockerfile PANGO $LATEST
# bump: pango link "NEWS" https://gitlab.gnome.org/GNOME/pango/-/blob/main/NEWS?ref_type=heads
ARG PANGO_VERSION=1.56.4
ARG PANGO_URL="https://download.gnome.org/sources/pango/1.56/pango-$PANGO_VERSION.tar.xz"
ARG PANGO_SHA256=17065e2fcc5f5a5bdbffc884c956bfc7c451a96e8c4fb2f8ad837c6413cb5a01
# TODO: add -Dbuild-testsuite=false when in stable release
# TODO: -Ddefault_library=both currently to not fail building tests
RUN \
  wget $WGET_OPTS -O pango.tar.xz "$PANGO_URL" && \
  echo "$PANGO_SHA256  pango.tar.xz" | sha256sum --status -c - && \
  tar $TAR_OPTS pango.tar.xz && cd pango-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=both \
    -Dintrospection=disabled \
    -Dgtk_doc=false && \
  ninja -j$(nproc) -vC build install

# bump: librsvg /LIBRSVG_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/librsvg.git|^2
# bump: librsvg after ./hashupdate Dockerfile LIBRSVG $LATEST
# bump: librsvg link "NEWS" https://gitlab.gnome.org/GNOME/librsvg/-/blob/master/NEWS
ARG LIBRSVG_VERSION=2.60.0
ARG LIBRSVG_URL="https://download.gnome.org/sources/librsvg/2.60/librsvg-$LIBRSVG_VERSION.tar.xz"
ARG LIBRSVG_SHA256=0b6ffccdf6e70afc9876882f5d2ce9ffcf2c713cbaaf1ad90170daa752e1eec3
RUN \
  wget $WGET_OPTS -O librsvg.tar.xz "$LIBRSVG_URL" && \
  echo "$LIBRSVG_SHA256  librsvg.tar.xz" | sha256sum --status -c - && \
  tar $TAR_OPTS librsvg.tar.xz && cd librsvg-* && \
  # workaround for https://gitlab.gnome.org/GNOME/librsvg/-/issues/1158
  sed -i "/^if host_system in \['windows'/s/, 'linux'//" meson.build && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddocs=disabled \
    -Dintrospection=disabled \
    -Dpixbuf=disabled \
    -Dpixbuf-loader=disabled \
    -Dvala=disabled \
    -Dtests=false && \
  ninja -j$(nproc) -vC build install

# build after libvmaf
# bump: aom /AOM_VERSION=([\d.]+)/ git:https://aomedia.googlesource.com/aom|*
# bump: aom after ./hashupdate Dockerfile AOM $LATEST
# bump: aom after COMMIT=$(git ls-remote https://aomedia.googlesource.com/aom v$LATEST^{} | awk '{print $1}') && sed -i -E "s/^ARG AOM_COMMIT=.*/ARG AOM_COMMIT=$COMMIT/" Dockerfile
# bump: aom link "CHANGELOG" https://aomedia.googlesource.com/aom/+/refs/tags/v$LATEST/CHANGELOG
ARG AOM_VERSION=3.13.1
ARG AOM_URL="https://aomedia.googlesource.com/aom"
ARG AOM_COMMIT=d772e334cc724105040382a977ebb10dfd393293
RUN git clone --depth 1 --branch v$AOM_VERSION "$AOM_URL"
RUN cd aom && test $(git rev-parse HEAD) = $AOM_COMMIT
RUN \
  cd aom && \
  mkdir build_tmp && cd build_tmp && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_EXAMPLES=NO \
    -DENABLE_DOCS=NO \
    -DENABLE_TESTS=NO \
    -DENABLE_TOOLS=NO \
    -DCONFIG_TUNE_VMAF=1 \
    -DENABLE_NASM=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    .. && \
  make -j$(nproc) install

# libaribb24's v1.0.3 tag predates the LGPLv3 relicensing commit. FFmpeg 8.0
# requires a post-1.0.3 libaribb24 build unless --enable-gpl is used.
ARG LIBARIBB24_VERSION=1.0.4
ARG LIBARIBB24_COMMIT=5e9be272f96e00f15a2f3c5f8ba7e124862aec38
ARG LIBARIBB24_URL="https://github.com/nkoriyama/aribb24/archive/$LIBARIBB24_COMMIT.tar.gz"
ARG LIBARIBB24_SHA256=651e88af3c8189d4faed538bee3affde360eb4698a70505765fc7e5653f5eb23
RUN \
  wget $WGET_OPTS -O libaribb24.tar.gz "$LIBARIBB24_URL" && \
  echo "$LIBARIBB24_SHA256  libaribb24.tar.gz" | sha256sum -c - && \
  mkdir libaribb24 && \
  tar $TAR_OPTS libaribb24.tar.gz -C libaribb24 --strip-components=1 && cd libaribb24 && \
  sed -i "s/AC_INIT(\\[aribb24\\], \\[1.0.3\\]/AC_INIT([aribb24], [$LIBARIBB24_VERSION]/" configure.ac && \
  autoreconf -fiv && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) && make install

# bump: libass /LIBASS_VERSION=([\d.]+)/ https://github.com/libass/libass.git|*
# bump: libass after ./hashupdate Dockerfile LIBASS $LATEST
# bump: libass link "Release notes" https://github.com/libass/libass/releases/tag/$LATEST
ARG LIBASS_VERSION=0.17.4
ARG LIBASS_URL="https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
ARG LIBASS_SHA256=a886b3b80867f437bc55cff3280a652bfa0d37b43d2aff39ddf3c4f288b8c5a8
RUN \
  wget $WGET_OPTS -O libass.tar.gz "$LIBASS_URL" && \
  echo "$LIBASS_SHA256  libass.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libass.tar.gz && cd libass-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) && make install

# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
ARG LIBBLURAY_VERSION=1.4.0
ARG LIBBLURAY_URL="https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz"
ARG LIBBLURAY_SHA256=0dc218f79435798a62da2a0510e0e921a3f7c1b140507df8e65f48d98046f024
# TODO: bump config? at least checkout to make commit sticky
ARG LIBUDFREAD_COMMIT=c3cd5cbb097924557ea4d9da1ff76a74620c51a8
RUN \
  wget $WGET_OPTS -O libbluray.tar.gz "$LIBBLURAY_URL" && \
  echo "$LIBBLURAY_SHA256  libbluray.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libbluray.tar.gz && cd libbluray-* && \
  git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread && \
  (cd contrib/libudfread && git checkout --recurse-submodules $LIBUDFREAD_COMMIT) && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

# bump: dav1d /DAV1D_VERSION=([\d.]+)/ https://code.videolan.org/videolan/dav1d.git|*
# bump: dav1d after ./hashupdate Dockerfile DAV1D $LATEST
# bump: dav1d link "Release notes" https://code.videolan.org/videolan/dav1d/-/tags/$LATEST
ARG DAV1D_VERSION=1.5.1
ARG DAV1D_URL="https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz"
ARG DAV1D_SHA256=fa635e2bdb25147b1384007c83e15de44c589582bb3b9a53fc1579cb9d74b695
RUN \
  wget $WGET_OPTS -O dav1d.tar.gz "$DAV1D_URL" && \
  echo "$DAV1D_SHA256  dav1d.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS dav1d.tar.gz && cd dav1d-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

# bump: libgme /LIBGME_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/libgme/game-music-emu.git|re:#^refs/heads/master$#|@commit
# bump: libgme after ./hashupdate Dockerfile LIBGME $LATEST
# bump: libgme link "Source diff $CURRENT..$LATEST" https://github.com/libgme/game-music-emu/compare/$CURRENT..v$LATEST
ARG LIBGME_URL="https://github.com/libgme/game-music-emu.git"
ARG LIBGME_COMMIT=bd7b3604dee43084aae0a2b4457ba7bf48554030
RUN \
  git clone "$LIBGME_URL" && \
  cd game-music-emu && git checkout --recurse-submodules $LIBGME_COMMIT && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_UBSAN=OFF \
    .. && \
  make -j$(nproc) install

# bump: libgsm /LIBGSM_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/timothytylee/libgsm.git|re:#^refs/heads/master$#|@commit
# bump: libgsm after ./hashupdate Dockerfile LIBGSM $LATEST
# bump: libgsm link "Changelog" https://github.com/timothytylee/libgsm/blob/master/ChangeLog
ARG LIBGSM_URL="https://github.com/timothytylee/libgsm.git"
ARG LIBGSM_COMMIT=98f1708fb5e06a0dfebd58a3b40d610823db9715
RUN \
  git clone "$LIBGSM_URL" && \
  cd libgsm && git checkout --recurse-submodules $LIBGSM_COMMIT && \
  # Makefile is hard to use, hence use specific compile arguments and flags
  # no need to build toast cli tool \
  rm src/toast* && \
  SRC=$(echo src/*.c) && \
  gcc ${CFLAGS} -c -ansi -pedantic -s -DNeedFunctionPrototypes=1 -Wall -Wno-comment -DSASR -DWAV49 -DNDEBUG -I./inc ${SRC} && \
  ar cr libgsm.a *.o && ranlib libgsm.a && \
  mkdir -p /usr/local/include/gsm && \
  cp inc/*.h /usr/local/include/gsm && \
  cp libgsm.a /usr/local/lib

# bump: kvazaar /KVAZAAR_VERSION=([\d.]+)/ https://github.com/ultravideo/kvazaar.git|^2
# bump: kvazaar after ./hashupdate Dockerfile KVAZAAR $LATEST
# bump: kvazaar link "Release notes" https://github.com/ultravideo/kvazaar/releases/tag/v$LATEST
ARG KVAZAAR_VERSION=2.3.2
ARG KVAZAAR_URL="https://github.com/ultravideo/kvazaar/archive/v$KVAZAAR_VERSION.tar.gz"
ARG KVAZAAR_SHA256=ddd0038696631ca5368d8e40efee36d2bbb805854b9b1dda8b12ea9b397ea951
RUN \
  wget $WGET_OPTS -O kvazaar.tar.gz "$KVAZAAR_URL" && \
  echo "$KVAZAAR_SHA256  kvazaar.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS kvazaar.tar.gz && cd kvazaar-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# bump: libmodplug /LIBMODPLUG_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/modplug-xmms/files/|/libmodplug-([\d.]+).tar.gz/
# bump: libmodplug after ./hashupdate Dockerfile LIBMODPLUG $LATEST
# bump: libmodplug link "NEWS" https://sourceforge.net/p/modplug-xmms/git/ci/master/tree/libmodplug/NEWS
ARG LIBMODPLUG_VERSION=0.8.9.0
ARG LIBMODPLUG_URL="https://downloads.sourceforge.net/modplug-xmms/libmodplug-$LIBMODPLUG_VERSION.tar.gz"
ARG LIBMODPLUG_SHA256=457ca5a6c179656d66c01505c0d95fafaead4329b9dbaa0f997d00a3508ad9de
RUN \
  wget $WGET_OPTS -O libmodplug.tar.gz "$LIBMODPLUG_URL" && \
  echo "$LIBMODPLUG_SHA256  libmodplug.tar.gz" | sha256sum -c && \
  tar $TAR_OPTS libmodplug.tar.gz && cd libmodplug-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# bump: mp3lame /MP3LAME_VERSION=([\d.]+)/ svn:http://svn.code.sf.net/p/lame/svn|/^RELEASE__(.*)$/|/_/./|*
# bump: mp3lame after ./hashupdate Dockerfile MP3LAME $LATEST
# bump: mp3lame link "ChangeLog" http://svn.code.sf.net/p/lame/svn/trunk/lame/ChangeLog
ARG MP3LAME_VERSION=3.100
ARG MP3LAME_URL="https://sourceforge.net/projects/lame/files/lame/$MP3LAME_VERSION/lame-$MP3LAME_VERSION.tar.gz/download"
ARG MP3LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
RUN \
  wget $WGET_OPTS -O lame.tar.gz "$MP3LAME_URL" && \
  echo "$MP3LAME_SHA256  lame.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS lame.tar.gz && cd lame-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --enable-nasm \
    --disable-gtktest \
    --disable-cpml \
    --disable-frontend && \
  make -j$(nproc) install

# bump: lcms2 /LCMS2_VERSION=([\d.]+)/ https://github.com/mm2/Little-CMS.git|^2
# bump: lcms2 after ./hashupdate Dockerfile LCMS2 $LATEST
# bump: lcms2 link "Release" https://github.com/mm2/Little-CMS/releases/tag/lcms$LATEST
ARG LCMS2_VERSION=2.17
ARG LCMS2_URL="https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS2_VERSION/lcms2-$LCMS2_VERSION.tar.gz"
ARG LCMS2_SHA256=d11af569e42a1baa1650d20ad61d12e41af4fead4aa7964a01f93b08b53ab074
RUN \
  wget $WGET_OPTS -O lcms2.tar.gz "$LCMS2_URL" && \
  echo "$LCMS2_SHA256  lcms2.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS lcms2.tar.gz && cd lcms2-* && \
  ./autogen.sh && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

# bump: libmysofa /LIBMYSOFA_VERSION=([\d.]+)/ https://github.com/hoene/libmysofa.git|^1
# bump: libmysofa after ./hashupdate Dockerfile LIBMYSOFA $LATEST
# bump: libmysofa link "Release" https://github.com/hoene/libmysofa/releases/tag/v$LATEST
# bump: libmysofa link "Source diff $CURRENT..$LATEST" https://github.com/hoene/libmysofa/compare/v$CURRENT..v$LATEST
ARG LIBMYSOFA_VERSION=1.3.4
ARG LIBMYSOFA_URL="https://github.com/hoene/libmysofa/archive/refs/tags/v$LIBMYSOFA_VERSION.tar.gz"
ARG LIBMYSOFA_SHA256=64c661f75ef39edf68bfc3a28403d2b5a0bd251d0b9f5d021ed6f7917867fb37
RUN \
  wget $WGET_OPTS -O libmysofa.tar.gz "$LIBMYSOFA_URL" && \
  echo "$LIBMYSOFA_SHA256  libmysofa.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libmysofa.tar.gz && cd libmysofa-*/build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    .. && \
  make -j$(nproc) install

# bump: opencoreamr /OPENCOREAMR_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/opencore-amr/files/opencore-amr/|/opencore-amr-([\d.]+).tar.gz/
# bump: opencoreamr after ./hashupdate Dockerfile OPENCOREAMR $LATEST
# bump: opencoreamr link "ChangeLog" https://sourceforge.net/p/opencore-amr/code/ci/master/tree/ChangeLog
ARG OPENCOREAMR_VERSION=0.1.6
ARG OPENCOREAMR_URL="https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-$OPENCOREAMR_VERSION.tar.gz"
ARG OPENCOREAMR_SHA256=483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1
RUN \
  wget $WGET_OPTS -O opencoreamr.tar.gz "$OPENCOREAMR_URL" && \
  echo "$OPENCOREAMR_SHA256  opencoreamr.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS opencoreamr.tar.gz && cd opencore-amr-* && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

# bump: openjpeg /OPENJPEG_VERSION=([\d.]+)/ https://github.com/uclouvain/openjpeg.git|*
# bump: openjpeg after ./hashupdate Dockerfile OPENJPEG $LATEST
# bump: openjpeg link "CHANGELOG" https://github.com/uclouvain/openjpeg/blob/master/CHANGELOG.md
ARG OPENJPEG_VERSION=2.5.4
ARG OPENJPEG_URL="https://github.com/uclouvain/openjpeg/archive/v$OPENJPEG_VERSION.tar.gz"
ARG OPENJPEG_SHA256=a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a
RUN \
  wget $WGET_OPTS -O openjpeg.tar.gz "$OPENJPEG_URL" && \
  echo "$OPENJPEG_SHA256  openjpeg.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS openjpeg.tar.gz && cd openjpeg-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_PKGCONFIG_FILES=ON \
    -DBUILD_CODEC=OFF \
    -DWITH_ASTYLE=OFF \
    -DBUILD_TESTING=OFF \
    .. && \
  make -j$(nproc) install

# bump: opus /OPUS_VERSION=([\d.]+)/ https://github.com/xiph/opus.git|^1
# bump: opus after ./hashupdate Dockerfile OPUS $LATEST
# bump: opus link "Release notes" https://github.com/xiph/opus/releases/tag/v$LATEST
# bump: opus link "Source diff $CURRENT..$LATEST" https://github.com/xiph/opus/compare/v$CURRENT..v$LATEST
ARG OPUS_VERSION=1.5.2
ARG OPUS_URL="https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
ARG OPUS_SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
RUN \
  wget $WGET_OPTS -O opus.tar.gz "$OPUS_URL" && \
  echo "$OPUS_SHA256  opus.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS opus.tar.gz && cd opus-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-extra-programs \
    --disable-doc && \
  make -j$(nproc) install

# bump: librabbitmq /LIBRABBITMQ_VERSION=([\d.]+)/ https://github.com/alanxz/rabbitmq-c.git|*
# bump: librabbitmq after ./hashupdate Dockerfile LIBRABBITMQ $LATEST
# bump: librabbitmq link "ChangeLog" https://github.com/alanxz/rabbitmq-c/blob/master/ChangeLog.md
ARG LIBRABBITMQ_VERSION=0.15.0
ARG LIBRABBITMQ_URL="https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v$LIBRABBITMQ_VERSION.tar.gz"
ARG LIBRABBITMQ_SHA256=7b652df52c0de4d19ca36c798ed81378cba7a03a0f0c5d498881ae2d79b241c2
RUN \
  wget $WGET_OPTS -O rabbitmq-c.tar.gz "$LIBRABBITMQ_URL" && \
  echo "$LIBRABBITMQ_SHA256  rabbitmq-c.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS rabbitmq-c.tar.gz && cd rabbitmq-c-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TOOLS_DOCS=OFF \
    -DRUN_SYSTEM_TESTS=OFF \
    .. && \
  make -j$(nproc) install

# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
ARG RAV1E_VERSION=0.7.1
ARG RAV1E_URL="https://github.com/xiph/rav1e/archive/v$RAV1E_VERSION.tar.gz"
ARG RAV1E_SHA256=da7ae0df2b608e539de5d443c096e109442cdfa6c5e9b4014361211cf61d030c
RUN \
  wget $WGET_OPTS -O rav1e.tar.gz "$RAV1E_URL" && \
  echo "$RAV1E_SHA256  rav1e.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS rav1e.tar.gz && cd rav1e-* && \
  # workaround weird cargo problem when on aws (?) weirdly alpine edge seems to work
  CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse" \
  RUSTFLAGS="-C target-feature=+crt-static" \
  cargo cinstall --release

# bump: librtmp /LIBRTMP_COMMIT=([[:xdigit:]]+)/ gitrefs:https://git.ffmpeg.org/rtmpdump.git|re:#^refs/heads/master$#|@commit
# bump: librtmp after ./hashupdate Dockerfile LIBRTMP $LATEST
# bump: librtmp link "Commit diff $CURRENT..$LATEST" https://git.ffmpeg.org/gitweb/rtmpdump.git/commitdiff/$LATEST?ds=sidebyside
ARG LIBRTMP_URL="https://git.ffmpeg.org/rtmpdump.git"
ARG LIBRTMP_COMMIT=6f6bb1353fc84f4cc37138baa99f586750028a01
RUN \
  git clone "$LIBRTMP_URL" && cd rtmpdump && \
  git checkout --recurse-submodules $LIBRTMP_COMMIT && \
  make SYS=posix SHARED=off -j$(nproc) install

# bump: libshine /LIBSHINE_VERSION=([\d.]+)/ https://github.com/toots/shine.git|*
# bump: libshine after ./hashupdate Dockerfile LIBSHINE $LATEST
# bump: libshine link "CHANGELOG" https://github.com/toots/shine/blob/master/ChangeLog
# bump: libshine link "Source diff $CURRENT..$LATEST" https://github.com/toots/shine/compare/$CURRENT..$LATEST
ARG LIBSHINE_VERSION=3.1.1
ARG LIBSHINE_URL="https://github.com/toots/shine/releases/download/$LIBSHINE_VERSION/shine-$LIBSHINE_VERSION.tar.gz"
ARG LIBSHINE_SHA256=58e61e70128cf73f88635db495bfc17f0dde3ce9c9ac070d505a0cd75b93d384
RUN \
  wget $WGET_OPTS -O libshine.tar.gz "$LIBSHINE_URL" && \
  echo "$LIBSHINE_SHA256  libshine.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libshine.tar.gz && cd shine* && \
  ./configure \
    --with-pic \
    --enable-static \
    --disable-shared \
    --disable-fast-install && \
  make -j$(nproc) install

# bump: speex /SPEEX_VERSION=([\d.]+)/ https://github.com/xiph/speex.git|*
# bump: speex after ./hashupdate Dockerfile SPEEX $LATEST
# bump: speex link "ChangeLog" https://github.com/xiph/speex//blob/master/ChangeLog
# bump: speex link "Source diff $CURRENT..$LATEST" https://github.com/xiph/speex/compare/$CURRENT..$LATEST
ARG SPEEX_VERSION=1.2.1
ARG SPEEX_URL="https://github.com/xiph/speex/archive/Speex-$SPEEX_VERSION.tar.gz"
ARG SPEEX_SHA256=beaf2642e81a822eaade4d9ebf92e1678f301abfc74a29159c4e721ee70fdce0
RUN \
  wget $WGET_OPTS -O speex.tar.gz "$SPEEX_URL" && \
  echo "$SPEEX_SHA256  speex.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS speex.tar.gz && cd speex-Speex-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# bump: srt /SRT_VERSION=([\d.]+)/ https://github.com/Haivision/srt.git|^1
# bump: srt after ./hashupdate Dockerfile SRT $LATEST
# bump: srt link "Release notes" https://github.com/Haivision/srt/releases/tag/v$LATEST
ARG SRT_VERSION=1.5.4
ARG SRT_URL="https://github.com/Haivision/srt/archive/v$SRT_VERSION.tar.gz"
ARG SRT_SHA256=d0a8b600fe1b4eaaf6277530e3cfc8f15b8ce4035f16af4a5eb5d4b123640cdd
RUN \
  wget $WGET_OPTS -O libsrt.tar.gz "$SRT_URL" && \
  echo "$SRT_SHA256  libsrt.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libsrt.tar.gz && cd srt-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF \
    -DENABLE_APPS=OFF \
    -DENABLE_CXX11=ON \
    -DUSE_STATIC_LIBSTDCXX=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DENABLE_LOGGING=OFF \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DCMAKE_INSTALL_BINDIR=bin \
    .. && \
  make -j$(nproc) && make install

# bump: libssh /LIBSSH_VERSION=([\d.]+)/ https://gitlab.com/libssh/libssh-mirror.git|*
# bump: libssh after ./hashupdate Dockerfile LIBSSH $LATEST
# bump: libssh link "Source diff $CURRENT..$LATEST" https://gitlab.com/libssh/libssh-mirror/-/compare/libssh-$CURRENT...libssh-$LATEST
# bump: libssh link "Release notes" https://gitlab.com/libssh/libssh-mirror/-/tags/libssh-$LATEST
ARG LIBSSH_VERSION=0.11.3
ARG LIBSSH_URL="https://gitlab.com/libssh/libssh-mirror/-/archive/libssh-$LIBSSH_VERSION/libssh-mirror-libssh-$LIBSSH_VERSION.tar.gz"
ARG LIBSSH_SHA256=16f4a54ee1e2d115931204fd45b87589dd8852dbfe48901c5c2dbc0b4b71da9a
# LIBSSH_STATIC=1 is REQUIRED to link statically against libssh.a so add to pkg-config file
RUN \
  wget $WGET_OPTS -O libssh.tar.gz "$LIBSSH_URL" && \
  echo "$LIBSSH_SHA256  libssh.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libssh.tar.gz && cd libssh* && \
  mkdir build && cd build && \
  echo -e 'Requires.private: libssl libcrypto zlib \nLibs.private: -DLIBSSH_STATIC=1 -lssh\nCflags.private: -DLIBSSH_STATIC=1 -I${CMAKE_INSTALL_FULL_INCLUDEDIR}' >> ../libssh.pc.cmake && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICKY_DEVELOPER=ON \
    -DBUILD_STATIC_LIB=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_GSSAPI=OFF \
    -DWITH_BLOWFISH_CIPHER=ON \
    -DWITH_SFTP=ON \
    -DWITH_SERVER=OFF \
    -DWITH_ZLIB=ON \
    -DWITH_PCAP=ON \
    -DWITH_DEBUG_CRYPTO=OFF \
    -DWITH_DEBUG_PACKET=OFF \
    -DWITH_DEBUG_CALLTRACE=OFF \
    -DUNIT_TESTING=OFF \
    -DCLIENT_TESTING=OFF \
    -DSERVER_TESTING=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_INTERNAL_DOC=OFF \
    .. && \
  # make -j seems to be shaky, libssh.a ends up truncated (used before fully created?)
  make install

# bump: svtav1 /SVTAV1_VERSION=([\d.]+)/ https://gitlab.com/AOMediaCodec/SVT-AV1.git|*
# bump: svtav1 after ./hashupdate Dockerfile SVTAV1 $LATEST
# bump: svtav1 link "Release notes" https://gitlab.com/AOMediaCodec/SVT-AV1/-/releases/v$LATEST
ARG SVTAV1_VERSION=3.1.2
ARG SVTAV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.bz2"
ARG SVTAV1_SHA256=802e9bb2b14f66e8c638f54857ccb84d3536144b0ae18b9f568bbf2314d2de88
RUN \
  wget $WGET_OPTS -O svtav1.tar.bz2 "$SVTAV1_URL" && \
  echo "$SVTAV1_SHA256  svtav1.tar.bz2" | sha256sum -c - && \
  tar $TAR_OPTS svtav1.tar.bz2 && cd SVT-AV1-*/Build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_AVX512=ON \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install

# has to be before theora
# bump: ogg /OGG_VERSION=([\d.]+)/ https://github.com/xiph/ogg.git|*
# bump: ogg after ./hashupdate Dockerfile OGG $LATEST
# bump: ogg link "CHANGES" https://github.com/xiph/ogg/blob/master/CHANGES
# bump: ogg link "Source diff $CURRENT..$LATEST" https://github.com/xiph/ogg/compare/v$CURRENT..v$LATEST
ARG OGG_VERSION=1.3.6
ARG OGG_URL="https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz"
ARG OGG_SHA256=83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638
RUN \
  wget $WGET_OPTS -O libogg.tar.gz "$OGG_URL" && \
  echo "$OGG_SHA256  libogg.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libogg.tar.gz && cd libogg-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# bump: theora /THEORA_VERSION=([\d.]+)/ https://github.com/xiph/theora.git|*
# bump: theora after ./hashupdate Dockerfile THEORA $LATEST
# bump: theora link "Release notes" https://github.com/xiph/theora/releases/tag/v$LATEST
# bump: theora link "Source diff $CURRENT..$LATEST" https://github.com/xiph/theora/compare/v$CURRENT..v$LATEST
ARG THEORA_VERSION=1.2.0
ARG THEORA_URL="https://ftp.osuosl.org/pub/xiph/releases/theora/libtheora-$THEORA_VERSION.tar.gz"
ARG THEORA_SHA256=279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e
RUN \
  wget $WGET_OPTS -O libtheora.tar.bz2 "$THEORA_URL" && \
  echo "$THEORA_SHA256  libtheora.tar.bz2" | sha256sum -c - && \
  tar $TAR_OPTS libtheora.tar.bz2 && cd libtheora-* && \
  # --build=$(arch)-unknown-linux-gnu helps with guessing the correct build. For some reason,
  # build script can't guess the build type in arm64 (hardware and emulated) environment.
 ./configure \
   --build=$(arch)-unknown-linux-gnu \
   --disable-examples \
   --disable-oggtest \
   --disable-shared \
   --enable-static && \
  make -j$(nproc) install

# bump: twolame /TWOLAME_VERSION=([\d.]+)/ https://github.com/njh/twolame.git|*
# bump: twolame after ./hashupdate Dockerfile TWOLAME $LATEST
# bump: twolame link "Source diff $CURRENT..$LATEST" https://github.com/njh/twolame/compare/v$CURRENT..v$LATEST
ARG TWOLAME_VERSION=0.4.0
ARG TWOLAME_URL="https://github.com/njh/twolame/releases/download/$TWOLAME_VERSION/twolame-$TWOLAME_VERSION.tar.gz"
ARG TWOLAME_SHA256=cc35424f6019a88c6f52570b63e1baf50f62963a3eac52a03a800bb070d7c87d
RUN \
  wget $WGET_OPTS -O twolame.tar.gz "$TWOLAME_URL" && \
  echo "$TWOLAME_SHA256  twolame.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS twolame.tar.gz && cd twolame-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-sndfile \
    --with-pic && \
  make -j$(nproc) install

# bump: uavs3d /UAVS3D_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/uavs3/uavs3d.git|re:#^refs/heads/master$#|@commit
# bump: uavs3d after ./hashupdate Dockerfile UAVS3D $LATEST
# bump: uavs3d link "Source diff $CURRENT..$LATEST" https://github.com/uavs3/uavs3d/compare/$CURRENT..$LATEST
ARG UAVS3D_URL="https://github.com/uavs3/uavs3d.git"
ARG UAVS3D_COMMIT=1fd04917cff50fac72ae23e45f82ca6fd9130bd8
# Removes BIT_DEPTH 10 to be able to build on other platforms. 10 was overkill anyways.
RUN \
  git clone "$UAVS3D_URL" && cd uavs3d && \
  git checkout --recurse-submodules $UAVS3D_COMMIT && \
  mkdir build/linux && cd build/linux && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    ../.. && \
  make -j$(nproc) install

# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
ARG VORBIS_VERSION=1.3.7
ARG VORBIS_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz"
ARG VORBIS_SHA256=0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab
RUN \
  wget $WGET_OPTS -O libvorbis.tar.gz "$VORBIS_URL" && \
  echo "$VORBIS_SHA256  libvorbis.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libvorbis.tar.gz && cd libvorbis-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-oggtest && \
  make -j$(nproc) install

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
ARG VPX_VERSION=1.15.2
ARG VPX_URL="https://github.com/webmproject/libvpx/archive/v$VPX_VERSION.tar.gz"
ARG VPX_SHA256=26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa
RUN \
  wget $WGET_OPTS -O libvpx.tar.gz "$VPX_URL" && \
  echo "$VPX_SHA256  libvpx.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libvpx.tar.gz && cd libvpx-* && \
  ./configure \
    --enable-static \
    --enable-vp9-highbitdepth \
    --disable-shared \
    --disable-unit-tests \
    --disable-examples && \
  make -j$(nproc) install

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
ARG LIBWEBP_VERSION=1.6.0
ARG LIBWEBP_URL="https://github.com/webmproject/libwebp/archive/v$LIBWEBP_VERSION.tar.gz"
ARG LIBWEBP_SHA256=93a852c2b3efafee3723efd4636de855b46f9fe1efddd607e1f42f60fc8f2136
RUN \
  wget $WGET_OPTS -O libwebp.tar.gz "$LIBWEBP_URL" && \
  echo "$LIBWEBP_SHA256  libwebp.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libwebp.tar.gz && cd libwebp-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static \
    --with-pic \
    --enable-libwebpmux \
    --disable-libwebpextras \
    --disable-libwebpdemux \
    --disable-sdl \
    --disable-gl \
    --disable-png \
    --disable-jpeg \
    --disable-tiff \
    --disable-gif && \
  make -j$(nproc) install

# bump: xeve /XEVE_VERSION=([\d.]+)/ https://github.com/mpeg5/xeve.git|*
# bump: xeve after ./hashupdate Dockerfile XEVE $LATEST
# bump: xeve link "CHANGELOG" https://github.com/mpeg5/xeve/releases/tag/v$LATEST
# TODO: better -DARM? possible to build on non arm and intel?
# TODO: report upstream about lib/libxeve.a?
ARG XEVE_VERSION=0.5.1
ARG XEVE_URL="https://github.com/mpeg5/xeve/archive/refs/tags/v$XEVE_VERSION.tar.gz"
ARG XEVE_SHA256=238c95ddd1a63105913d9354045eb329ad9002903a407b5cf1ab16bad324c245
RUN \
  wget $WGET_OPTS -O xeve.tar.gz "$XEVE_URL" && \
  echo "$XEVE_SHA256  xeve.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS xeve.tar.gz && \
  cd xeve-* && \
  echo v$XEVE_VERSION > version.txt && \
  sed -i 's/mc_filter_bilin/xevem_mc_filter_bilin/' src_main/sse/xevem_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -s /usr/local/lib/xeve/libxeve.a /usr/local/lib/libxeve.a

# bump: xevd /XEVD_VERSION=([\d.]+)/ https://github.com/mpeg5/xevd.git|*
# bump: xevd after ./hashupdate Dockerfile XEVD $LATEST
# bump: xevd link "CHANGELOG" https://github.com/mpeg5/xevd/releases/tag/v$LATEST
# TODO: better -DARM? possible to build on non arm and intel?
# TODO: report upstream about lib/libxevd.a?
ARG XEVD_VERSION=0.5.0
ARG XEVD_URL="https://github.com/mpeg5/xevd/archive/refs/tags/v$XEVD_VERSION.tar.gz"
ARG XEVD_SHA256=8d55c7ec1a9ad4e70fe91fbe129a1d4dd288bce766f466cba07a29452b3cecd8
RUN \
  wget $WGET_OPTS -O xevd.tar.gz "$XEVD_URL" && \
  echo "$XEVD_SHA256  xevd.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS xevd.tar.gz && cd xevd-* && \
  echo v$XEVD_VERSION > version.txt && \
  sed -i 's/mc_filter_bilin/xevdm_mc_filter_bilin/' src_main/sse/xevdm_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -s /usr/local/lib/xevd/libxevd.a /usr/local/lib/libxevd.a

# bump: zimg /ZIMG_VERSION=([\d.]+)/ https://github.com/sekrit-twc/zimg.git|*
# bump: zimg after ./hashupdate Dockerfile ZIMG $LATEST
# bump: zimg link "ChangeLog" https://github.com/sekrit-twc/zimg/blob/master/ChangeLog
ARG ZIMG_VERSION=3.0.6
ARG ZIMG_URL="https://github.com/sekrit-twc/zimg/archive/release-$ZIMG_VERSION.tar.gz"
ARG ZIMG_SHA256=be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577
RUN \
  wget $WGET_OPTS -O zimg.tar.gz "$ZIMG_URL" && \
  echo "$ZIMG_SHA256  zimg.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS zimg.tar.gz && cd zimg-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# bump: libjxl /LIBJXL_VERSION=([\d.]+)/ https://github.com/libjxl/libjxl.git|^0
# bump: libjxl after ./hashupdate Dockerfile LIBJXL $LATEST
# bump: libjxl link "Changelog" https://github.com/libjxl/libjxl/blob/main/CHANGELOG.md
# use bundled highway library as its static build is not available in alpine
ARG LIBJXL_VERSION=0.11.1
ARG LIBJXL_URL="https://github.com/libjxl/libjxl/archive/refs/tags/v${LIBJXL_VERSION}.tar.gz"
ARG LIBJXL_SHA256=1492dfef8dd6c3036446ac3b340005d92ab92f7d48ee3271b5dac1d36945d3d9
RUN \
  wget $WGET_OPTS -O libjxl.tar.gz "$LIBJXL_URL" && \
  echo "$LIBJXL_SHA256  libjxl.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libjxl.tar.gz && cd libjxl-* && \
  ./deps.sh && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_COVERAGE=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_FORCE_SYSTEM_GTEST=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_HWY=OFF && \
  cmake --build build -j$(nproc) && \
  cmake --install build
# workaround for ffmpeg configure script
RUN \
  sed -i 's/-ljxl/-ljxl -lstdc++ /' /usr/local/lib/pkgconfig/libjxl.pc && \
  sed -i 's/-ljxl_cms/-ljxl_cms -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_cms.pc && \
  sed -i 's/-ljxl_threads/-ljxl_threads -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_threads.pc

# bump: libzmq /LIBZMQ_VERSION=([\d.]+)/ https://github.com/zeromq/libzmq.git|*
# bump: libzmq after ./hashupdate Dockerfile LIBZMQ $LATEST
# bump: libzmq link "NEWS" https://github.com/zeromq/libzmq/blob/master/NEWS
ARG LIBZMQ_VERSION=4.3.5
ARG LIBZMQ_URL="https://github.com/zeromq/libzmq/releases/download/v${LIBZMQ_VERSION}/zeromq-${LIBZMQ_VERSION}.tar.gz"
ARG LIBZMQ_SHA256=6653ef5910f17954861fe72332e68b03ca6e4d9c7160eb3a8de5a5a913bfab43
RUN \
  wget $WGET_OPTS -O zmq.tar.gz "$LIBZMQ_URL" && \
  echo "$LIBZMQ_SHA256  zmq.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS zmq.tar.gz && cd zeromq-* && \
  # fix sha1_init symbol collision with libssh
  grep -r -l sha1_init external/sha1* | xargs sed -i 's/sha1_init/zeromq_sha1_init/g' && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# requires libdrm
# bump: libva /LIBVA_VERSION=([\d.]+)/ https://github.com/intel/libva.git|^2
# bump: libva after ./hashupdate Dockerfile LIBVA $LATEST
# bump: libva link "Changelog" https://github.com/intel/libva/blob/master/NEWS
ARG LIBVA_VERSION=2.22.0
ARG LIBVA_URL="https://github.com/intel/libva/archive/refs/tags/${LIBVA_VERSION}.tar.gz"
ARG LIBVA_SHA256=467c418c2640a178c6baad5be2e00d569842123763b80507721ab87eb7af8735
RUN \
  wget $WGET_OPTS -O libva.tar.gz "$LIBVA_URL" && \
  echo "$LIBVA_SHA256  libva.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libva.tar.gz && cd libva-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddisable_drm=false \
    -Dwith_x11=no \
    -Dwith_glx=no \
    -Dwith_wayland=no \
    -Dwith_win32=no \
    -Dwith_legacy=[] \
    -Denable_docs=false && \
  ninja -j$(nproc) -vC build install

# bump: libvpl /LIBVPL_VERSION=([\d.]+)/ https://github.com/intel/libvpl.git|^2
# bump: libvpl after ./hashupdate Dockerfile LIBVPL $LATEST
# bump: libvpl link "Changelog" https://github.com/intel/libvpl/blob/main/CHANGELOG.md
ARG LIBVPL_VERSION=2.14.0
ARG LIBVPL_URL="https://github.com/intel/libvpl/archive/refs/tags/v${LIBVPL_VERSION}.tar.gz"
ARG LIBVPL_SHA256=7c6bff1c1708d910032c2e6c44998ffff3f5fdbf06b00972bc48bf2dd9e5ac06
RUN \
  wget $WGET_OPTS -O libvpl.tar.gz "$LIBVPL_URL" && \
  echo "$LIBVPL_SHA256  libvpl.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS libvpl.tar.gz && cd libvpl-* && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_WARNING_AS_ERROR=ON && \
  cmake --build build -j$(nproc) && \
  cmake --install build

# bump: vvenc /VVENC_VERSION=([\d.]+)/ https://github.com/fraunhoferhhi/vvenc.git|*
# bump: vvenc after ./hashupdate Dockerfile VVENC $LATEST
# bump: vvenc link "CHANGELOG" https://github.com/fraunhoferhhi/vvenc/releases/tag/v$LATEST
ARG VVENC_VERSION=1.13.1
ARG VVENC_URL="https://github.com/fraunhoferhhi/vvenc/archive/refs/tags/v$VVENC_VERSION.tar.gz"
ARG VVENC_SHA256=9d0d88319b9c200ebf428471a3f042ea7dcd868e8be096c66e19120a671a0bc8
RUN \
  wget $WGET_OPTS -O vvenc.tar.gz "$VVENC_URL" && \
  echo "$VVENC_SHA256  vvenc.tar.gz" | sha256sum --status -c - && \
  tar $TAR_OPTS vvenc.tar.gz && cd vvenc-* && \
  sed -i 's/-Werror;//' source/Lib/vvenc/CMakeLists.txt && \
  cmake \
    -S . \
    -B build/release-static \
    -DVVENC_ENABLE_WERROR=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local && \
  cmake --build build/release-static -j && \
  cmake --build build/release-static --target install

# bump: ffmpeg /FFMPEG_VERSION=([\d.]+)/ https://github.com/FFmpeg/FFmpeg.git|*
# bump: ffmpeg after ./hashupdate Dockerfile FFMPEG $LATEST
# bump: ffmpeg link "Changelog" https://github.com/FFmpeg/FFmpeg/blob/n$LATEST/Changelog
# bump: ffmpeg link "Source diff $CURRENT..$LATEST" https://github.com/FFmpeg/FFmpeg/compare/n$CURRENT..n$LATEST
ARG FFMPEG_VERSION=8.0
ARG FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
ARG FFMPEG_SHA256=3e74acc48ddb9f5f70b6747d3f439d51e7cc5497f097d58e5975c84488f4d186
ARG OPENH264_VERSION=2.6.0
ARG OPENH264_URL="https://github.com/cisco/openh264/archive/refs/tags/v$OPENH264_VERSION.tar.gz"
ARG OPENH264_SHA256=558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69

COPY scripts/build-ffmpeg.sh /usr/local/bin/build-ffmpeg.sh
COPY scripts/make-license-json.sh /usr/local/bin/make-license-json.sh
COPY scripts/verify-ffmpeg-license.sh /usr/local/bin/verify-ffmpeg-license.sh
COPY scripts/oski-openh264 /usr/local/bin/oski-openh264
COPY scripts/oski-amr /usr/local/bin/oski-amr
COPY scripts/openh264-glibc-shim.c /tmp/openh264-glibc-shim.c
COPY licenses/external-libs.json /licenses/external-libs.json

RUN gcc -shared -fPIC -O2 -o /usr/local/lib/liboski-openh264-glibc-shim.so /tmp/openh264-glibc-shim.c

RUN \
  wget $WGET_OPTS -O openh264.tar.gz "$OPENH264_URL" && \
  echo "$OPENH264_SHA256  openh264.tar.gz" | sha256sum -c - && \
  tar $TAR_OPTS openh264.tar.gz && cd openh264-* && \
  make -j$(nproc) PREFIX=/usr/local install-shared

RUN \
  wget $WGET_OPTS -O ffmpeg.tar.bz2 "$FFMPEG_URL" && \
  echo "$FFMPEG_SHA256  ffmpeg.tar.bz2" | sha256sum -c - && \
  tar $TAR_OPTS ffmpeg.tar.bz2 && cd ffmpeg* && \
  # workaround for https://gitlab.com/AOMediaCodec/SVT-AV1/-/merge_requests/2387
  sed -i 's/svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params)/svt_av1_enc_init_handle(\&svt_enc->svt_handle, \&svt_enc->enc_params)/g' libavcodec/libsvtav1.c && \
  cp configure configure.orig && \
  cp configure.orig configure && \
  sed -i 's/add_ldexeflags -fPIE -pie/add_ldexeflags -fPIE -static-pie/' configure && \
  /usr/local/bin/build-ffmpeg.sh static

# make sure default static binaries have no dependencies, are relro, pie and stack nx
COPY checkelf /
COPY checkdupsym /
RUN \
  /checkelf /usr/local/bin/ffmpeg && \
  /checkelf /usr/local/bin/ffprobe && \
  /checkdupsym /ffmpeg-*

RUN \
  cd ffmpeg-* && \
  make distclean && \
  cp configure.orig configure && \
  DESTDIR=/opt/oski-shared /usr/local/bin/build-ffmpeg.sh shared

RUN \
  cd ffmpeg-* && \
  make distclean && \
  cp configure.orig configure && \
  sed -i 's/add_ldexeflags -fPIE -pie/add_ldexeflags -fPIE -static-pie/' configure && \
  DESTDIR=/opt/oski-amr /usr/local/bin/build-ffmpeg.sh amr

RUN \
  cd ffmpeg-* && \
  make distclean && \
  cp configure.orig configure && \
  DESTDIR=/opt/oski-openh264 /usr/local/bin/build-ffmpeg.sh openh264

RUN \
	  EXPAT_VERSION=$(pkg-config --modversion expat) \
		  FONTCONFIG_VERSION=$(pkg-config --modversion fontconfig) \
	  FREETYPE_VERSION=$(pkg-config --modversion freetype2) \
	  FRIBIDI_VERSION=$(pkg-config --modversion fribidi) \
		  LIBOPENH264_VERSION=$(pkg-config --modversion openh264) \
	  LIBVO_AMRWBENC_VERSION=$(pkg-config --modversion vo-amrwbenc) \
	  LIBXML2_VERSION=$(pkg-config --modversion libxml-2.0) \
	  OPENSSL_VERSION=$(pkg-config --modversion openssl) \
	  SNAPPY_VERSION=$(apk info -a snappy $APK_OPTS | head -n1 | awk '{print $1}' | sed -e 's/snappy-//') \
	  SOXR_VERSION=$(pkg-config --modversion soxr) \
  jq -n \
  '{ \
  expat: env.EXPAT_VERSION, \
	  ffmpeg: env.FFMPEG_VERSION, \
		  fontconfig: env.FONTCONFIG_VERSION, \
	  lcms2: env.LCMS2_VERSION, \
	  libaom: env.AOM_VERSION, \
	  libaribb24: env.LIBARIBB24_VERSION, \
	  libass: env.LIBASS_VERSION, \
	  libbluray: env.LIBBLURAY_VERSION, \
	  libdav1d: env.DAV1D_VERSION, \
	  libfreetype: env.FREETYPE_VERSION, \
	  libfribidi: env.FRIBIDI_VERSION, \
	  libgme: env.LIBGME_COMMIT, \
	  libgsm: env.LIBGSM_COMMIT, \
	  libharfbuzz: env.LIBHARFBUZZ_VERSION, \
  libjxl: env.LIBJXL_VERSION, \
  libkvazaar: env.KVAZAAR_VERSION, \
  libmodplug: env.LIBMODPLUG_VERSION, \
  libmp3lame: env.MP3LAME_VERSION, \
  libmysofa: env.LIBMYSOFA_VERSION, \
  libogg: env.OGG_VERSION, \
	  libopencoreamr: env.OPENCOREAMR_VERSION, \
	  libopenh264: env.LIBOPENH264_VERSION, \
	  libopenjpeg: env.OPENJPEG_VERSION, \
	  libopus: env.OPUS_VERSION, \
	  librabbitmq: env.LIBRABBITMQ_VERSION, \
	  librav1e: env.RAV1E_VERSION, \
	  librsvg: env.LIBRSVG_VERSION, \
	  librtmp: env.LIBRTMP_COMMIT, \
		  libshine: env.LIBSHINE_VERSION, \
	  libsnappy: env.SNAPPY_VERSION, \
	  libsoxr: env.SOXR_VERSION, \
	  libspeex: env.SPEEX_VERSION, \
  libsrt: env.SRT_VERSION, \
  libssh: env.LIBSSH_VERSION, \
  libsvtav1: env.SVTAV1_VERSION, \
	  libtheora: env.THEORA_VERSION, \
	  libtwolame: env.TWOLAME_VERSION, \
	  libuavs3d: env.UAVS3D_COMMIT, \
	  libva: env.LIBVA_VERSION, \
	  libvmaf: env.VMAF_VERSION, \
	  libvo_amrwbenc: env.LIBVO_AMRWBENC_VERSION, \
	  libvorbis: env.VORBIS_VERSION, \
	  libvpl: env.LIBVPL_VERSION, \
	  libvpx: env.VPX_VERSION, \
	  libvvenc: env.VVENC_VERSION, \
	  libwebp: env.LIBWEBP_VERSION, \
	  libxevd: env.XEVD_VERSION, \
	  libxeve: env.XEVE_VERSION, \
	  libxml2: env.LIBXML2_VERSION, \
	  libzimg: env.ZIMG_VERSION, \
	  libzmq: env.LIBZMQ_VERSION, \
	  openssl: env.OPENSSL_VERSION, \
		  sonames: { \
		    libavformat: "libavformat.so.62", \
		    libavcodec: "libavcodec.so.62", \
		    libavdevice: "libavdevice.so.62", \
		    libavfilter: "libavfilter.so.11", \
		    libavutil: "libavutil.so.60", \
		    libswresample: "libswresample.so.6", \
		    libswscale: "libswscale.so.9" \
		  } \
	  }' > /versions.json

RUN \
  /usr/local/bin/make-license-json.sh ffmpeg-bin && cp /license.json /license-ffmpeg-bin.json && \
  /usr/local/bin/make-license-json.sh ffmpeg-dev && cp /license.json /license-ffmpeg-dev.json && \
  /usr/local/bin/make-license-json.sh ffmpeg-shared && cp /license.json /license-ffmpeg-shared.json && \
  /usr/local/bin/make-license-json.sh openh264-runtime && cp /license.json /license-openh264-runtime.json && \
  /usr/local/bin/make-license-json.sh amr-runtime && cp /license.json /license-amr-runtime.json

RUN TARGET=ffmpeg-bin FFMPEG=/usr/local/bin/ffmpeg PROBE=/usr/local/bin/ffprobe /usr/local/bin/verify-ffmpeg-license.sh
RUN TARGET=ffmpeg-dev FFMPEG=/usr/local/bin/ffmpeg PROBE=/usr/local/bin/ffprobe /usr/local/bin/verify-ffmpeg-license.sh
RUN TARGET=ffmpeg-shared FFMPEG=/opt/oski-shared/usr/local/bin/ffmpeg PROBE=/opt/oski-shared/usr/local/bin/ffprobe LIBDIR=/opt/oski-shared/usr/local/lib LD_LIBRARY_PATH=/opt/oski-shared/usr/local/lib /usr/local/bin/verify-ffmpeg-license.sh
RUN TARGET=openh264-runtime FFMPEG=/opt/oski-openh264/usr/local/bin/ffmpeg PROBE=/opt/oski-openh264/usr/local/bin/ffprobe LD_LIBRARY_PATH=/usr/local/lib /usr/local/bin/verify-ffmpeg-license.sh
RUN TARGET=amr-runtime FFMPEG=/opt/oski-amr/usr/local/bin/ffmpeg PROBE=/opt/oski-amr/usr/local/bin/ffprobe /usr/local/bin/verify-ffmpeg-license.sh

RUN \
  mkdir -p /opt/oski-dev/usr/local/lib /opt/oski-dev/usr/local/include /opt/oski-dev/usr/local/lib/pkgconfig && \
  cp -a /usr/local/lib/*.a /opt/oski-dev/usr/local/lib/ && \
  cp -a /usr/local/include/. /opt/oski-dev/usr/local/include/ && \
  cp -a /usr/local/lib/pkgconfig/. /opt/oski-dev/usr/local/lib/pkgconfig/ && \
  rm -f /opt/oski-dev/usr/local/lib/libopencore-amr*.a /opt/oski-dev/usr/local/lib/libopenh264*.a && \
  rm -f /opt/oski-dev/usr/local/lib/pkgconfig/opencore-amr*.pc /opt/oski-dev/usr/local/lib/pkgconfig/openh264.pc && \
  rm -rf /opt/oski-dev/usr/local/include/opencore-amrnb /opt/oski-dev/usr/local/include/opencore-amrwb /opt/oski-dev/usr/local/include/wels

# some basic fonts that don't take up much space
RUN apk add $APK_OPTS font-terminus font-inconsolata font-dejavu font-awesome

FROM scratch AS ffmpeg-bin
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /versions.json /
COPY --from=builder /license-ffmpeg-bin.json /license.json
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

# sanity tests
RUN ["/ffmpeg", "-version"]
RUN ["/ffprobe", "-version"]
RUN ["/ffmpeg", "-hide_banner", "-buildconf"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=0.1", "-c:v", "libsvtav1", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=0.1", "-c:v", "libaom-av1", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=0.1", "-c:v", "libvpx-vp9", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=0.1", "-c:v", "libwebp", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=0.1", "-c:v", "libkvazaar", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "sine=duration=0.1", "-c:a", "libopus", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "sine=duration=0.1", "-c:a", "libvorbis", "-f", "null", "-"]
RUN ["/ffmpeg", "-f", "lavfi", "-i", "sine=duration=0.1", "-c:a", "libmp3lame", "-f", "null", "-"]
# dns
RUN ["/ffprobe", "-i", "https://github.com/favicon.ico"]
# tls/https certs
RUN ["/ffprobe", "-tls_verify", "1", "-ca_file", "/etc/ssl/cert.pem", "-i", "https://github.com/favicon.ico"]
# svg
RUN ["/ffprobe", "-i", "https://github.githubassets.com/favicons/favicon.svg"]

FROM scratch AS ffmpeg-dev
COPY --from=builder /opt/oski-dev/usr/local/lib/ /usr/local/lib/
COPY --from=builder /opt/oski-dev/usr/local/include/ /usr/local/include/
COPY --from=builder /opt/oski-dev/usr/local/lib/pkgconfig/ /usr/local/lib/pkgconfig/
COPY --from=builder /versions.json /
COPY --from=builder /license-ffmpeg-dev.json /license.json

FROM scratch AS ffmpeg-shared
COPY --from=builder /opt/oski-shared/usr/local/lib/libav*.so* /usr/local/lib/
COPY --from=builder /opt/oski-shared/usr/local/lib/libsw*.so* /usr/local/lib/
COPY --from=builder /opt/oski-shared/usr/local/include/ /usr/local/include/
COPY --from=builder /opt/oski-shared/usr/local/lib/pkgconfig/ /usr/local/lib/pkgconfig/
COPY --from=builder /versions.json /
COPY --from=builder /license-ffmpeg-shared.json /license.json

FROM $ALPINE_VERSION AS openh264-runtime
RUN apk add --no-cache ca-certificates curl bzip2 coreutils gcompat libc6-compat libgcc libstdc++
COPY --from=builder /opt/oski-openh264/usr/local/bin/ffmpeg /usr/local/bin/ffmpeg-openh264
COPY --from=builder /opt/oski-openh264/usr/local/bin/ffprobe /usr/local/bin/ffprobe-openh264
COPY --from=builder /usr/local/bin/oski-openh264 /usr/local/bin/oski-openh264
COPY --from=builder /usr/local/lib/liboski-openh264-glibc-shim.so /usr/local/lib/liboski-openh264-glibc-shim.so
COPY --from=builder /versions.json /
COPY --from=builder /license-openh264-runtime.json /license.json
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/
RUN printf '%s\n' '#!/bin/sh' 'if [ ! -e /usr/local/lib/libopenh264.so.8 ]; then' '  echo "OpenH264 sidecar missing. Run oski-openh264 enable --accept-license first." >&2' '  exit 1' 'fi' 'export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"' 'export LD_PRELOAD="/usr/local/lib/liboski-openh264-glibc-shim.so${LD_PRELOAD:+:$LD_PRELOAD}"' 'exec /usr/local/bin/ffmpeg-openh264 "$@"' > /ffmpeg && chmod +x /ffmpeg
RUN printf '%s\n' '#!/bin/sh' 'if [ ! -e /usr/local/lib/libopenh264.so.8 ]; then' '  echo "OpenH264 sidecar missing. Run oski-openh264 enable --accept-license first." >&2' '  exit 1' 'fi' 'export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"' 'export LD_PRELOAD="/usr/local/lib/liboski-openh264-glibc-shim.so${LD_PRELOAD:+:$LD_PRELOAD}"' 'exec /usr/local/bin/ffprobe-openh264 "$@"' > /ffprobe && chmod +x /ffprobe
ENTRYPOINT ["/ffmpeg"]

FROM $ALPINE_VERSION AS amr-runtime
RUN apk add --no-cache ca-certificates
COPY --from=builder /opt/oski-amr/usr/local/bin/ffmpeg /ffmpeg
COPY --from=builder /opt/oski-amr/usr/local/bin/ffprobe /ffprobe
COPY --from=builder /usr/local/bin/oski-amr /usr/local/bin/oski-amr
COPY --from=builder /versions.json /
COPY --from=builder /license-amr-runtime.json /license.json
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/
RUN ["/ffmpeg", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.1", "-c:a", "libopencore_amrnb", "-ar", "8000", "-ac", "1", "-f", "amr", "-y", "/tmp/out.amr"]
RUN ["/ffmpeg", "-i", "/tmp/out.amr", "-f", "null", "-"]
ENTRYPOINT ["/ffmpeg"]

FROM ffmpeg-bin
LABEL maintainer="Mattias Wadman mattias.wadman@gmail.com"
ENTRYPOINT ["/ffmpeg"]
