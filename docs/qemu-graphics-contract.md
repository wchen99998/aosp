# QEMU Graphics Contract

This document captures the QEMU graphics contract that the Cuttlefish/QEMU
product now relies on. The goal is to keep renderer selection, RenderEngine
selection, refresh policy, and composer selection aligned at boot instead of
patching behavior later with launcher-only overrides.

## What The Guest Expects

The guest graphics stack now expects the launcher and init flow to agree on the
following boot properties:

- `androidboot.hardware.guest_hwui_renderer`
- `androidboot.hardware.guest_disable_renderer_preload`
- `androidboot.debug.renderengine.backend`
- `androidboot.hardware.hwcomposer`
- `androidboot.vendor.apex.com.android.hardware.graphics.composer`
- `androidboot.hardware.gralloc`
- `androidboot.lcd_density`

The guest-side init fragment promotes these values before the first
`surfaceflinger` start:

- `ro.boot.hardware.guest_hwui_renderer` becomes `debug.hwui.renderer`
- `ro.boot.hardware.guest_disable_renderer_preload` becomes
  `ro.zygote.disable_gl_preload`
- `ro.boot.debug.renderengine.backend` becomes `debug.renderengine.backend`

That keeps HWUI and RenderEngine selection in early init, which is the point at
which SurfaceFlinger and zygote still see the contract cleanly.

## Why The QEMU Product Is Refresh-Driven

The QEMU product image now targets a 120 Hz display policy, so the framework
defaults in the guest should prefer 120 Hz rather than letting a generic 60 Hz
default dominate.

On this branch, the runtime knobs that actually expressed the policy on the
verified image were:

- `ro.surface_flinger.game_default_frame_rate_override=0`
- `debug.graphics.game_default_frame_rate.disabled=true`

`persist.graphics.game_default_frame_rate.enabled` may still be present in the
product build.prop, but it was empty at runtime on the verified image. Treat the
runtime properties above as the effective policy signal on this branch.

The product still uses a QEMU-only framework overlay to keep the framework
targeted at 120 Hz by setting both
`config_defaultPeakRefreshRate` and `config_defaultRefreshRate` to `120`, and
the fixed `SurfaceFlinger` aconfig guard still reports
`game_default_frame_rate: true`. Do not use that log line alone as evidence
that the product policy failed.

Current runtime caveat on this branch:

- the plain-QEMU/ranchu path still advertises only a 75 Hz mode at runtime
- `cmd overlay lookup` resolves the guest defaults to `120`
- `dumpsys display` still reports `renderFrameRate 75.0` until the host/display
  mode contract is updated to expose a 120 Hz mode

## Gralloc Stack

The QEMU product ships both gralloc backends:

- `minigbm` — the Cuttlefish default, packaged in the `com.google.cf.gralloc`
  APEX. Works with plain QEMU and software-GL hosts.
- `ranchu` — the gfxstream-native gralloc
  (`android.hardware.graphics.allocator-service.ranchu` and `mapper.ranchu`).
  Requires a gfxstream/rutabaga-capable QEMU host.

The active backend is selected at boot via `QEMU_BOOT_HARDWARE_GRALLOC`, which
maps to `androidboot.hardware.gralloc` and then to `ro.hardware.gralloc`. The
QEMU init fragment (`init.vendor.qemu.rc`) stops the default minigbm allocator
and starts the ranchu one when `ro.hardware.gralloc=ranchu`. The plain-QEMU
launcher defaults to `minigbm`. Set `QEMU_BOOT_HARDWARE_GRALLOC=ranchu` when
running on a gfxstream-capable host.

## Why Composer Selection Is Product-Backed

The QEMU product was previously hard-pinned to Ranchu in product packaging.
That made the runtime behavior internally consistent, but it also meant the
launcher had to keep reinforcing the same choice.

The current approach is to treat composer selection as a product decision:

- The QEMU product can ship the relevant composer backends.
- The boot contract names the active composer explicitly.
- The host launcher maps the selected `hwcomposer` to the matching composer
  APEX at boot.

That is a better boundary than hardcoding Ranchu in the product and then trying
to override it later. It also keeps the launch contract honest: if the product
is meant to validate a leaner DRM path, the product should say so directly.

## Plain-QEMU Launch Contract

The plain-QEMU scripts now mirror the same contract as the Cuttlefish host
manager:

- `QEMU_BOOT_HARDWARE_GUEST_HWUI_RENDERER`
- `QEMU_BOOT_HARDWARE_GUEST_DISABLE_RENDERER_PRELOAD`
- `QEMU_BOOT_DEBUG_RENDERENGINE_BACKEND`
- `QEMU_BOOT_VENDOR_APEX_GRAPHICS_COMPOSER`
- `QEMU_BOOT_HARDWARE_HWCOMPOSER`
- `QEMU_BOOT_HARDWARE_GRALLOC`
- `QEMU_BOOT_LCD_DENSITY`

The scripts derive `androidboot.vendor.apex.com.android.hardware.graphics.composer`
from `QEMU_BOOT_HARDWARE_HWCOMPOSER` when no explicit APEX is provided, so the
boot-time APEX and the selected composer backend stay aligned.


On this host, the launcher also mirrors critical early-boot args onto the
kernel cmdline, including `androidboot.force_normal_boot`, because bootconfig
delivery alone was not reliable enough for bundle verification.

This is the important rule for future changes:

- Change the product if the device policy changed.
- Change the launch contract if the guest needs a different boot-time renderer
  or composer choice.
- Avoid restarting SurfaceFlinger later to compensate for a missing boot
  property.

## Files To Read Together

- `src/device/google/cuttlefish/shared/config/graphics/init_graphics.vendor.rc`
- `src/device/google/cuttlefish/shared/config/qemu/init.vendor.qemu.rc`
- `src/device/google/cuttlefish/vsoc_arm64_only/phone/aosp_cf_qemu.mk`
- `src/device/google/cuttlefish/shared/device.mk`
- `scripts/run_plain_qemu.sh`
- `scripts/prepare_plain_qemu.sh`
