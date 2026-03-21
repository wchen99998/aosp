# AOSP QEMU Build Notes

## Workspace

- Root workspace: `/home/azureuser/aosp`
- Source tree: `/home/azureuser/aosp/src`
- Product output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- Staged no-harness bundle: `/home/azureuser/aosp/plain-qemu`

Important path detail:

- even though the lunch target is `aosp_cf_arm64_only_phone_qemu`, the build
  output directory used by the scripts is still
  `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- `plain-qemu/` is a staged runtime bundle created after the build; it is not a
  second lunch flavor

## Host Prerequisites

Required to build in this workspace:

```bash
sudo apt-get update
sudo apt-get install -y rsync
```

Required to stage and validate the built image here:

```bash
sudo apt-get install -y e2fsprogs gdisk f2fs-tools qemu-system-arm xvfb
```

Notes:

- `rsync` was required by the AOSP build and its absence caused an earlier
  build failure
- `scripts/prepare_plain_qemu.sh` vendors its own boot-image unpacker at
  `scripts/unpack_bootimg.py`
- external staging tools are `simg2img`, `mke2fs`, and `sgdisk`
- `qemu-system-aarch64` is provided by the Ubuntu `qemu-system-arm` package
- `adb` is taken from the AOSP host tools under
  `/home/azureuser/aosp/src/out/host/linux-x86/bin/adb`

## Build Target

Run from `/home/azureuser/aosp/src`:

```bash
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
m -j$(nproc)
```

That lunch target resolves to:

- `TARGET_PRODUCT=aosp_cf_arm64_only_phone_qemu`
- `TARGET_ARCH=arm64`

## Current Build And Validation Status

- the latest compile completed successfully on `2026-03-19`
- the latest `plain-qemu/` bundle was restaged from that build on
  `2026-03-19`
- direct plain-QEMU boot without `launch_cvd` or `run_cvd` was validated on
  `2026-03-19`
- software-GL validation on this no-GPU machine reached `adb device`
- the validated live ADB endpoint is `127.0.0.1:6530`
- `adb -s 127.0.0.1:6530 get-state` returned `device`
- `adb -s 127.0.0.1:6530 shell getprop sys.boot_completed` returned `1`
- validated fingerprint:
  `generic/aosp_cf_arm64_only_phone_qemu/vsoc_arm64_only:Baklava/MAIN/eng.azureu:userdebug/test-keys`
- validated FRP block device:
  `/dev/block/by-name/frp -> /dev/block/vda2`

## Active Source Changes In `src/`

The active source changes are under:

- `/home/azureuser/aosp/src/build/make`
- `/home/azureuser/aosp/src/device/google/cuttlefish`

High-level changes:

- `build/make/target/product/handheld_system.mk`
  - gates Bluetooth packages on `BOARD_HAVE_BLUETOOTH`
  - gates telephony packages on `TARGET_NO_TELEPHONY`
- `build/make/target/product/telephony_system_ext.mk`
  - gates `system_ext` telephony packages on `TARGET_NO_TELEPHONY`
- `device/google/cuttlefish/AndroidProducts.mk`
  - adds the `aosp_cf_arm64_only_phone_qemu` lunch product
- `device/google/cuttlefish/vsoc_arm64_only/phone/aosp_cf_qemu.mk`
  - inherits the stock arm64-only phone product
  - keeps in-guest nonsecure KeyMint and Gatekeeper
  - keeps the ranchu graphics composer
  - disables the light HAL and Thread networking
  - switches ADB transport to raw TCP on guest port `5555`
  - adds QEMU-specific metadata properties
  - layers in the QEMU init fragment
  - keeps Bluetooth and telephony enabled in the current tree
- `device/google/cuttlefish/shared/device.mk`
  - makes Gatekeeper and KeyMint package selection overridable by child products
  - gates some telephony-adjacent packages on `TARGET_NO_TELEPHONY`
  - gates Thread packages on `LOCAL_ENABLE_THREADNETWORK`
- `device/google/cuttlefish/shared/config/qemu/init.vendor.qemu.rc`
  - adds a small QEMU-only init fragment
  - stops `socket_vsock_proxy`
  - stops `setup_wifi` and `init_wifi_sh`
  - brings `eth0` up directly in `post-fs-data`
- `device/google/cuttlefish/shared/config/qemu/Android.bp`
  - installs the QEMU init fragment as vendor init file `init.qemu.rc`
- `device/google/cuttlefish/shared/graphics/device_vendor.mk`
  - makes graphics composer package selection overridable by child products
- `device/google/cuttlefish/shared/phone/device_vendor.mk`
  - makes virgl inclusion optional through `LOCAL_ENABLE_VIRGL`

Important current-tree note:

- the current validated build does not use a QEMU-specific audio-policy module
- stale experimental QEMU audio-policy leftovers were removed before the latest
  rebuild

Important build-graph detail:

- the stock `init.cutf_cvm.rc` is not replaced in-place
- the QEMU flavor adds a separate `init.qemu.rc` fragment instead
- trying to replace the stock `prebuilt_etc` directly caused an install-path
  conflict during earlier build attempts

## Graphics Backend Policy

`third-party/aosp/` is the source of truth for the guest image and its launch
defaults.

The image is intentionally launch-selectable:

- the Phase 2 guest Vulkan target is `androidboot.hardware.vulkan=ranchu`
- `pastel` remains the SwiftShader-backed fallback we are moving away from
- GPU-capable hosts are expected to pair this image with a
  gfxstream/rutabaga-capable QEMU path
- software-rendered fallback validation is still possible when the host does
  not yet expose gfxstream/rutabaga at runtime

Runtime graphics selection is done later by `scripts/run_plain_qemu.sh` through
`androidboot.hardware.*` boot properties, with `ranchu` as the default Vulkan
HAL.

The image ships both gralloc backends: `minigbm` (default for plain-QEMU) and
`ranchu` (gfxstream-native, for gfxstream-capable hosts). Both are packaged as
vendor APEXes under `com.google.cf.gralloc`, and boot-time APEX selection via
`QEMU_BOOT_HARDWARE_GRALLOC` picks the active one.

## Stage After Build

After a successful build:

```bash
cd /home/azureuser/aosp
./scripts/prepare_plain_qemu.sh
```

`scripts/prepare_plain_qemu.sh` prefers the vendored
`scripts/unpack_bootimg.py`, so you do not need the AOSP-host
`unpack_bootimg` binary to stage the bundle.

The prep script consumes these compiled outputs from the product directory:

- `boot.img`
- `init_boot.img`
- `vendor_boot.img`
- `super.img`
- `userdata.img`
- `vbmeta.img`
- `vbmeta_system.img`
- `vbmeta_vendor_dlkm.img`
- `vbmeta_system_dlkm.img`

It produces the staged no-harness bundle:

- `plain-qemu/kernel`
- `plain-qemu/initrd.img`
- `plain-qemu/os-disk.raw`
- `plain-qemu/kernel.cmdline`

Supporting staged artifacts are also kept:

- `plain-qemu/super.raw`
- `plain-qemu/userdata.raw`
- `plain-qemu/misc.img`
- `plain-qemu/frp.img`
- `plain-qemu/metadata.img`
- `plain-qemu/generic_ramdisk.img`
- `plain-qemu/combined_ramdisk.img`
- `plain-qemu/vendor_ramdisk.lz4`
- `plain-qemu/vendor_bootconfig.txt`

If needed, the scripts can target another compiled output directory or another
staging directory:

```bash
cd /home/azureuser/aosp
OUT=/path/to/out/target/product/vsoc_arm64_only \
STAGE=/path/to/plain-qemu \
./scripts/prepare_plain_qemu.sh
```

## Current Runtime Notes

The current validated no-harness boot is usable, but first boot is not quiet.

Observed behavior on the successful `2026-03-19` validation:

- first boot spends noticeable time in APEX decompression and `cppreopts`
- host `adb` can briefly show `offline` before it settles to `device`
- `SurfaceFlinger`, `bootanim`, `system_server`, and PackageManager all come up
- the guest reaches `sys.boot_completed=1`

Observed non-blocking runtime issues on that validated boot:

- `com.android.nfc` aborts and restarts after NFC HAL command timeouts
- `com.android.bluetooth` also aborts and restarts later in boot
- `audioserver` repeatedly tries to start lazy `aidl/activity`
- these issues did not prevent `adb device` or `sys.boot_completed=1`

See `/home/azureuser/aosp/BOOT.md` for the exact no-harness boot flow and the
validated launch command.
