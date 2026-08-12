# Pixel Water Simulator

Lightweight, physically-inspired 2D pixel water for Godot 4.x.

This package is designed for side-view games that want expressive water without a full fluid solver. The core is intentionally separated from the demo so it can be copied into another project.

## Recommended integration

Copy:

`addons/pixel_water/`

Then instance:

`pixel_water_container.tscn`

`PixelWaterContainer2D` represents one contiguous water basin. Use multiple instances for separate pools.

Configure the container to match your level collision:

- `basin_left` / `basin_right`
- `rest_surface_y`
- `bottom_y`
- `platform_y`
- optional `left_rim_y` / `right_rim_y`
- `fluid_depth_m`
- outside spill bounds

The water node simulates liquid only. Your game should provide real `StaticBody2D` / tile collision for the basin walls, floor and surrounding terrain.

## Buoyant objects

Attach or extend `BuoyantPixelBody2D` for physics-driven objects.

The body uses:

- Archimedes buoyancy from sampled submerged volume
- quadratic hydrodynamic drag
- local buoyancy forces, so partially submerged objects can rotate naturally
- material density presets
- displacement-driven waves
- splash energy from impact mass and speed
- underwater wakes, foam and bubbles

For the included mouse sandbox behavior, use `InteractiveBuoyantPixelBody2D`.

The interactive version never teleports a held body. A spring-damper force pulls the clicked point toward the cursor while the object stays a normal `RigidBody2D`, so terrain and object collisions remain active during the grab.

Useful grab tuning:

- `grab_stiffness`
- `grab_damping`
- `max_grab_acceleration_px_s2`
- `max_held_speed_px_s`

## Water surface model

The free surface is a conservative 1D height field. Waves use a damped discrete wave equation with:

- solid-wall reflection
- adaptive damping for extreme motion
- nonlinear restoring pressure
- explicit volume correction
- a physical dry-floor limit only

There is no symmetric hard amplitude clamp above and below the resting surface.

## Overflow

Overflow is volume-based.

When the water surface rises above a rim, outflow is based on a Torricelli-inspired relation:

`Q = Cd * A * sqrt(2 g h)`

where:

- `Cd` is the discharge coefficient
- `A` is the effective opening area
- `g` is gravity
- `h` is water head above the rim

Small overfill produces a trickle. Large head produces substantially more flow.

Overflow volume is removed from the basin and divided between:

- a shallow outside puddle sheet
- sparse visual spray

Water that later falls back into the basin is returned to its tracked volume.

## Outside puddles and wetness

Spilled water is not only a decal. The simulator keeps a sparse 1D shallow-puddle volume map outside the basin.

Puddles:

- spread laterally
- use conservative neighbor transfers
- can drain back into an open basin edge
- evaporate gradually
- leave temporary wet pixels behind

This keeps outside water cheap while making large spills visibly different from a few splash particles.

## Pixel rendering

The physics runs in floating point. Quantization happens when drawing, so the solver does not lose precision while the result still reads as small pixel art.

Main effects:

- pixel water surface
- crest highlights
- foam
- bubbles
- spray droplets
- shallow puddles
- wet ground

## Demo controls

- Left mouse + drag: physically grab an object
- Release: throw with the real current rigid-body velocity
- Right mouse + drag: pan the camera
- Maximize/resize the window freely
- Reset Objects: restores demo objects
- Reset Water: restores basin volume and clears spill state

## Scope

This is a lightweight gameplay fluid, not CFD/Navier-Stokes. It prioritizes conservation, convincing response, integration simplicity and low cost for pixel-art games.
