# QEMU Graphics Validation

Use this checklist after rebuilding or changing the graphics stack for the QEMU
product.

## Boot-Time Checks

- Confirm `getprop debug.hwui.renderer` is populated before
  `surfaceflinger` starts.
- Confirm `getprop debug.renderengine.backend` is populated before
  `surfaceflinger` starts when the boot property is supplied.
- Confirm the guest does not log a missing
  `ro.boot.hardware.guest_hwui_renderer` error on first boot.
- Confirm `getprop ro.zygote.disable_gl_preload` reflects the boot contract
  when renderer preload is disabled.
- Confirm `getprop ro.boot.vendor.apex.com.android.hardware.graphics.composer`
  matches the selected composer backend.
- Confirm `getprop ro.hardware.hwcomposer` matches the intended product choice.

## Refresh-Policy Checks

- Confirm `cmd overlay lookup android android:integer/config_defaultPeakRefreshRate`
  returns `120`.
- Confirm `cmd overlay lookup android android:integer/config_defaultRefreshRate`
  returns `120`.
- On the currently validated plain-QEMU/ranchu path, confirm `dumpsys display`
  still reports `renderFrameRate 75.0` and supported refresh rates that include
  `75.0`, `37.5`, and `25.0`.
- Treat the remaining 75 Hz runtime cap as a host/display-mode advertisement
  problem once the overlay values above are correct.
- Confirm `ro.surface_flinger.game_default_frame_rate_override=0` at runtime.
- Confirm `debug.graphics.game_default_frame_rate.disabled=true` at runtime.
- Treat `persist.graphics.game_default_frame_rate.enabled` as a build-time
  product property on this branch; do not rely on it as the runtime signal.
- Do not treat `SurfaceFlinger`'s fixed `game_default_frame_rate: true` aconfig
  line as proof that the product policy failed.

## Composer Checks

- Confirm the mounted composer APEX matches the selected backend.
- Confirm the active composer implementation is not accidentally falling back
  to Ranchu when the product or boot contract intends a different backend.
- Confirm the `androidboot.vendor.apex.com.android.hardware.graphics.composer`
  value matches the selected `hwcomposer`.

## Launcher Checks

- Confirm `QEMU_BOOT_HARDWARE_GUEST_HWUI_RENDERER` maps to
  `androidboot.hardware.guest_hwui_renderer`.
- Confirm `QEMU_BOOT_HARDWARE_GUEST_DISABLE_RENDERER_PRELOAD` maps to
  `androidboot.hardware.guest_disable_renderer_preload`.
- Confirm `QEMU_BOOT_DEBUG_RENDERENGINE_BACKEND` maps to
  `androidboot.debug.renderengine.backend`.
- Confirm `QEMU_BOOT_VENDOR_APEX_GRAPHICS_COMPOSER` maps to the matching
  composer APEX, or is derived from `QEMU_BOOT_HARDWARE_HWCOMPOSER` when left
  unset.

## Interpretation

If a later boot requires restarting SurfaceFlinger to "fix" the graphics
backend, the contract is wrong. The boot properties, product defaults, or
composer packaging should be corrected instead.
