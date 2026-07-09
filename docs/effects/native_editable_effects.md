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
- `res://scenes/effects/AltarAirDistortion_Shader.tscn`
- `res://scenes/effects/PurpleEmberEmitterNative.tscn`
- `res://scenes/effects/PurpleMistEmitterNative.tscn`
- `res://scenes/effects/FireflyAreaNative.tscn`
- `res://scenes/effects/PurpleSoftGlow2D.tscn`
- `res://scenes/effects/AltarNativeVFXRig.tscn`

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
- Purple soft glow: `res://resources/effects/materials/purple_soft_glow_material.tres`

## PNG overlay slots

These scenes are intentionally created without texture assigned because they are meant to receive your own PNG in the Inspector:

- `RitualSeal_Overlay_Shader.tscn`
- `Halo_Overlay_Shader.tscn`
- `CrackCorruptionOverlay_Shader.tscn`

Open the scene, select the `Sprite2D`, assign your PNG to `Texture`, then edit the `ShaderMaterial` parameters.

## Flash usage

`DivineFlashOverlay.tscn` starts hidden and with `flash_intensity = 0.0`. For a manual test, make the node visible and raise `flash_intensity` in the material. For gameplay, trigger it later from the boss/event logic or an `AnimationPlayer`.

## Important

If an effect instance is reused in many places and you want changes only in one place, use **Make Unique** on its material/resource before editing. This keeps local edits from changing every copy of the same resource.
