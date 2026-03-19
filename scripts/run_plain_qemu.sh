#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/azureuser/aosp
STAGE=${STAGE:-$ROOT/plain-qemu}
QEMU=${QEMU:-/usr/bin/qemu-system-aarch64}
QEMU_DISPLAY=${QEMU_DISPLAY:-none}
QEMU_GPU_DEVICE=${QEMU_GPU_DEVICE:-virtio-gpu-pci,id=gpu0,xres=720,yres=1280}
QEMU_HOST_ADB_PORT=${QEMU_HOST_ADB_PORT:-6520}

if [[ ! -f "$STAGE/kernel" || ! -f "$STAGE/initrd.img" || ! -f "$STAGE/os-disk.raw" ]]; then
  echo "missing staged bundle under $STAGE; run scripts/prepare_plain_qemu.sh first" >&2
  exit 1
fi

CMDLINE=$(tr '\n' ' ' <"$STAGE/kernel.cmdline" | sed 's/[[:space:]]\+/ /g')

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
  -initrd "$STAGE/initrd.img"
  -append "$CMDLINE"
  -device virtio-serial-pci-non-transitional,max_ports=32,id=virtio-serial
  -chardev stdio,id=hvc0,signal=off
  -device virtconsole,bus=virtio-serial.0,chardev=hvc0
)

args+=(-display "$QEMU_DISPLAY")

if [[ -n "$QEMU_GPU_DEVICE" ]]; then
  args+=(-device "$QEMU_GPU_DEVICE")
fi

for n in $(seq 1 16); do
  args+=(-chardev "null,id=hvc${n}")
  args+=(-device "virtconsole,bus=virtio-serial.0,chardev=hvc${n}")
done

args+=(
  -drive "file=$STAGE/os-disk.raw,if=none,id=osdisk,format=raw,aio=threads"
  -device virtio-blk-pci-non-transitional,drive=osdisk,id=virtio-disk0,bootindex=1
  -netdev "user,id=net0,hostfwd=tcp::${QEMU_HOST_ADB_PORT}-:5555"
  -device virtio-net-pci-non-transitional,netdev=net0,id=net0
  -device virtio-rng-pci-non-transitional
)

exec "$QEMU" "${args[@]}"
