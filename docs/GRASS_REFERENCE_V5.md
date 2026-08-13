# Grass Only V5 reference target

This lab pass targets the third visual reference supplied on 2026-08-13.

## Palette lock

The grass/ground renderer is intentionally restricted to four green tones sampled from the reference image. No multiplicative tint, smooth toon factor, alpha blending, or per-instance colour variation is allowed to create intermediate greens.

- shadow: RGB 71, 93, 30 (`#475D1E`)
- dark/mid: RGB 131, 164, 54 (`#83A436`)
- mid/light: RGB 166, 191, 75 (`#A6BF4B`)
- highlight/base: RGB 195, 211, 91 (`#C3D35B`)

## Pixel-language rules

- one source atlas pixel maps to one world pixel at scale 1
- no random sprite scaling
- no random rotation
- integer placement jitter only
- grass blades remain at least 2 pixels wide, commonly 3 pixels wide
- wind/displacement vertex offsets are quantized to whole pixels
- texture filtering remains nearest

## Families

The single runtime atlas now includes twelve 40x28 silhouettes:

- 0-5: low overlapping carpet clumps
- 6-8: low broad leaf/rosette patches
- 9-10: taller grass groups
- 11: rare tall weed with side leaves

Every family includes a low carpet base so replacements never punch holes through the continuous grass mass.

## Colour fusion

The floor and grass use the same world-space noise field and the same four-colour palette. Some low carpet variants use the exact floor palette index while others are one step darker. Taller grass is one or two palette steps darker. Overlap therefore creates shape and depth without generating extra colours.

## Motion hierarchy

- low carpet: restrained wind
- ground leaves: almost static
- tall grass: full gust response
- tall weed: strongest response

The coherent two-noise travelling gust system and the shared stepped clock remain, but the resulting vertex displacement is snapped to integer pixels.
