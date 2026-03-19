#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/azureuser/aosp
OUT=${OUT:-$ROOT/src/out/target/product/vsoc_arm64_only}
HOSTBIN=${HOSTBIN:-$ROOT/src/out/host/linux-x86/bin}
STAGE=${STAGE:-$ROOT/plain-qemu}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_UNPACK_BOOTIMG=${LOCAL_UNPACK_BOOTIMG:-$SCRIPT_DIR/unpack_bootimg.py}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_file() {
  local path=$1
  [[ -f "$path" ]] || {
    echo "missing required input file: $path" >&2
    exit 1
  }
}

first_existing() {
  local candidate
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_tool() {
  local tool=$1
  if [[ "$tool" == "unpack_bootimg" && -x "$LOCAL_UNPACK_BOOTIMG" ]]; then
    echo "$LOCAL_UNPACK_BOOTIMG"
    return 0
  fi

  if [[ -n "${HOSTBIN:-}" && -x "$HOSTBIN/$tool" ]]; then
    echo "$HOSTBIN/$tool"
    return 0
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi

  echo "missing required tool: $tool" >&2
  exit 1
}

file_size_bytes() {
  local path=$1
  if stat -f%z "$path" >/dev/null 2>&1; then
    stat -f%z "$path"
    return 0
  fi

  stat -c%s "$path"
}

require python3
require mke2fs
require sgdisk

SIMG2IMG=$(resolve_tool simg2img)
UNPACK_BOOTIMG=$(resolve_tool unpack_bootimg)
MKE2FS=$(command -v mke2fs)
SGDISK=$(command -v sgdisk)

for file in \
  "$OUT/boot.img" \
  "$OUT/init_boot.img" \
  "$OUT/vendor_boot.img" \
  "$OUT/super.img" \
  "$OUT/userdata.img" \
  "$OUT/vbmeta.img" \
  "$OUT/vbmeta_system.img" \
  "$OUT/vbmeta_vendor_dlkm.img" \
  "$OUT/vbmeta_system_dlkm.img"; do
  require_file "$file"
done

mkdir -p "$STAGE"/unpack/boot "$STAGE"/unpack/vendor_boot

"$UNPACK_BOOTIMG" --boot_img "$OUT/boot.img" --out "$STAGE/unpack/boot"
"$UNPACK_BOOTIMG" --boot_img "$OUT/vendor_boot.img" --out "$STAGE/unpack/vendor_boot"

vendor_ramdisk_path=$(first_existing \
  "$STAGE/unpack/vendor_boot/vendor_ramdisk00" \
  "$STAGE/unpack/vendor_boot/vendor_ramdisk")
require_file "$vendor_ramdisk_path"

cp "$STAGE/unpack/boot/kernel" "$STAGE/kernel"
cp "$vendor_ramdisk_path" "$STAGE/vendor_ramdisk.lz4"
cp "$STAGE/unpack/vendor_boot/bootconfig" "$STAGE/vendor_bootconfig.txt"
cp "$STAGE/unpack/vendor_boot/dtb" "$STAGE/dtb.img"

for file in \
  "$STAGE/kernel" \
  "$STAGE/vendor_ramdisk.lz4" \
  "$STAGE/vendor_bootconfig.txt" \
  "$STAGE/dtb.img"; do
  require_file "$file"
done

"$SIMG2IMG" "$OUT/super.img" "$STAGE/super.raw"
"$SIMG2IMG" "$OUT/userdata.img" "$STAGE/userdata.raw"

truncate -s 1M "$STAGE/misc.img"
truncate -s 1M "$STAGE/frp.img"
truncate -s 64M "$STAGE/metadata.img"
"$MKE2FS" -q -t ext4 -F "$STAGE/metadata.img"

cat >"$STAGE/bootconfig.extra.txt" <<'EOF'
androidboot.slot_suffix=_a
androidboot.force_normal_boot=1
androidboot.verifiedbootstate=orange
androidboot.fstab_suffix=cf.f2fs.hctr2
androidboot.boot_devices=4010000000.pcie
androidboot.serialconsole=0
EOF

cat "$STAGE/bootconfig.extra.txt" "$STAGE/vendor_bootconfig.txt" >"$STAGE/bootconfig.combined.txt"

python3 - "$STAGE/vendor_ramdisk.lz4" "$STAGE/bootconfig.combined.txt" "$STAGE/initrd.img" <<'PY'
import pathlib
import struct
import sys

ramdisk = pathlib.Path(sys.argv[1]).read_bytes()
bootconfig = pathlib.Path(sys.argv[2]).read_bytes().rstrip(b"\x00")
checksum = sum(bootconfig) & 0xFFFFFFFF

with open(sys.argv[3], "wb") as f:
    f.write(ramdisk)
    f.write(bootconfig)
    f.write(struct.pack("<I", len(bootconfig)))
    f.write(struct.pack("<I", checksum))
    f.write(b"#BOOTCONFIG\n")
PY

align_sectors() {
  local n=$1
  echo $(( ((n + 2047) / 2048) * 2048 ))
}

declare -a PART_NAMES=(
  misc
  frp
  boot_a
  boot_b
  init_boot_a
  init_boot_b
  vendor_boot_a
  vendor_boot_b
  vbmeta_a
  vbmeta_b
  vbmeta_system_a
  vbmeta_system_b
  vbmeta_vendor_dlkm_a
  vbmeta_vendor_dlkm_b
  vbmeta_system_dlkm_a
  vbmeta_system_dlkm_b
  super
  userdata
  metadata
)

declare -a PART_FILES=(
  "$STAGE/misc.img"
  "$STAGE/frp.img"
  "$OUT/boot.img"
  "$OUT/boot.img"
  "$OUT/init_boot.img"
  "$OUT/init_boot.img"
  "$OUT/vendor_boot.img"
  "$OUT/vendor_boot.img"
  "$OUT/vbmeta.img"
  "$OUT/vbmeta.img"
  "$OUT/vbmeta_system.img"
  "$OUT/vbmeta_system.img"
  "$OUT/vbmeta_vendor_dlkm.img"
  "$OUT/vbmeta_vendor_dlkm.img"
  "$OUT/vbmeta_system_dlkm.img"
  "$OUT/vbmeta_system_dlkm.img"
  "$STAGE/super.raw"
  "$STAGE/userdata.raw"
  "$STAGE/metadata.img"
)

start=2048
total_end=2048
for file in "${PART_FILES[@]}"; do
  size=$(file_size_bytes "$file")
  sectors=$(( (size + 511) / 512 ))
  start=$(align_sectors "$start")
  end=$(( start + sectors - 1 ))
  total_end=$end
  start=$(( end + 1 ))
done

disk_sectors=$(align_sectors $(( total_end + 4096 )))
truncate -s $(( disk_sectors * 512 )) "$STAGE/os-disk.raw"
"$SGDISK" --zap-all "$STAGE/os-disk.raw" >/dev/null

start=2048
for i in "${!PART_NAMES[@]}"; do
  file=${PART_FILES[$i]}
  size=$(file_size_bytes "$file")
  sectors=$(( (size + 511) / 512 ))
  start=$(align_sectors "$start")
  end=$(( start + sectors - 1 ))
  idx=$(( i + 1 ))
  "$SGDISK" -n "${idx}:${start}:${end}" -c "${idx}:${PART_NAMES[$i]}" "$STAGE/os-disk.raw" >/dev/null
  dd if="$file" of="$STAGE/os-disk.raw" bs=512 seek="$start" conv=notrunc status=none
  start=$(( end + 1 ))
done

cat >"$STAGE/kernel.cmdline" <<'EOF'
console=hvc0 earlycon=pl011,mmio32,0x9000000 printk.devkmsg=on audit=1 panic=-1 8250.nr_uarts=1 cma=0 firmware_class.path=/vendor/etc/ loop.max_part=7 init=/init bootconfig androidboot.boot_devices=4010000000.pcie
EOF

cat >"$STAGE/README.txt" <<EOF
Prepared plain-QEMU bundle at:
  $STAGE

Compiled build output consumed from:
  $OUT

Required compiled inputs:
  $OUT/boot.img
  $OUT/init_boot.img
  $OUT/vendor_boot.img
  $OUT/super.img
  $OUT/userdata.img
  $OUT/vbmeta.img
  $OUT/vbmeta_system.img
  $OUT/vbmeta_vendor_dlkm.img
  $OUT/vbmeta_system_dlkm.img

Main outputs:
  $STAGE/kernel
  $STAGE/initrd.img
  $STAGE/os-disk.raw
  $STAGE/kernel.cmdline

Bootable QEMU artifact:
  kernel + initrd.img + os-disk.raw

Supporting staged artifacts:
  $STAGE/super.raw
  $STAGE/userdata.raw
EOF

echo "prepared plain-QEMU bundle in $STAGE"
