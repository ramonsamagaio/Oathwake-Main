# Firefly area guide

There are two usable firefly options now.

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

This is the best choice when you want each individual firefly/wisp to carry its own visible historical trail. Godot's native particle trails are unavailable in the Compatibility renderer, so exact per-firefly trails need this custom draw approach.

## 2. Native Compatibility-friendly particle version

Use:

- `res://scenes/effects/FireflyAreaNative.tscn`

This version avoids the built-in `Trails` checkbox and uses two native `GPUParticles2D` nodes instead:

- `Fireflies`: visible firefly pixels
- `FireflyGlowTrail`: soft glow/trail particles

The scene now has inline procedural `GradientTexture2D` resources so the texture field should no longer appear empty.

Edit motion through:

- `Fireflies > Process Material`
- `FireflyGlowTrail > Process Material`

Edit color, glow, and flicker through:

- `res://resources/effects/materials/firefly_particle_palette_glow_material.tres`
- `res://resources/effects/materials/firefly_trail_palette_glow_material.tres`

## Important Compatibility Renderer note

Do not use the native `Trails` checkbox in this project while the renderer is `GL Compatibility`. Godot shows this warning because particle trails only work in Forward+ or Mobile. The native workaround is the second emitter, `FireflyGlowTrail`.
