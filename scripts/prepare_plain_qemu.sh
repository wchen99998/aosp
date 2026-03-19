#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/azureuser/aosp
OUT=${OUT:-$ROOT/src/out/target/product/vsoc_arm64_only}
HOSTBIN=${HOSTBIN:-$ROOT/src/out/host/linux-x86/bin}
STAGE=${STAGE:-$ROOT/plain-qemu}
DD_BS=${DD_BS:-4M}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require python3
require /usr/sbin/mke2fs
require /usr/sbin/sgdisk

for tool in simg2img unpack_bootimg; do
  if [[ ! -x "$HOSTBIN/$tool" ]]; then
    echo "missing required host tool: $HOSTBIN/$tool" >&2
    exit 1
  fi
done

mkdir -p "$STAGE"/unpack/boot "$STAGE"/unpack/vendor_boot

"$HOSTBIN/unpack_bootimg" --boot_img "$OUT/boot.img" --out "$STAGE/unpack/boot"
"$HOSTBIN/unpack_bootimg" --boot_img "$OUT/vendor_boot.img" --out "$STAGE/unpack/vendor_boot"

cp "$STAGE/unpack/boot/kernel" "$STAGE/kernel"
cp "$STAGE/unpack/vendor_boot/vendor_ramdisk00" "$STAGE/vendor_ramdisk.lz4"
cp "$STAGE/unpack/vendor_boot/bootconfig" "$STAGE/vendor_bootconfig.txt"
cp "$STAGE/unpack/vendor_boot/dtb" "$STAGE/dtb.img"

"$HOSTBIN/simg2img" "$OUT/super.img" "$STAGE/super.raw"
"$HOSTBIN/simg2img" "$OUT/userdata.img" "$STAGE/userdata.raw"

truncate -s 1M "$STAGE/misc.img"
truncate -s 1M "$STAGE/frp.img"
truncate -s 64M "$STAGE/metadata.img"
/usr/sbin/mke2fs -q -t ext4 -F "$STAGE/metadata.img"

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
  size=$(stat -c%s "$file")
  sectors=$(( (size + 511) / 512 ))
  start=$(align_sectors "$start")
  end=$(( start + sectors - 1 ))
  total_end=$end
  start=$(( end + 1 ))
done

disk_sectors=$(align_sectors $(( total_end + 4096 )))
truncate -s $(( disk_sectors * 512 )) "$STAGE/os-disk.raw"
/usr/sbin/sgdisk --zap-all "$STAGE/os-disk.raw" >/dev/null

start=2048
for i in "${!PART_NAMES[@]}"; do
  file=${PART_FILES[$i]}
  size=$(stat -c%s "$file")
  sectors=$(( (size + 511) / 512 ))
  start=$(align_sectors "$start")
  end=$(( start + sectors - 1 ))
  idx=$(( i + 1 ))
  offset_bytes=$(( start * 512 ))
  /usr/sbin/sgdisk -n "${idx}:${start}:${end}" -c "${idx}:${PART_NAMES[$i]}" "$STAGE/os-disk.raw" >/dev/null
  dd if="$file" of="$STAGE/os-disk.raw" bs="$DD_BS" seek="$offset_bytes" oflag=seek_bytes conv=notrunc status=none
  start=$(( end + 1 ))
done

cat >"$STAGE/kernel.cmdline" <<'EOF'
console=hvc0 earlycon=pl011,mmio32,0x9000000 printk.devkmsg=on audit=1 panic=-1 8250.nr_uarts=1 cma=0 firmware_class.path=/vendor/etc/ loop.max_part=7 init=/init bootconfig androidboot.boot_devices=4010000000.pcie
EOF

cat >"$STAGE/README.txt" <<EOF
Prepared plain-QEMU bundle at:
  $STAGE

Main outputs:
  $STAGE/kernel
  $STAGE/initrd.img
  $STAGE/os-disk.raw
  $STAGE/kernel.cmdline
EOF

echo "prepared plain-QEMU bundle in $STAGE"
