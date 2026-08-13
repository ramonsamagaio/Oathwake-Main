# Oathwake Procedural Creature System

## Purpose

This system is a pixel-native procedural animation layer for monsters that reduces sprite-sheet authoring while preserving Oathwake's authored visual identity. It is intentionally not a full rigid-body simulation. The runtime uses cheap deterministic math, quantized motion, reusable archetypes, and distance-based update throttling.

The lab scene is:

`res://scenes/labs/ProceduralCreatureLab.tscn`

Run that scene directly in Godot to author and stress-test creatures.

## The four reference archetypes

### 1. Slime — Blob Spring

A deformable ring driven by spring/damping behavior, squash/stretch, impact response, wobble, and approximate volume preservation. It is the template for slime, goo, magma blobs, spores, jelly monsters, living puddles and soft bosses.

### 2. Snake — Segment Chain

A constrained follow-chain with travelling body wave and tapered procedural rendering. It is the template for snakes, worms, tails, tentacles, vines, eels, centipede bodies and dragon tails.

### 3. Wisp — Field + Trail

A floating core with elastic trail, layered glow pixels and orbiting motes. It is the template for ghosts, wisps, cursed flames, elemental spirits, floating eyes with trails and magic summons.

### 4. Crawler — Radial IK

A central body with analytically solved two-bone legs and procedural gait phase. It is the template for spiders, crabs, insects, mechanical crawlers, root creatures and multi-legged bosses.

## Runtime contract

Every procedural monster inherits `ProceduralCreature`.

Common API:

- `apply_impulse(Vector2)` — hit/recoil/environment response.
- `add_force(Vector2)` — continuous force.
- `set_parameter(StringName, Variant)` — data-driven authoring.
- `get_parameter(StringName)` — tooling/serialization.
- `get_editor_schema()` — automatically builds the lab controls.
- `make_preset()` / `apply_preset(Dictionary)` — save/load creature tuning.
- `reseed(int)` — deterministic variation.
- `set_lod_anchor(Node2D)` — selects the point used for simulation throttling.
- `set_simulation_active(bool)` — pooling/offscreen support.

## Performance strategy

The system intentionally avoids per-limb rigid bodies and physics joints. Creature math is local and low-dimensional. The base class supports full-rate, reduced-rate and far-rate simulation according to distance from a camera or explicit LOD anchor.

For production use:

1. Pool procedural enemies instead of repeatedly creating/freeing them.
2. Keep collision simple and independent from visual deformation.
3. Never regenerate collision polygons every frame for slimes or chains.
4. Use one coarse gameplay collision shape plus optional attack/hurt sensors.
5. Disable secondary motion when enemies are dormant or outside AI relevance.
6. For crowds, update decision-making more slowly than visual procedural motion.
7. Keep procedural rendering pixel-quantized so post-processing cannot create subpixel shimmer.

## Art pipeline

The procedural layer does not replace art direction. Production monsters can swap the debug procedural drawing for authored sprite pieces attached to the same mathematical anchors.

Recommended pipeline:

`Monster definition -> archetype solver -> anchors/bones -> authored sprite parts -> palette/material variant -> combat hitboxes`

This lets one monster family share motion while preserving unique silhouettes.

## Lab controls

The lab provides:

- creature archetype switching
- live parameter sliders
- deterministic seed/reseed
- random tuning generation
- pause/reset
- directional hit/pop impulses
- palette editing
- persistent preset save/load at `user://procedural_creature_presets.json`
- JSON clipboard export
- 10/25/50/100/200 creature stress spawning
- distance LOD toggle
- FPS/instance status
- direct stage interaction: left click pushes, right click pulls, wheel scales

## Production integration rules

The procedural visual should not own enemy gameplay state. AI, navigation, health, damage and drops remain independent components. The creature renderer receives movement velocity, impulses, facing and state events.

Suggested event bridge:

- movement velocity -> gait/wave/squash
- attack windup -> procedural anticipation
- damage -> impulse + local secondary motion
- stun -> reduced motion / altered spring
- death -> one-shot collapse profile, then pool/despawn
- status effects -> palette/secondary emitters, not solver mutation unless desired

## Planned extension points already anticipated

The architecture is ready to add:

- sprite-part sockets and bones
- 4/8 direction sprite selection
- equipment/accessory sockets
- per-creature JSON definitions
- seeded silhouette variation
- terrain contact probes for feet/tentacles
- attack pose layers over procedural idle motion
- network-safe deterministic presets
- pooled runtime instances
- editor plugin wrapper around the lab schema
- baking procedural motion into sprite-sheet frames for zero-runtime-cost variants

The key design choice is hybrid: authored pixels define identity, procedural solvers define motion, and gameplay components remain decoupled.
