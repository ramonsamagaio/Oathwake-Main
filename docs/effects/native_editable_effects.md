# Native editable effects

These effects intentionally avoid custom emitter scripts. They use native Godot nodes, `GPUParticles2D`, `CanvasModulate`, `LightOccluder2D`, `PointLight2D`, `ShaderMaterial`, and procedural `.tres` texture resources so the look can be tuned directly in the Inspector.

No new sprite/image files are required by this setup. The particle and light textures are editable Godot resources under `res://resources/effects/textures/`.

## Main boss temple rig

Drag this into the boss room scene:

- `res://scenes/effects/BossTempleNativeVFXRoot.tscn`

It contains:

- `CanvasModulate` for the dark room ambience
- `Lights` with editable `PointLight2D` braziers and altar light
- `LightOccluders` with editable `LightOccluder2D` shadow polygons
- `FogLayer_Shader`
- `DustAshParticles`
- `RitualSeal_Overlay_Shader`
- `Halo_Overlay_Shader`
- `AltarAura_Shader`
- `CrackCorruptionOverlay_Shader`
- `AltarAirDistortion_Shader`
- `VignetteOverlay`
- `FlashOverlay`

## Individual scenes

- `res://scenes/effects/BossTempleCanvasModulate.tscn`
- `res://scenes/effects/BossTempleLightingRig.tscn`
- `res://scenes/effects/BossTempleLightOccluders.tscn`
- `res://scenes/effects/VignetteOverlay.tscn`
- `res://scenes/effects/FogLayerShader.tscn`
- `res://scenes/effects/DustAshParticles.tscn`
- `res://scenes/effects/RitualSeal_Overlay_Shader.tscn`
- `res://scenes/effects/Halo_Overlay_Shader.tscn`
- `res://scenes/effects/AltarAura_Shader.tscn`
- `res://scenes/effects/CrackCorruptionOverlay_Shader.tscn`
- `res://scenes/effects/DivineFlashOverlay.tscn`
- `res://scenes/effects/DivineFlashMaskOverlay.tscn`
- `res://scenes/effects/AltarAirDistortion_Shader.tscn`
- `res://scenes/effects/PurpleEmberEmitterNative.tscn`
- `res://scenes/effects/FireflyAreaNative.tscn`
- `res://scenes/effects/PaletteMistEmitterNative.tscn`
- `res://scenes/effects/PurpleMistEmitterNative.tscn`
- `res://scenes/effects/GlowOverlayNative.tscn`
- `res://scenes/effects/PurpleSoftGlow2D.tscn`
- `res://scenes/effects/AltarNativeVFXRig.tscn`

## Glow overlay

Use this for a native editable glow field:

- `res://scenes/effects/GlowOverlayNative.tscn`

Open the assigned material:

- `res://resources/effects/materials/purple_soft_glow_material.tres`

Inspector controls include:

- `palette_color_1` through `palette_color_6`
- `palette_count`
- `color_cycle_speed`
- `palette_blend`
- `pulse_speed`
- `pulse_strength`
- `flicker_speed`
- `flicker_strength`
- `flicker_randomness`
- `glow_intensity`
- `opacity`
- `core_radius`
- `edge_radius`
- `falloff`
- `pixel_steps`

## Ember emitter palette glow

Use:

- `res://scenes/effects/PurpleEmberEmitterNative.tscn`

The old script-style colored-pixel behavior is now done through a native `GPUParticles2D` plus this material:

- `res://resources/effects/materials/ember_particle_palette_glow_material.tres`

The particle material gives each particle a core plus circular glow. It also cycles colors quickly inside the palette. Edit the node for movement and edit the material for color/glow/flicker.

Useful controls:

- Movement: `Amount`, `Lifetime`, `Process Material > Initial Velocity`, `Gravity`, `Scale Min/Max`
- Palette: `palette_color_1` through `palette_color_6`, `palette_count`
- Color motion: `color_cycle_speed`, `palette_blend`, `particle_color_randomness`
- Pixel glow: `core_radius`, `halo_radius`, `core_intensity`, `glow_intensity`
- Flicker: `flicker_speed`, `flicker_strength`, `flicker_randomness`

## Firefly area

Use:

- `res://scenes/effects/FireflyAreaNative.tscn`

This scene no longer depends on Godot's built-in `Trails` checkbox. That checkbox can make small 2D particles look frozen or disappear depending on the trail settings. Instead, the scene has two editable emitters:

- `Fireflies`: the visible colored fireflies
- `FireflyGlowTrail`: a second soft native particle layer that behaves like a trail/glow cloud

