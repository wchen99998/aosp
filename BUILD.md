# AOSP QEMU Build Notes

## Workspace

- Root workspace: `/home/azureuser/aosp`
- Source tree: `/home/azureuser/aosp/src`
- Product output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`

## Product

The build target is:

```bash
cd /home/azureuser/aosp/src
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
```

That lunch target resolves to:

- `TARGET_PRODUCT=aosp_cf_arm64_only_phone_qemu`
- `TARGET_ARCH=arm64`

Important naming detail:

- `aosp_cf_arm64_only_phone_qemu` is the built product in `src/`
- `plain-qemu/` is only the staged no-harness runtime bundle created later by
  the workspace scripts
- `plain-qemu` is not a second lunch flavor

## Host Prerequisites

Required to build:

```bash
sudo apt-get update
sudo apt-get install -y rsync
```

Required to stage and validate the built image in this workspace:

```bash
sudo apt-get install -y e2fsprogs gdisk f2fs-tools xvfb
```

Notes:

- `rsync` was required by the AOSP build and its absence caused an earlier
  failure
- `mke2fs` and `sgdisk` are used by `scripts/prepare_plain_qemu.sh`
- `xvfb` is used only for the no-GPU software-rendered runtime validation

## Build Command

Run from `/home/azureuser/aosp/src`:

```bash
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
m -j$(nproc)
```

The current image build completed successfully.

## Source Changes In `src/`

The tracked source changes live under `src/device/google/cuttlefish` and are
exported in `/home/azureuser/aosp/patches/0001-cuttlefish-qemu.patch`.

High-level changes:

- `AndroidProducts.mk`
  - adds the `aosp_cf_arm64_only_phone_qemu` lunch product
- `vsoc_arm64_only/phone/aosp_cf_qemu.mk`
  - inherits the stock arm64-only phone product
  - keeps Gatekeeper and KeyMint on nonsecure in-guest implementations
  - keeps the ranchu graphics composer
  - disables the light HAL and Thread network pieces for this QEMU product
  - adds QEMU-specific metadata
  - does not bake a fixed graphics backend into read-only properties
- `shared/device.mk`
  - gates light and Thread network package inclusion so the QEMU child product
    can disable them cleanly
- `shared/phone/device_vendor.mk`
  - keeps virgl packaging available by default so the same built image can be
    used on other machines with virgl-capable hosts
- `shared/config/qemu/init.vendor.qemu.rc`
  - layers a small QEMU-specific init fragment on top of stock cuttlefish init
  - stops `socket_vsock_proxy`
  - stops `setup_wifi` and `init_wifi_sh`
  - brings `eth0` up directly

Important build-graph detail:

- the stock `init.cutf_cvm.rc` is not replaced
- a separate QEMU init fragment is installed instead
- replacing the stock prebuilt caused an install-path conflict during the build

## Graphics Backend Policy

The built image is intentionally launch-selectable:

- software-rendered validation on this no-GPU server uses
  `androidboot.hardware.egl=angle` and `androidboot.hardware.vulkan=pastel`
- virgl-capable runtime hosts can launch the same image with a different QEMU
  GPU device and different `androidboot.hardware.*` values
- the source tree does not hardcode `ro.hardware.egl=mesa` anymore

That is why the build product is still `aosp_cf_arm64_only_phone_qemu`, while
the runtime choice is made later by `scripts/run_plain_qemu.sh`.

## After Build

After a successful build:

```bash
cd /home/azureuser/aosp
./scripts/prepare_plain_qemu.sh
```

Then follow `/home/azureuser/aosp/BOOT.md`.

Consistency rule:

- restage only from a consistent image set
- if `super.img` changes, keep the matching `vbmeta*` images from the same
  build
- then rerun `./scripts/prepare_plain_qemu.sh`
