#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/azureuser/aosp
STAGE=${STAGE:-$ROOT/plain-qemu}
QEMU=${QEMU:-/usr/bin/qemu-system-aarch64}
QEMU_DISPLAY=${QEMU_DISPLAY:-none}
QEMU_GPU_DEVICE=${QEMU_GPU_DEVICE:-virtio-gpu-pci,id=gpu0,xres=720,yres=1280}
QEMU_HOST_ADB_PORT=${QEMU_HOST_ADB_PORT:-6520}
# Disabled by default so background launches do not get stopped by job control.
# Set to 0..16 explicitly if you want a virtconsole attached to stdio.
QEMU_STDIO_HVC=${QEMU_STDIO_HVC:-99}
QEMU_HVC0_FILE=${QEMU_HVC0_FILE:-}
QEMU_HVC2_FILE=${QEMU_HVC2_FILE:-}
QEMU_BOOT_SLOT_SUFFIX=${QEMU_BOOT_SLOT_SUFFIX:-_a}
QEMU_BOOT_FORCE_NORMAL_BOOT=${QEMU_BOOT_FORCE_NORMAL_BOOT:-1}
QEMU_BOOT_VERIFIEDBOOTSTATE=${QEMU_BOOT_VERIFIEDBOOTSTATE:-orange}
QEMU_BOOT_FSTAB_SUFFIX=${QEMU_BOOT_FSTAB_SUFFIX:-cf.f2fs.hctr2}
QEMU_BOOT_BOOT_DEVICES=${QEMU_BOOT_BOOT_DEVICES:-4010000000.pcie}
QEMU_BOOT_SERIALCONSOLE=${QEMU_BOOT_SERIALCONSOLE:-0}
QEMU_BOOT_CPUVULKAN_VERSION=${QEMU_BOOT_CPUVULKAN_VERSION:-4202496}
QEMU_BOOT_HARDWARE_EGL=${QEMU_BOOT_HARDWARE_EGL:-angle}
QEMU_BOOT_HARDWARE_GRALLOC=${QEMU_BOOT_HARDWARE_GRALLOC:-minigbm}
QEMU_BOOT_HARDWARE_HWCOMPOSER=${QEMU_BOOT_HARDWARE_HWCOMPOSER:-ranchu}
QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE=${QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE:-client}
QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE:-drm}
QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT:-rgba}
QEMU_BOOT_HARDWARE_VULKAN=${QEMU_BOOT_HARDWARE_VULKAN:-ranchu}
QEMU_BOOT_LCD_DENSITY=${QEMU_BOOT_LCD_DENSITY:-320}
QEMU_BOOT_OPENGLES_VERSION=${QEMU_BOOT_OPENGLES_VERSION:-196609}
QEMU_BOOT_HARDWARE_GLTRANSPORT=${QEMU_BOOT_HARDWARE_GLTRANSPORT:-}
QEMU_RUN_DIR=${QEMU_RUN_DIR:-$STAGE/run-$(date +%Y%m%d-%H%M%S)}

require_file() {
  local path=$1
  [[ -f "$path" ]] || {
    echo "missing required staged file: $path" >&2
    exit 1
  }
}

if [[ ! -x "$QEMU" ]]; then
  echo "missing QEMU binary: $QEMU" >&2
  exit 1
fi

for file in \
  "$STAGE/kernel" \
  "$STAGE/initrd.img" \
  "$STAGE/os-disk.raw" \
  "$STAGE/kernel.cmdline"; do
  require_file "$file"
done

CMDLINE=$(tr '\n' ' ' <"$STAGE/kernel.cmdline" | sed 's/[[:space:]]\+/ /g')
CMDLINE+=" androidboot.cpuvulkan.version=${QEMU_BOOT_CPUVULKAN_VERSION}"
CMDLINE+=" androidboot.hardware.egl=${QEMU_BOOT_HARDWARE_EGL}"
CMDLINE+=" androidboot.hardware.gralloc=${QEMU_BOOT_HARDWARE_GRALLOC}"
CMDLINE+=" androidboot.hardware.hwcomposer=${QEMU_BOOT_HARDWARE_HWCOMPOSER}"
CMDLINE+=" androidboot.hardware.hwcomposer.mode=${QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE}"
CMDLINE+=" androidboot.hardware.hwcomposer.display_finder_mode=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE}"
CMDLINE+=" androidboot.hardware.hwcomposer.display_framebuffer_format=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT}"
CMDLINE+=" androidboot.lcd_density=${QEMU_BOOT_LCD_DENSITY}"
CMDLINE+=" androidboot.opengles.version=${QEMU_BOOT_OPENGLES_VERSION}"
if [[ -n "$QEMU_BOOT_HARDWARE_VULKAN" ]]; then
  CMDLINE+=" androidboot.hardware.vulkan=${QEMU_BOOT_HARDWARE_VULKAN}"
fi
if [[ -n "$QEMU_BOOT_HARDWARE_GLTRANSPORT" ]]; then
  CMDLINE+=" androidboot.hardware.gltransport=${QEMU_BOOT_HARDWARE_GLTRANSPORT}"
fi
INITRD="$STAGE/initrd.img"
mkdir -p "$QEMU_RUN_DIR"

if [[ -f "$STAGE/vendor_ramdisk.lz4" && -f "$STAGE/vendor_bootconfig.txt" ]]; then
  RAMDISK_BASE="$STAGE/combined_ramdisk.img"
  if [[ ! -f "$RAMDISK_BASE" && -f "$STAGE/generic_ramdisk.img" ]]; then
    RAMDISK_BASE="$QEMU_RUN_DIR/combined_ramdisk.img"
    cat "$STAGE/vendor_ramdisk.lz4" "$STAGE/generic_ramdisk.img" >"$RAMDISK_BASE"
  elif [[ ! -f "$RAMDISK_BASE" ]]; then
    RAMDISK_BASE="$STAGE/vendor_ramdisk.lz4"
  fi

  cat >"$QEMU_RUN_DIR/bootconfig.extra.txt" <<EOF
