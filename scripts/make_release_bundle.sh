#!/usr/bin/env bash
set -euo pipefail

# Generate a release bundle from compiled AOSP build outputs.
#
# Produces three files in RELEASE_DIR:
#   <product>-out-<date>.tar.zst     compressed archive of build images
#   <product>-out-<date>.manifest.txt  human-readable contents listing
#   <product>-out-<date>.sha256        SHA-256 checksums
#
# Environment variables:
#   OUT          compiled output dir   (default: src/out/target/product/vsoc_arm64_only)
#   RELEASE_DIR  destination dir       (default: release-assets)
#   TAG          version tag for notes (default: none, skip notes generation)
#   DATE         datestamp override    (default: today, YYYY-MM-DD)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=${OUT:-$ROOT/src/out/target/product/vsoc_arm64_only}
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release-assets}
DATE=${DATE:-$(date +%Y-%m-%d)}
TAG=${TAG:-}
PRODUCT=aosp_cf_arm64_only_phone_qemu

IMAGES=(
  boot.img
  init_boot.img
  vendor_boot.img
  super.img
  userdata.img
  vbmeta.img
  vbmeta_system.img
  vbmeta_vendor_dlkm.img
  vbmeta_system_dlkm.img
)

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require tar
require zstd
require sha256sum

# Validate that all required build images exist.
missing=0
for img in "${IMAGES[@]}"; do
  if [[ ! -f "$OUT/$img" ]]; then
    echo "missing required image: $OUT/$img" >&2
    missing=1
  fi
done
if (( missing )); then
  exit 1
fi

mkdir -p "$RELEASE_DIR"

BASENAME="${PRODUCT}-out-${DATE}"
ARCHIVE="$RELEASE_DIR/${BASENAME}.tar.zst"
MANIFEST="$RELEASE_DIR/${BASENAME}.manifest.txt"
CHECKSUM="$RELEASE_DIR/${BASENAME}.sha256"

# Build the archive from the product output directory.
echo "creating archive: $ARCHIVE"
tar -C "$OUT" --zstd -cf "$ARCHIVE" "${IMAGES[@]}"

# Write the manifest.
cat >"$MANIFEST" <<EOF
AOSP build outputs required to create the validated plain-QEMU bundle.

Source product:
- ${PRODUCT}
- output dir: ${OUT##"$ROOT"/}

Included files:
$(printf -- '- %s\n' "${IMAGES[@]}")

Use with:
- scripts/prepare_plain_qemu.sh
- docs/BUILD.md
- docs/BOOT.md
EOF

# Generate SHA-256 checksums (paths relative to repo root).
(cd "$ROOT" && sha256sum \
  "${ARCHIVE#"$ROOT"/}" \
  "${MANIFEST#"$ROOT"/}" \
) >"$CHECKSUM"

echo "manifest:  $MANIFEST"
echo "checksums: $CHECKSUM"

# Optionally generate release notes when TAG is set.
if [[ -n "$TAG" ]]; then
  NOTES="$RELEASE_DIR/${TAG}-notes.md"
  cat >"$NOTES" <<EOF
Initial release of the validated \`${PRODUCT}\` build outputs.

What is included:
- \`${BASENAME}.tar.zst\`
- matching manifest and SHA-256 files

Why this asset format:
- the direct processed \`plain-qemu/os-disk.raw\` boot image is too large to publish comfortably
- this release instead ships the compiled output set that was used to produce the validated plain-QEMU bundle

How to use:
1. Extract the archive under the repository root.
2. Place the included image files under \`${OUT##"$ROOT"/}\`.
3. Run \`./scripts/prepare_plain_qemu.sh\`.
4. Follow \`docs/BOOT.md\` for the validated no-harness QEMU launch flow.
EOF
  echo "notes:     $NOTES"
fi

echo "done"
