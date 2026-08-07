# ALABASTER_BRANCH character-rig lab

This branch is an isolated Godot 4.6 experiment reconstructed from the supplied `juno.png`, `juno.json`, `juno-rd.json`, and `bob.json`. It does not replace the Oathwake player or change `project.godot`.

## What the supplied files establish

The character is not a normal frame-by-frame sprite animation. The figure data describes a hierarchical rig whose nodes carry 3D-style position/rotation transforms while small pixel-art billboards are selected, mirrored, rotated, scaled, and layered over those nodes.

The source contains:

- a parent hierarchy for root, torso, head, shoulders, arms, hands, fingers, hips, legs, feet, toes and attachments;
- sparse animation transforms (`rot` / `trans`) for `idle`, `walk`, `run` and many other actions;
- `FACE_16`, `FACE_8`, `FACE_4`, mirrored, flipped and front-only sprite-selection modes;
- per-piece source rectangles, pivots and `zOrder`;
- `refAngles` tables and texture modes such as `ROTATE`, `PARENT_ROTATE`, `PARENT_ROTATE_SCALE`, `PARENT_ROTATE_CUT`, and `ROTATE_SCALE`;
- `halfPixelShift`, parent-pixel offsets, IK metadata and node alignment metadata.

`bob.json` uses the same general structure with a different humanoid, which is strong evidence that this is a reusable figure/rig system rather than a Juno-only format.

## Godot prototype

Open and run:

`res://scenes/labs/alabaster/AlabasterMechanicLab.tscn`

Controls:

- WASD: move and set facing;
- Shift + WASD: run;
- F1: show the reconstructed node hierarchy.

The lab keeps the source convention of X/Y as the ground plane and Z as height. It evaluates the hierarchy with `Transform3D` / `Basis`, projects the result into the 2D top-down view, then chooses the appropriate atlas cells with nearest-neighbor filtering. The supplied Juno sheet is embedded losslessly as a palette PNG payload in four text parts so the branch is self-contained.

The source subset used at runtime preserves the full node/GFX definitions plus the exact supplied `idle`, `walk`, and `run` key blocks. It is stored as gzip+base64 at:

`res://data/labs/alabaster/juno_runtime.json.gz.b64`

## Important fidelity boundary

Everything that is numerically described by the supplied files is carried into the prototype: hierarchy, transforms, atlas rectangles, pivots, facing modes, reference angles, draw-order values, half-pixel behavior and the idle/walk/run source keys.

Some renderer operations are named but their actual implementation is not present in the files. The clearest example is the precise clipping algorithm behind the `*_CUT` texture modes. The prototype therefore keeps those flags and approximates the visible behavior instead of inventing a fake undocumented algorithm. Pixel-identical parity needs visual comparison in a running Godot build and small renderer tuning after that comparison.

## Validation

A headless structural validator is included at:

`res://scripts/test/AlabasterMechanicValidator.gd`

Run with Godot 4.6.x:

```bash
godot --headless --path . --script res://scripts/test/AlabasterMechanicValidator.gd
```

Expected success marker:

`ALABASTER_MECHANIC_VALIDATION_OK`

## Sprite map

See `res://docs/alabaster/JUNO_SPRITE_MAP.md`. It records the body-piece rectangles and the rig hierarchy used by the lab. That document is the source of truth for the later annotated sprite-sheet image for building the Oathwake base character.
