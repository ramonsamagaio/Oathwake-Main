# Native editable effects

These effects intentionally avoid custom emitter scripts. They use native Godot nodes and resources so the look can be tuned directly in the Inspector.

## Scenes

- `res://scenes/effects/PurpleEmberEmitterNative.tscn`
- `res://scenes/effects/PurpleMistEmitterNative.tscn`
- `res://scenes/effects/FireflyAreaNative.tscn`
- `res://scenes/effects/PurpleSoftGlow2D.tscn`
- `res://scenes/effects/AltarNativeVFXRig.tscn`

## How to edit particles

1. Open one of the native effect scenes.
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

## How to edit the glow

1. Open `res://scenes/effects/PurpleSoftGlow2D.tscn` or `AltarNativeVFXRig.tscn`.
2. Select the `PurpleSoftGlow` / `Sprite2D` node.
3. Open the assigned `ShaderMaterial`.
4. Tune the exposed shader parameters:
   - `glow_color`
   - `core_radius`
   - `edge_radius`
   - `falloff`
   - `pixel_steps`
   - `pulse_strength`
   - `pulse_speed`

## Important

If an effect instance is reused in many places and you want changes only in one place, use **Make Unique** on its material/resource before editing. This keeps local edits from changing every copy of the same resource.
