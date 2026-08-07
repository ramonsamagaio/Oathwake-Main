# Alabaster lab movement diagnosis — 2026-08-06

Input reviewed: 13.9 s / 417 frames / 30 fps capture of the Godot lab, with walk and run tested around the cardinal directions.

## What the capture proves

1. Atlas decoding is valid. The head is coherent, directional and stable, so the embedded 672×240 PNG and the broad FACE_16 selection convention are working.
2. Animation playback is active. The deformation repeats with walk/run phase instead of appearing as random corruption, which means source transforms are being sampled.
3. The remaining defects are renderer/rig interpretation defects, not movement input defects.

## Defects visible in the capture

- chained extremities change apparent length and attachment under rotation;
- a long tail/hair segment can project far sideways, most obvious around the north-facing run;
- arm/hand/foot pieces occasionally use a shape/orientation inconsistent with the current 3D pose;
- depth/layer changes are not always consistent with the apparent front/back side of the body;
- the head remains substantially more stable than the chained limbs.

## Root causes found in V1

### 1. `globalRot` was ignored

Juno marks `head`, `armL`, `armR`, and `tailEnd` as `globalRot:true`.

The strongest structural evidence is the comparison with the supplied Bob rig:

- Juno shoulder L has `dir=[-90,0,0]` and global arm L has `dir=[-90,-74,0]`;
- Bob shoulder L has `dir=[-90,0,0]` while its non-global arm L uses `dir=[0,-74,0]`.

Therefore applying the parent shoulder basis and then applying Juno's full arm basis applies the shoulder component twice. V1 did exactly that. V2 keeps the attachment origin parented but evaluates a `globalRot` node basis in actor/global orientation.

### 2. Texture row zero was selected blindly

The files store multiple rows for the same atlas range, controlled by `pitchRange`. For many limbs row zero is not the generic row. Examples include arm and hand definitions whose first row is `DOWN2+`, followed later by `ALL`/`NORM` rows.

V1 selected the first row with no frame key, which means it could literally address the wrong Y region of the sprite sheet even when the correct X/direction was known.

V2 derives an elevation/pitch estimate from the 3D node basis, matches the named pitch bands, and keeps `ALL` as the authored safe fallback.

### 3. Animation node frame IDs were ignored

Animations contain per-node frame streams under `anims.<animation>.nodes`. These select the node's authored frame-key states. `tailEnd` is the clearest case: its node exposes named states such as `wave1..4`, `subtle1..4`, and swing states, while texture entries attach numeric `frameKeys` to those rows.

V1 did not read this stream, so walk/run could continue rendering the idle tail strip. V2 resolves the active node frame ID and searches the matching entry/row before falling back.

### 4. Animated node scale was discarded

Several source animation transforms include `scale`. V1 only sampled `rot` and `trans`, so articulated limb length/projection could not match the authored pose. V2 samples and interpolates uniform node scale into the basis.

## Intentionally not guessed yet

- the exact engine algorithm behind `*_CUT`;
- exact numeric thresholds used by the original engine for `pitchRange` bands;
- the complete meaning of animation-time `rotToggle` and temporary `parent` fields;
- whether every rendering difference between `juno.json` and `juno-rd.json` is preprocessing or a separate revision.

The V2 pitch thresholds use 22.5° half-sector boundaries because that matches the figure's facing quantization and gives deterministic behavior. This remains a reconstruction choice until direct runtime parity establishes the original thresholds.

## V2 test objective

Record the same movement sweep again after commit `785c6388173f5f1548719e5ae1ba484abd84b018` or later. Compare especially:

- north-facing run tail placement;
- west/east arm attachment;
- foot attachment during the high-stride run phases;
- front/back draw ordering when changing 90° → 180° → 270°;
- whether the head remains as stable as in V1.