androidboot.hardware=cutf_cvm
androidboot.serialno=CUTTLEFISHCVD01
androidboot.lcd_density=${QEMU_BOOT_LCD_DENSITY}
androidboot.setupwizard_mode=OPTIONAL
androidboot.selinux=permissive
androidboot.verifiedbootstate=${QEMU_BOOT_VERIFIEDBOOTSTATE}
androidboot.vbmeta.device=PARTUUID=unknown
androidboot.vbmeta.avb_version=1.1
androidboot.vbmeta.device_state=unlocked
androidboot.vbmeta.hash_alg=sha256
androidboot.vbmeta.size=4416
androidboot.vbmeta.digest=0000000000000000000000000000000000000000000000000000000000000000
androidboot.slot_suffix=${QEMU_BOOT_SLOT_SUFFIX}
androidboot.force_normal_boot=${QEMU_BOOT_FORCE_NORMAL_BOOT}
androidboot.fstab_suffix=${QEMU_BOOT_FSTAB_SUFFIX}
androidboot.boot_devices=${QEMU_BOOT_BOOT_DEVICES}
androidboot.serialconsole=${QEMU_BOOT_SERIALCONSOLE}
androidboot.openthread_node_id=1
androidboot.vsock_lights_cid=3
androidboot.vsock_lights_port=6900
androidboot.cpuvulkan.version=${QEMU_BOOT_CPUVULKAN_VERSION}
androidboot.hardware.gralloc=${QEMU_BOOT_HARDWARE_GRALLOC}
androidboot.hardware.hwcomposer=${QEMU_BOOT_HARDWARE_HWCOMPOSER}
androidboot.hardware.hwcomposer.mode=${QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE}
androidboot.hardware.hwcomposer.display_finder_mode=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE}
androidboot.hardware.hwcomposer.display_framebuffer_format=${QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT}
androidboot.hardware.egl=${QEMU_BOOT_HARDWARE_EGL}
androidboot.lcd_density=${QEMU_BOOT_LCD_DENSITY}
androidboot.opengles.version=${QEMU_BOOT_OPENGLES_VERSION}
androidboot.vendor.apex.com.android.hardware.keymint=com.android.hardware.keymint.rust_nonsecure
androidboot.vendor.apex.com.android.hardware.gatekeeper=com.android.hardware.gatekeeper.nonsecure
androidboot.vendor.apex.com.android.hardware.graphics.composer=com.android.hardware.graphics.composer.ranchu
EOF

  if [[ -n "$QEMU_BOOT_HARDWARE_VULKAN" ]]; then
    echo "androidboot.hardware.vulkan=${QEMU_BOOT_HARDWARE_VULKAN}" >>"$QEMU_RUN_DIR/bootconfig.extra.txt"
  fi

  if [[ -n "$QEMU_BOOT_HARDWARE_GLTRANSPORT" ]]; then
    echo "androidboot.hardware.gltransport=${QEMU_BOOT_HARDWARE_GLTRANSPORT}" >>"$QEMU_RUN_DIR/bootconfig.extra.txt"
  fi

  cat "$QEMU_RUN_DIR/bootconfig.extra.txt" "$STAGE/vendor_bootconfig.txt" >"$QEMU_RUN_DIR/bootconfig.combined.txt"

  python3 - "$RAMDISK_BASE" "$QEMU_RUN_DIR/bootconfig.combined.txt" "$QEMU_RUN_DIR/initrd.img" <<'PY'
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

  INITRD="$QEMU_RUN_DIR/initrd.img"
fi

args=(
  -machine virt,gic-version=2,usb=off,dump-guest-core=off
  -cpu max
  -m 4096
  -smp 4,cores=4,threads=1
  -no-user-config
  -nodefaults
  -serial none
  -monitor none
  -kernel "$STAGE/kernel"
  -initrd "$INITRD"
  -append "$CMDLINE"
  -device virtio-serial-pci-non-transitional,max_ports=32,id=virtio-serial
)

for n in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  if [[ "$n" == "$QEMU_STDIO_HVC" ]]; then
    args+=(-chardev "stdio,id=hvc${n},signal=off")
  elif [[ "$n" == "0" && -n "$QEMU_HVC0_FILE" ]]; then
    args+=(-chardev "file,id=hvc0,path=$QEMU_HVC0_FILE,append=off")
  elif [[ "$n" == "2" && -n "$QEMU_HVC2_FILE" ]]; then
    args+=(-chardev "file,id=hvc2,path=$QEMU_HVC2_FILE,append=off")
  else
    args+=(-chardev "null,id=hvc${n}")
  fi
  args+=(-device "virtconsole,bus=virtio-serial.0,chardev=hvc${n}")
done

args+=(-display "$QEMU_DISPLAY")

if [[ -n "$QEMU_GPU_DEVICE" ]]; then
  args+=(-device "$QEMU_GPU_DEVICE")
fi

args+=(
  -drive "file=$STAGE/os-disk.raw,if=none,id=osdisk,format=raw,aio=threads"
  -device virtio-blk-pci-non-transitional,drive=osdisk,id=virtio-disk0,bootindex=1
  -netdev "user,id=net0,hostfwd=tcp::${QEMU_HOST_ADB_PORT}-:5555"
  -device virtio-net-pci-non-transitional,netdev=net0,id=net0
  -device virtio-rng-pci-non-transitional
)

exec "$QEMU" "${args[@]}"
