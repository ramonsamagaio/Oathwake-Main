# Dylearn-style Grass Only Lab

Preferred isolated visual-development scene:

`res://scenes/labs/DylearnStyleGrassOnlyLab.tscn`

This lab is intentionally separate from Main, AuthoringLab, the current Oathwake terrain and the real Player. Its only job is to converge on the procedural grass look before dirt/biomes are reintroduced.

## V4: dense toon carpet

V4 was rebuilt after direct comparison with the Dylearn demo and reference captures. The important finding is that the look does not come from a single leaf shader trick. In the reference project, the floor and grass share broad world-space variation, grass movement is driven by a common stepped clock and coherent world-space noise, and both grass/floor participate in the same toon-style lighting language. Dense overlap then makes the individual grass cards visually disappear into a carpet.

### What changed from V3

- Removed chunk visibility culling entirely from this visual lab.
- Removed near/mid/far material swaps and `visible_instance_count` thinning.
- The whole test field is now one `MultiMeshInstance2D`, eliminating chunk/LOD popping.
- Replaced small Y-like tuft stamps with eight generated 32x24 clump silhouettes.
- Common clumps have a deliberately broad, opaque lower body plus irregular blades/leaves above it.
- Cards are rendered on 40x28 quads at 18x11 spacing, so neighbouring clumps overlap heavily and knit into a solid carpet.
- Six clumps are common; two taller silhouettes are rare accents.
- Floor and grass now use the same three-band world-space toon field and matching broad colour patches.
- Large colour/light changes happen in coherent masses rather than per-card colour noise.
- Wind uses the reference architecture of two diverging world-space noise samples, but every card shares one 6 FPS clock. Per-instance values only alter amplitude slightly, never animation phase.
- Player displacement remains local and root-weighted.

The generated atlas and noise textures are created at runtime. No Dylearn art asset is copied into Oathwake.

## Reference architecture inspected

The implementation was informed by the public Dylearn demo repository, especially:

- `Shaders/Grass.gdshader`
- `Shaders/Floor.gdshader`
- `Shaders/ToonShader.gdshader`
- `Scripts/ShaderGlobals.gd`
- `Scripts/CharacterManager.gd`
- `Scripts/LightDirection.gd`
- `Scenes/Demo.tscn`

The key transferable ideas are coherent world-space wind, a shared stepped animation clock, shared grass/floor colour logic, toon-band lighting, fake perspective, dense instancing and local character displacement. V4 recreates those principles for Godot 2D rather than porting the 3D scene literally.

## Test

1. Open `res://scenes/labs/DylearnStyleGrassOnlyLab.tscn`.
2. Run current scene with F6.
3. Move with WASD/arrows and hold Shift to run.
4. Confirm there is no chunk/LOD visibility popping anywhere in the camera range.
5. Look for a continuous grass carpet, with the lower portions of clumps visually merging into the floor/nearby cards.
6. Watch broad toon patches and gust regions move/read as field-level phenomena instead of isolated sprite behaviour.
7. Verify nearby grass still bends away from the test walker.

## Scope

Still deliberately excluded:

- dirt
- procedural biome composition
- current authored Oathwake terrain
- Main scene integration
- real Player sprite/rig

Those should remain out until the grass-only target is accepted.
