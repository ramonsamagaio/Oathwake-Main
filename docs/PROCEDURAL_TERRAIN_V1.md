# Oathwake Procedural Terrain V1

This is the first isolated procedural terrain slice for Oathwake.

## Goals

- Keep the existing 64x64 visual terrain and nearest filtering.
- Generate grass/dirt regions deterministically from a world seed.
- Reuse the existing grass/dirt terrain set so authored and procedural terrain share the same visual language.
- Scatter tall pixel grass only over pixels marked as grass in the existing dual-mask atlas.
- Render grass in GPU-instanced chunks instead of one Sprite2D per tuft.
- Animate wind at a quantized frame rate so motion reads as pixel animation instead of smooth vector animation.
- Bend nearby tufts away from the player without CPU-updating every tuft.
- Expose a sampler API that can later drive rocks, trees, resources, fauna, biome selection and world chunks.

## Main pieces

- `ProceduralTerrainProfile.gd`: art and generation tuning.
- `ProceduralTerrainSampler.gd`: deterministic world-space noise fields and terrain samples.
- `ProceduralTerrainRegion2D.gd`: fills the current Oathwake terrain set procedurally.
- `ProceduralGrassField2D.gd`: deterministic scatter and MultiMesh2D chunk creation.
- `procedural_grass_tuft.gdshader`: pixel tuft silhouette, stepped wind and player bending.
- `OathwakeProceduralTerrainRegion.tscn`: drop-in reusable region.
- `ProceduralTerrainLab.tscn`: isolated playtest scene.

## Test in Godot

1. Open `res://scenes/labs/ProceduralTerrainLab.tscn`.
2. Run the current scene with F6.
3. Walk through the generated grass with WASD or arrow keys.
4. Confirm that grass tufts only appear on grass-colored portions of the terrain, not on dirt pixels.
5. Confirm that wind moves in stepped frames and nearby tufts bend around the player.
6. Change `world_seed` in `oathwake_procedural_grass_profile.tres` and rerun. The same seed must reproduce the same terrain and grass layout.

## Extension path

The sampler is intentionally independent from rendering. Future terrain systems should query the same sample fields instead of inventing separate random logic. This allows one world seed to control biome, vegetation, resources and fauna consistently.
