# Creating a soft dot / soft glow texture inside Godot

Use this when you need a particle texture but do not want to import an image file.

## Create it from the Inspector

1. Select a node with a `Texture` slot, for example `GPUParticles2D` or `Sprite2D`.
2. In the Inspector, find `Texture`.
3. Click the dropdown arrow.
4. Choose `New GradientTexture2D`.
5. Click the new `GradientTexture2D` resource to open it.
6. Set:
   - `Width`: `16` for a tiny particle, `64` or `256` for glow
   - `Height`: same as width for a circular dot
   - `Fill`: radial/circular mode
   - `Fill From`: `Vector2(0.5, 0.5)`
   - `Fill To`: `Vector2(1.0, 0.5)`
7. Open the `Gradient` inside it.
8. Add color points like this:
   - center: white, alpha `1.0`
   - middle: white, alpha `0.4`
   - edge: white, alpha `0.0`

The shader or particle material can recolor it later, so the texture itself should usually stay white with alpha falloff.

## Good presets

### Tiny particle dot

- `Width`: `16`
- `Height`: `16`
- Center alpha: `1.0`
- Middle alpha: `0.8`
- Edge alpha: `0.0`

### Soft glow orb

- `Width`: `256`
- `Height`: `256`
- Center alpha: `1.0`
- Middle alpha: `0.35`
- Edge alpha: `0.0`

### Mist blob

- `Width`: `96`
- `Height`: `48`
- Center alpha: `0.45`
- Middle alpha: `0.22`
- Edge alpha: `0.0`

## Save as a reusable resource

After creating the texture:

1. Click the small arrow/menu on the texture resource.
2. Choose `Save As...`.
3. Save it under:
   - `res://resources/effects/textures/`

Examples already in the project:

- `res://resources/effects/textures/particle_soft_dot.tres`
- `res://resources/effects/textures/soft_light_radial.tres`
- `res://resources/effects/textures/mist_soft_blob.tres`

## If the texture field appears empty

Some Godot scenes can lose external `.tres` texture references while testing. When that happens, open the scene and create the `GradientTexture2D` directly inside the node's `Texture` slot. This makes it an inline subresource and avoids the missing texture problem.
