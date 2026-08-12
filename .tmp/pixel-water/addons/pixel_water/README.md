# Pixel Water Simulator for Godot 4.x

Lightweight side-view pixel water with buoyancy, displacement, overflow, waterfalls, buckets, foam and shallow-water flow.

## QUICK INSTALL INTO AN EXISTING GAME

### 1. Copy the addon

Copy this whole folder into your project:

`addons/pixel_water/`

Do not separate the files inside it.

### 2. Add the water world to your level

Drag this scene into your gameplay level:

`addons/pixel_water/pixel_water_world.tscn`

The reusable runtime node is `PixelWaterWorld2D`.

For the fastest setup, copy `_configure_water_world()` from `demo/main.gd` into your level script and change the floor / water coordinates to match your level. The demo is only a reference; it is not required in your final game.

---

# MAKE AN EXISTING OBJECT / PLATFORM FLOAT

Your object can keep its own `RigidBody2D`, script, sprites and collision.

Just drag this scene as a CHILD of the existing `RigidBody2D`:

`addons/pixel_water/water_buoyancy_2d.tscn`

Example:

```text
FloatingPlatform (RigidBody2D)   <- your existing object/script
├── Sprite2D
├── CollisionShape2D
└── WaterBuoyancy2D              <- add this
```

That's it.

`WaterBuoyancy2D` automatically reads the parent's collision shape and mass, then adds buoyancy, drag, water displacement, surface stability and shallow-water pushing without replacing the object's script.

- Lower mass / larger volume = floats higher
- Higher mass / smaller volume = sinks lower
- The component works with the object's existing collisions and gameplay code
- If the collision changes at runtime, call `WaterBuoyancy2D.refresh_geometry()`

Example scene:

`examples/floating_platform_example.tscn`

Do NOT add `WaterBuoyancy2D` to an object that already inherits `BuoyantPixelBody2D`; the original demo bodies already contain their own buoyancy implementation.

---

# MAKE AN EXISTING CHARACTER SWIM

Your player can keep its existing `CharacterBody2D` controller.

Drag this scene as a CHILD of the player:

`addons/pixel_water/water_swimmer_2d.tscn`

Example:

```text
Player (CharacterBody2D)         <- your existing player/script
├── Sprite2D
├── CollisionShape2D
└── WaterSwimmer2D               <- add this
```

Then add ONE line to the player's existing `_physics_process()` after normal movement / gravity code and immediately before `move_and_slide()`:

```gdscript
velocity = $WaterSwimmer2D.apply_water_motion(velocity, delta)
move_and_slide()
```

That's the complete swimming integration.

The component automatically detects the water surface and character collision, slows movement underwater, adds buoyancy, supports swim-up / swim-down input, displaces water and exposes water state signals.

Default swim controls use:

- `ui_accept` = swim up
- `ui_down` = swim down

You can change both actions in the Inspector.

If your controller already handles its own swimming input, use:

```gdscript
velocity = $WaterSwimmer2D.apply_water_motion_with_axis(
    velocity,
    delta,
    vertical_swim_axis
)
```

Where `-1` is up and `+1` is down.

Example player:

`examples/swimmer_player_example.tscn`

---

# USE WATER STATE IN GAMEPLAY

`WaterSwimmer2D` exposes:

```gdscript
$WaterSwimmer2D.is_in_water()
$WaterSwimmer2D.get_submersion()
$WaterSwimmer2D.get_surface_y()
$WaterSwimmer2D.is_head_underwater()
```

Signals:

- `entered_water`
- `exited_water`
- `head_submerged`
- `head_emerged`
- `submersion_changed`

Useful for swimming animations, breath meters, sound, underwater VFX, damage zones, etc.

---

# OPTIONAL WATER APIs

The water world also exposes:

- `surface_y_at(x)`
- `floor_y_at(x)`
- `depth_m_at(x)`
- `contains_point(point)`
- `water_volume_liters()`
- `extract_water_at(...)`
- `deposit_water_at(...)`
- `emit_water_stream(...)`

These are useful for pumps, pipes, rain, spells, drains and custom containers.

---

# FILES YOU ACTUALLY NEED

For your game, copy only:

`addons/pixel_water/`

The `demo/` and `examples/` folders are references and can be deleted from your final project.

## Fastest possible workflow

1. Copy `addons/pixel_water/`
2. Add `pixel_water_world.tscn` to your level
3. Copy the demo water configuration and change the coordinates
4. Add `WaterBuoyancy2D` under any `RigidBody2D` that should float
5. Add `WaterSwimmer2D` under the player + one line before `move_and_slide()`

No solver code needs to be edited.
