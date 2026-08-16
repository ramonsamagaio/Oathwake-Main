# BoneLab Retarget Debug V8

## Purpose

The retarget path is now explicitly **Mixamo-compatible 3D skeleton → Juno / BASESKIN semantics**.

`BASESKIN` remains the frozen Juno snapshot. Juno remains the live runtime target.

V8 keeps the strongest part of the old V7 implementation: it samples imported 3D transform tracks directly and composes them through the real `Skeleton3D` parent + REST hierarchy before any target conversion. It then solves motion in global anatomical space and projects that result into Juno's effective hierarchy.

## Why V8 exists

The old full-quality path was authored as `Mixamo → Default/Dummy`. Its target hierarchy assumed `shoulderL/R` and `hipL/R` attachment pivots as animated intermediary nodes.

Bone Studio, gameplay and the canonical target are Juno.

V8 removes that mismatch:

```text
SOURCE
Mixamo / Cascadeur-on-Mixamo / Rokoko-exported-as-Mixamo
        |
        v
actual Skeleton3D REST + animated 3D tracks
        |
        v
global anatomical REST -> POSE delta
        |
        v
Juno semantic solve
        |
        +-- root     = orientation locked; gameplay facing stays authoritative
        +-- bottom   = pelvis/body-lower orientation
        +-- top      = torso orientation
        +-- head     = head global delta relative to effective target parent
        +-- arms     = Juno arm -> hand -> finger
        +-- legs     = Juno leg -> foot -> toe
        |
        v
Juno / BASESKIN nodeXfm
```

Shoulder and hip attachment pivots are left at their authored Juno REST transform by default.

## Two limb solvers

The RETARGET DEBUG tab can A/B the two transfer modes without changing the source file.

### V8 Full global delta

Default.

Uses the full global REST→POSE orientation delta of the source limb joint, then converts it into Juno's target hierarchy.

Advantages:

- preserves swing;
- preserves orientation around the limb axis (twist/roll);
- does not copy the source character's absolute T/A pose;
- is independent of Mixamo's local bone-axis naming.

### V7 Segment swing

Fallback / comparison mode.

Uses only the direction from one source joint to the next.

Advantages:

- very robust to unusual bone roll;
- useful to prove whether a problem comes from twist/orientation or from the basic limb swing.

Limitation:

- intentionally discards twist around the segment axis.

If Full Global Delta looks wrong but Segment Swing looks correct, the debug report's `EXTRA ORIENTATION/TWIST` column becomes the first suspect.

## Root policy

Juno's facing is controlled independently by the Oathwake runtime. V8 therefore does **not** put imported pelvis rotation on Juno's `root`.

Instead:

```text
Mixamo pelvis orientation -> Juno bottom
Mixamo torso orientation  -> Juno top
Juno root rotation        -> neutral
```

Optional root translation remains available through `Root translation scale`.

This prevents a mocap/Mixamo hip yaw from fighting the game's top-down facing system.

## RETARGET DEBUG tab

The tab is designed to be readable in a screen recording.

### RUN DEEP AUDIT

Checks:

- raw/imported resource kind;
- `AnimationPlayer` availability;
- `Skeleton3D` availability;
- source bone count;
- source root bones;
- normalized duplicate bone names;
- required and optional Mixamo bones;
- rotation / position / scale track counts;
- duplicate semantic tracks;
- REST parent hierarchy;
- non-uniform REST scale;
- reflected / negative-determinant REST bases;
- nearly zero-length REST segments;
- raw source rotational motion span;
- maximum one-frame source rotation jump;
- Hips translation span;
- animated source scale;
- actual Juno target nodes;
- actual Juno parent map;
- target hierarchy cycles;
- attachment pivots skipped by V8;
- source limb swing;
- orientation/twist beyond segment swing;
- final Juno motion span;
- maximum one-frame Juno rotation jump;
- frame where a discontinuity happens;
- root translation;
- source motion that disappears during retarget.

### Frame microscope

For every sampled frame it shows, per Juno target:

```text
source segment swing
extra source orientation / twist
output yaw
output pitch
output roll
effective Juno parent used by V8
```

This is the most useful view when a single pose explodes or a specific joint behaves incorrectly.

### Source Skeleton3D hierarchy

Displays every source bone and its actual parent as Godot sees it.

This catches cases where a file looks like Mixamo by name but was reparented or altered by an exporter.

### Juno target structure

Displays the target directly from a hidden canonical `BonesSystem` Juno instance. It does not depend on which alternate skin is being viewed in Live Tuning.

### Juno Axis Probe

Creates a runtime-only synthetic animation for one Juno target bone:

```text
REST
YAW +45
YAW -45
PITCH +45
PITCH -45
ROLL +45
ROLL -45
REST
```

No FBX is involved.

If the target already behaves incorrectly in Axis Probe, the source file is not the problem. We then inspect Juno axis semantics, sprite pitch selection, parent inheritance or rendering.

If Axis Probe is correct and the retarget is wrong, the fault is upstream in source REST/hierarchy, anatomical solve, mapping or coordinate conversion.

## Recommended recording workflow

For a useful diagnostic recording:

1. Open `Import_Retarget`.
2. Select the raw FBX/GLB and the problematic clip.
3. Open `RETARGET DEBUG`.
4. Run `RUN DEEP AUDIT`.
5. Keep the STATUS and Problems section visible for a few seconds.
6. Show `Motion transfer`.
7. Move the `Frame microscope` to a visibly broken frame.
8. Preview the animation.
9. If one limb is suspicious, run Axis Probe on that Juno bone.
10. If useful, switch `Limb solve` between Full Global Delta and Segment Swing and preview both.

The report can also be copied to the clipboard or saved as:

```text
user://bonelab_retarget_debug_report.txt
user://bonelab_retarget_debug_report.json
```

The JSON is intended to let the retarget be diagnosed without relying only on visual judgement.