Color and glow controls live in:

- `res://resources/effects/materials/firefly_particle_palette_glow_material.tres`
- `res://resources/effects/materials/firefly_trail_palette_glow_material.tres`

Movement speed lives in:

- `res://resources/effects/particles/firefly_particles.tres`
- `res://resources/effects/particles/firefly_glow_trail_particles.tres`

## Generic palette mist

Use:

- `res://scenes/effects/PaletteMistEmitterNative.tscn`

The older `PurpleMistEmitterNative.tscn` now points at the same generic palette mist setup.

Color/evolution controls live in:

- `res://resources/effects/materials/generic_mist_palette_material.tres`

Useful controls:

- `palette_color_1` through `palette_color_6`
- `palette_count`
- `color_cycle_speed`
- `opacity`
- `evolution_speed`
- `drift_speed_x`
- `drift_speed_y`
- `noise_scale`
- `noise_contrast`
- `softness`

## How to edit particles

1. Open one of the particle scenes.
2. Select the `GPUParticles2D` node.
3. Edit the simple particle values directly:
   - `Amount`
   - `Lifetime`
   - `Preprocess`
   - `Randomness`
   - `Texture`
4. Expand `Process Material`.
5. Click the assigned `ParticleProcessMaterial` resource and edit:
   - `Emission Shape`
   - `Emission Box Extents`
   - `Direction`
   - `Spread`
   - `Gravity`
   - `Initial Velocity Min/Max`
   - `Scale Min/Max`
   - `Color`
   - `Color Ramp`

## How to edit shader overlays

Select the overlay node, open the assigned `ShaderMaterial`, and tune the exposed parameters in the Inspector.

Useful files:

- Vignette: `res://resources/effects/materials/vignette_overlay_material.tres`
- Low floor fog: `res://resources/effects/materials/floor_dead_fog_material.tres`
- Ritual seal pulse: `res://resources/effects/materials/ritual_pulse_overlay_material.tres`
- Broken halo pulse: `res://resources/effects/materials/broken_halo_pulse_material.tres`
- Altar dark aura: `res://resources/effects/materials/altar_dark_aura_material.tres`
- Crack/corruption glow: `res://resources/effects/materials/corruption_crack_glow_material.tres`
- Divine flash: `res://resources/effects/materials/divine_flash_overlay_material.tres`
- Air distortion: `res://resources/effects/materials/altar_air_distortion_material.tres`
- Palette soft glow: `res://resources/effects/materials/purple_soft_glow_material.tres`

## PNG overlay slots

These scenes are intentionally created without texture assigned because they are meant to receive your own PNG in the Inspector:

- `RitualSeal_Overlay_Shader.tscn`
- `Halo_Overlay_Shader.tscn`
- `CrackCorruptionOverlay_Shader.tscn`
- `DivineFlashMaskOverlay.tscn`

Open the scene, select the `Sprite2D`, assign your PNG to `Texture`, then edit the `ShaderMaterial` parameters.

## Flash usage

Use full-screen flash:

- `res://scenes/effects/DivineFlashOverlay.tscn`

Use masked/local flash:

- `res://scenes/effects/DivineFlashMaskOverlay.tscn`

Edit:

- `res://resources/effects/materials/divine_flash_overlay_material.tres`

Useful controls:

- `flash_intensity`
- `flash_speed`
- `flash_width`
- `manual_phase`
- `auto_flash_amount`
- `use_texture_alpha_mask`
- `mask_power`

Set `auto_flash_amount` to `1.0` for automatic looping flash, or `0.0` for manual/static control through `manual_phase`. Set `flash_intensity` to `0.0` to disable it.

## Vignette usage

Open:

- `res://resources/effects/materials/vignette_overlay_material.tres`

The main knob is `intensity`. Lower it if the screen edge is crushing the gameplay area. Raise it if the temple needs to feel more claustrophobic.

## Light occluder usage

Open:

- `res://scenes/effects/BossTempleLightOccluders.tscn`

Each child is a `LightOccluder2D`. Select one, edit its `OccluderPolygon2D`, then move/rotate/scale it behind the actual column, altar, statue, wall, or boss body.

For shadows to appear, the nearby `PointLight2D` must have `Shadow > Enabled` active. The light rig scene already has shadows enabled on the braziers and altar light.

## Important

If an effect instance is reused in many places and you want changes only in one place, use **Make Unique** on its material/resource before editing. This keeps local edits from changing every copy of the same resource.
