# Pixel Water Simulator

Lightweight, physically-inspired pixel water for Godot 4.x side-view games.

## What changed in the unified solver

The water is now one continuous simulation domain. Deep basins, shallow water on platforms, overflow, and secondary pits are all horizontal cells in the same shallow-water world. There is no separate puddle implementation and no special invisible barrier at basin edges.

The core tracks water depth and horizontal momentum with a conservative finite-volume shallow-water approximation, hydrostatic reconstruction across terrain steps, CFL sub-stepping, wet/dry cells, bottom/turbulent friction, transported spray, object displacement, buoyancy, wakes, foam, and bubbles.

Gravity is part of the pressure-wave dynamics. Wave energy is dissipated by bottom/turbulent friction rather than by forcing the surface back to an arbitrary rest line.

## Install

Copy:

`addons/pixel_water/`

Instance:

`pixel_water_world.tscn`

The main runtime class is:

`PixelWaterWorld2D`

Older names `PixelWaterContainer2D`, `PixelWaterSimulator2D`, and `PixelWaterSimulatorV2` remain as compatibility aliases.

## Terrain and initial water

Configure a world with floor segments and initial water regions:

```gdscript
water.configure_world(
    [
        {"left": 170.0, "right": 790.0, "floor_y": 500.0},
        {"left": 970.0, "right": 1120.0, "floor_y": 430.0}
    ],
    [
        {"left": 170.0, "right": 790.0, "surface_y": 275.0},
        {"left": 970.0, "right": 1120.0, "surface_y": 405.0}
    ]
)
```

Every x-position not covered by a floor segment uses `default_floor_y`.

A tall floor step behaves as a physical rim because of the terrain elevation itself. If the free surface rises above the rim, the same solver carries water over it. Once outside, that water continues obeying the same depth/momentum equations and can flow into another lower region.

Your game should still provide matching `StaticBody2D`, TileMap, or other collision geometry for solid terrain so rigid bodies cannot overlap walls/floors.

## Water conservation APIs

Useful runtime methods:

- `water_volume_liters()`
- `volume_liters_in_range(left_x, right_x)`
- `surface_y_at(x)`
- `floor_y_at(x)`
- `depth_m_at(x)`
- `contains_point(point)`
- `extract_water_at(x, volume_m3, radius_px)`
- `deposit_water_at(x, volume_m3, incoming_horizontal_velocity_m_s, radius_px)`
- `emit_water_stream(point, volume_m3, velocity_px_s, particle_count)`

`extract_water_at` and `deposit_water_at` are intended for pumps, buckets, pipes, spells, drains, faucets, rain systems, and similar gameplay systems while preserving tracked water volume.

## Buoyant bodies

`BuoyantPixelBody2D` uses sampled Archimedes buoyancy, quadratic hydrodynamic drag, local torque, material density, object displacement, splash energy, wakes, foam, and bubbles.

Object displacement is reported to the water world as occupied volume. Multiple submerged objects therefore reduce available storage simultaneously and raise/redistribute the water naturally. RigidBody2D collision keeps the objects themselves from occupying the same physical space.

Use `InteractiveBuoyantPixelBody2D` for the included physical mouse grab. It remains a normal RigidBody2D while held and is pulled toward the cursor with a spring-damper force.

## Transparent bucket

`WaterBucket2D` is an open-topped U-shaped RigidBody2D with visible contained water.

When its opening goes below the outside free surface, it equalizes toward the surrounding water level and removes that volume from the world. The water mass increases the bucket's total mass.

When tilted past the lip angle, the bucket emits conservative transported water parcels. Those parcels fall under gravity and rejoin the same world solver wherever they land, including another basin or a shallow platform.

## Demo

The demo contains:

- a large main basin
- a smaller secondary basin with less initial water
- a transparent 16 L transfer bucket
- the original material test objects
- spawn controls for creating additional copies of every object/bucket
- live volume readouts for the main basin, small basin, bucket contents, and world water
- physical object grabbing
- right-mouse camera panning

Repeated bucket transfers visibly lower one basin and raise the other. Spawning and submerging many rigid bodies also occupies volume and raises the water.

## Why shallow water instead of full CFD

This asset targets pixel-art gameplay and solo-dev budgets. It does not solve full 3D Navier-Stokes. The core uses a conservative 1D shallow-water approximation across a side-view terrain profile, which captures gravity-driven free-surface flow, wetting/drying, basin transfer, overflow, wave propagation, and momentum at a fraction of the cost of general fluid simulation.
