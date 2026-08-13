# Grass-only Dylearn-inspired lab

This lab intentionally isolates grass from Oathwake's authored terrain pipeline.

## Why it exists

The first procedural terrain prototype mixed two problems at once:

1. grass/dirt terrain generation and transition tiles;
2. animated, interactive grass rendering.

That made it harder to judge the visual target. `DylearnStyleGrassOnlyLab.tscn`
removes dirt and the existing terrain art completely so the grass rendering can
be tuned on its own.

## What this pass borrows conceptually

Reference project:

- DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo
- https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo

The reference project's code is MIT licensed. Its art assets are CC BY 4.0.
This Oathwake lab uses newly authored tiny white-mask leaf sprites rather than
copying the reference PNGs, but the shader architecture intentionally follows
the same broad ideas:

- world-space thresholded noise for heterogeneous ground colour;
- dense instanced grass quads;
- world-position-driven variation;
- two moving noise fields for less repetitive wind;
- quantised/stepped animation time;
- fake-perspective UV deformation;
- character-reactive displacement;
- occasional accent foliage.

No Waterfowl branding or logo asset is reused.

## Scene

`res://scenes/labs/DylearnStyleGrassOnlyLab.tscn`

Run the scene with F6. Move the simple test marker with WASD/arrows and hold
Shift to run. The marker is deliberately procedural geometry so this lab does
not depend on Player sprites or AuthoringLab assets.

## Tuning

Most useful controls live on the `GrassField` node:

- spacing/jitter/scale for density and silhouette;
- three grass colours and patch thresholds;
- accent frequency;
- stepped framerate;
- wind direction/strength/noise scale/noise speed;
- fake perspective;
- displacement radius and strength.

The floor's three world-space colours and thresholds are on the `Ground`
ShaderMaterial.

## Next phase

Do not add dirt until this grass-only visual target is approved. Once approved,
a separate procedural dirt system can cut into the grass field while preserving
this renderer as the grass biome's visual layer.
