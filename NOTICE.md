# Project Licensing Notice

Oski is a fork of `static-ffmpeg`, which was originally licensed under the MIT
License. A copy of that license is included in this repository as `LICENSE.MIT`.

Oski's own source code, scripts, and Dockerfile modifications are licensed under
BSD 2-Clause; see `LICENSE.BSD`.

The FFmpeg binaries and libraries produced by Oski are licensed under
LGPL-3.0-or-later. They are intended to be GPL-free and FFmpeg `nonfree`-free.

External libraries linked into FFmpeg retain their upstream licenses. Each image
includes `/license.json` with the effective license, enabled external libraries,
and target metadata.

Patent-encumbered codecs are isolated from the default image. H.264 encoding is
available only through the `openh264-runtime` target with a Cisco binary sidecar;
AMR-NB/WB support is available only through the `amr-runtime` target. Patent
licensing for those codecs is the user's responsibility.
