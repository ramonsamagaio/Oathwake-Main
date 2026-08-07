# Alabaster demo source-runtime findings

This note records the high-confidence behavior recovered from the supplied demo `bundle.js`, Juno figure data, tutorial figures and billboard shaders. It supersedes the earlier inference-based V2 diagnosis.

## Important correction to V2

`globalRot` is parsed into `FigureNode.globalRot`, but the supplied demo bundle does not use that field in the figure-state transform or billboard-render path. V2 invented special parent-rotation behavior for it, which was incorrect and explains the head regression because Juno's head is marked `globalRot:true`.

The source-derived runtime does not special-case `globalRot`.

## Node transform semantics

- `node.dir` builds a `rootDir` used for yaw/pitch and sprite-facing selection.
- `node.dir` is not multiplied into the node's positional bone transform.
- Animation rotations are quaternions. Child animated orientation is composed with the animated parent orientation.
- Quaternion animation uses SLERP, not Euler component interpolation.
- The spline for an interpolation segment comes from the next key.
- Node translation is transformed by the animated parent orientation.
- Figure-space quaternion transforms temporarily scale Z by `1 / 1.325`, rotate, then scale Z by `1.325`.
- Per-node scale is local to that node's authored position and is not multiplied into a cumulative parent scale value.

## World and pixel metrics

The demo uses `TILE_W=24` and `TILE_H=16`. Figure world positions are snapped with half-pixel precision independently on X/Y/Z:

- X: `round(x * 24 * 2) / (24 * 2)`
- Y/Z: `round(value * 16 * 2) / (16 * 2)`

This is different from the original lab's blanket `16 px/unit` assumption.

`halfPixelShift` is additionally used in billboard-pivot calculations. It is not a substitute for world-position snapping.

## Facing convention

The source heading convention is:

- North = 0 degrees
- East = 90 degrees
- South/front = 180 degrees
- West = 270 degrees

Juno uses `rootFacing: FACE_16`. Root facing is quantized in 22.5-degree increments and the figure root rotation is `roundFaceAngle - 180 degrees`.

Sprite facing is not generic equal-sector indexing. The runtime contains authored lookup tables for `FACE_4`, `FACE_8`, `FACE_16`, mirrored and front-only modes. The source-derived runtime uses those tables.

## Pitch rows

Pitch is extracted from the node orientation quaternion and mapped through the demo's exact pitch slots:

`[-105, -75, -45, -15, 15, 45, 75, 105, 135, 165, 195]`

Rows such as `DOWN2+`, `DOWN1+`, `NORM`, `UP1+`, etc. are compiled into pitch-slot ranges. If two rows overlap, the narrower pitch range wins.

Rows with empty `frameKeys` are authored as frame key `0`. When a requested frame key is absent and `onMissingFrame=USE_DEFAULT`, frame key `0` is used.

## Atlas addressing

The exact directional tile comes from the facing lookup table. `extendX` changes atlas layout:

- normal: X advances by facing tile, Y advances by row;
- `extendX`: X advances by row, Y advances by facing tile.

The earlier lab did not implement this exactly.

## Juno head

Juno's main head entry uses `FACE_16_MIRR` and `rotDefOff:true`. In the original runtime, `rotDefOff` causes billboard rotation to be skipped by default. An animation `rotToggle` can invert that choice.

This is a direct explanation for the V2 head regression: V2 continuously rotated the head and also applied an invented `globalRot` transform rule.

## Texture rotation flags

The demo encodes texture rotation as bit flags:

- `ROTATE = 1`
- `ROTATE_CUT = 3`
- `ROTATE_SCALE = 5`
- `PARENT_ROTATE = 9`
- `PARENT_ROTATE_CUT = 11`
- `PARENT_ROTATE_SCALE = 13`

The `PARENT_*` family uses the inverse/other end of the node connection for the billboard transform. It is not simply a request to read the parent's Euler angle.

## CUT / SCALE

The original renderer uses a two-point billboard path in `billboard.vert`. The second world-space point is stored in the instance transform. The shader compares the projected real connection with the untransformed reference connection, computes a view rotation, and can crop the texture when the connection becomes shorter.

The current Godot lab uses the demo's own CPU fallback equations for `CUT`/`SCALE` as an approximation while keeping the test on simple `Sprite2D` pieces. A later fidelity pass can replace affected pieces with four-point geometry reproducing the supplied billboard shader exactly.

## Tutorial files

The supplied tutorial assets are especially useful as renderer unit tests:

- `bone-tutorial.json`: isolated parent-rotate, scale and cut cases;
- `chara-tutorial.json`: minimal humanoid assembly;
- `chara-test.json`: humanoid CUT/ROTATE examples;
- `anim-test.json`: isolated `ROTATE_CUT` and `PARENT_ROTATE_CUT` hand/bone tests;
- `anim-test2.json`: frame-key and pitch-row behavior.

These should be used for future renderer validation before changing Juno-specific data.
