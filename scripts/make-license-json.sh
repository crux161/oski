#!/bin/sh
set -eu

TARGET=${1:-ffmpeg-bin}
VERSIONS=${VERSIONS:-/versions.json}
LICENSE_MAP=${LICENSE_MAP:-/licenses/external-libs.json}
OUTPUT=${OUTPUT:-/license.json}

jq \
  --arg target "$TARGET" \
  --slurpfile versions "$VERSIONS" \
  '
  . as $map
  | {
      target: $target,
      effective_license: $map.effective_license,
      ffmpeg_version: $versions[0].ffmpeg,
      version3_required_by: (
        if $target == "amr-runtime" then
          ($map.version3_required_by + ["libopencore-amrnb"])
        else
          $map.version3_required_by
        end
      ),
      enabled_external_libs: [
        $map.external_libs[]
        | select(
            (.default_enabled // true) and
            ((.opt_in // "") == "" or (.opt_in == "amr" and $target == "amr-runtime") or (.opt_in == "h264" and $target == "openh264-runtime"))
          )
        | select($versions[0][.version_key] != null)
        | {
            name,
            version: $versions[0][.version_key],
            license,
            opt_in: (.opt_in // null)
          }
      ],
      gpl: false,
      nonfree: false,
      sonames: ($versions[0].sonames // {}),
      patent_encumbered_opt_in_only: $map.patent_encumbered_opt_in_only
    }
  ' "$LICENSE_MAP" > "$OUTPUT"
