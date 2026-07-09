# Firefly area guide

There are three clear firefly options now.

## 1. Editable scripted fireflies, closest to the old look

Use:

- `res://scenes/effects/FireflyArea.tscn`

This is the old visual style, but the script was upgraded with more Inspector controls:

- longer trail range up to 96
- `trail_style`: `Pixel`, `Soft Glow`, or `Pixel + Soft Glow`
- `trail_glow_size`
- `trail_glow_alpha`
- `trail_soft_steps`
- `trail_soft_falloff`
- `soft_glow_enabled`
- `soft_glow_steps`
- `soft_glow_falloff`
- `glow_intensity`
- `color_cycle_enabled`
- `color_cycle_speed`
- `color_cycle_randomness`
- `color_blend`
- `flicker_randomness`

This is the best choice when you want each individual firefly/wisp to carry its own visible historical trail in the Compatibility renderer. It works because the script stores old positions per firefly and draws the trail from that history.

## 2. Native Compatibility-safe particle version, no real trail

Use:

- `res://scenes/effects/FireflyAreaNative.tscn`

This is now intentionally only one `GPUParticles2D` emitter. It has individual particle glow through a `ShaderMaterial`, but it does **not** fake a trail with a second emitter anymore.

Why: a second independent `GPUParticles2D` cannot follow the particles from the first one. It only creates unrelated glow particles. That was visually misleading and has been removed.

Use this version when you want native particles with:

- palette color control
- color cycle speed
- flicker speed/randomness
- glow radius/intensity
- Compatibility renderer support

Edit movement through:

- `FireflyAreaNative > Process Material`

Edit color, glow, and flicker through:

- `res://resources/effects/materials/firefly_particle_palette_glow_material.tres`

## 3. Native Forward+/Mobile trail version

Use:

- `res://scenes/effects/FireflyAreaNativeForwardTrail.tscn`

This is the same single-emitter native setup, but with native particle trails enabled. It only works when the project renderer is `Forward+` or `Mobile`. It will not work in `Compatibility`.

If the scene opens and the trail properties do not appear, enable trails manually on the `GPUParticles2D` node in the Inspector after switching renderer.

## How to switch renderer to see native particle trails

1. Save the project.
2. Go to `Project > Project Settings...`.
3. In the search bar, type `rendering_method` or just `renderer`.
4. Go to `Rendering > Renderer`.
5. Change `Rendering Method` from `gl_compatibility` / `Compatibility` to one of:
   - `forward_plus` / `Forward+`
   - `mobile` / `Mobile`
6. Close Project Settings.
7. Restart the editor if Godot asks, or close and reopen the project manually.
8. Open `res://scenes/effects/FireflyAreaNativeForwardTrail.tscn`.
9. Select the `GPUParticles2D` node and make sure `Trails > Enabled` is active.

## Important warning

Switching from `Compatibility` to `Forward+` can change the look of 2D lighting, shaders, glow, performance, and export compatibility. Test the boss room after switching. If the whole project gets visually weird, switch back to `Compatibility` and use `FireflyArea.tscn` for real per-firefly trails.
