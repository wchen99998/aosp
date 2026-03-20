# AOSP QEMU Build, Bundle, And Restage

## Workspace

- Root workspace: `/home/azureuser/aosp`
- Source tree: `/home/azureuser/aosp/src`
- Product output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- Staged bundle: `/home/azureuser/aosp/plain-qemu`
- Canonical docs: `/home/azureuser/aosp/docs`

The build target is `aosp_cf_arm64_only_phone_qemu`, but the scripts still
consume the board-style output directory above.

## Host Prerequisites

Install the tools used by the build and bundle flow:

```bash
sudo apt-get update
sudo apt-get install -y rsync e2fsprogs gdisk f2fs-tools qemu-system-arm xvfb
```

Notes:

- `rsync` is required by the AOSP build.
- `scripts/prepare_plain_qemu.sh` uses `scripts/unpack_bootimg.py`, so the
  host `unpack_bootimg` binary is not required for staging.
- `qemu-system-aarch64` is provided by the Ubuntu `qemu-system-arm` package.
- `adb` is taken from `/home/azureuser/aosp/src/out/host/linux-x86/bin/adb`.

## Build Target

Run from `/home/azureuser/aosp/src`:

```bash
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu trunk_staging userdebug
m -j$(nproc)
```

That resolves to `TARGET_PRODUCT=aosp_cf_arm64_only_phone_qemu` and
`TARGET_ARCH=arm64`.

## Stage The Bundle

After a successful build:

```bash
cd /home/azureuser/aosp
./scripts/prepare_plain_qemu.sh
```

The staging script consumes these build artifacts from
`src/out/target/product/vsoc_arm64_only`:

- `boot.img`
- `init_boot.img`
- `vendor_boot.img`
- `super.img`
- `userdata.img`
- `vbmeta.img`
- `vbmeta_system.img`
- `vbmeta_vendor_dlkm.img`
- `vbmeta_system_dlkm.img`

It produces:

- `plain-qemu/kernel`
- `plain-qemu/initrd.img`
- `plain-qemu/os-disk.raw`
- `plain-qemu/kernel.cmdline`

It also keeps supporting artifacts such as `vendor_bootconfig.txt`,
`combined_ramdisk.img`, `super.raw`, `userdata.raw`, `misc.img`, `frp.img`, and
`metadata.img`.

## Release Bundle

`scripts/make_release_bundle.sh` packages the build outputs and emits a
manifest and checksum set under `release-assets/`.

Example:

```bash
cd /home/azureuser/aosp
./scripts/make_release_bundle.sh
```

Use the `OUT`, `RELEASE_DIR`, `DATE`, and `TAG` environment variables if you
need to override the defaults.

## Restage From `release-assets`

Use this when you want to rebuild the plain-QEMU staging tree from an exported
bundle instead of from a local `m` output directory.

1. Extract the release archive somewhere under the repo root or in a temp
   directory:

   ```bash
   cd /home/azureuser/aosp
   mkdir -p tmp/release-extract
   tar --zstd -xf release-assets/<product>-out-<date>.tar.zst -C tmp/release-extract
   ```

2. Restage the bundle from that extracted output directory:

   ```bash
   cd /home/azureuser/aosp
   OUT=/home/azureuser/aosp/tmp/release-extract \
     STAGE=/home/azureuser/aosp/plain-qemu \
     ./scripts/prepare_plain_qemu.sh
   ```

   If you extracted the archive directly into
   `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`, you can omit
   `OUT=` and just rerun `./scripts/prepare_plain_qemu.sh`.

The release bundle is the source of truth for the image set; `prepare_plain_qemu.sh`
turns it into the bootable `plain-qemu/` staging directory.
