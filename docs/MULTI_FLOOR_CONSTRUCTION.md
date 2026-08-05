# Multi-floor construction

`MultiFloorBuildManager` virtualizes the existing `BuildSystem` across vertical floors. Every floor now has two independent collections:

- **Surfaces:** walkable floor tiles rendered below constructions.
- **Buildings:** walls, doors, stairs, beds, storage, workstations and other placed objects.

A surface and a building may occupy the same grid cell. Floor tiles no longer consume the building slot.

## Player controls

- `B`: toggle build mode.
- `7`: select Floor Tile.
- `8`: select Stairs Up.
- `Page Up` / `Page Down`: inspect another constructed floor while build mode is active.
- `R`: use nearby stairs while build mode is inactive.
- Left mouse button: place the selected surface or construction.
- Right mouse button: remove the construction first; clicking again removes the floor surface below it.

## Structural rules

- Floor `0` is ground level and does not need player-built floor tiles.
- On upper floors, normal constructions require a floor surface in the same cell.
- The generated stair landing is temporarily walkable even before a floor tile is placed beneath it.
- A new floor tile must connect to stairs, an adjacent floor tile, or structural support below.
- Floor surfaces may spread horizontally from an anchored tile.
- Walls, doors and stair pieces can support a floor directly above them.
- A support or floor surface cannot be removed while something depends on it above.
- Placing `Stairs Up` creates its linked `Stairs Down` endpoint on the next floor.
- The generated lower endpoint is removed by deleting the matching `Stairs Up` piece from the floor below.
- The default maximum is eight floors, indexed from `0` through `7`.

## Placement behavior

Upper-floor construction ignores resources and terrain obstacles that exist on the ground at the same coordinates. Map bounds and current-floor occupancy are still enforced. This prevents a tree or rock on the ground from blocking furniture several floors above.

Only one regular building may occupy a cell, but its floor surface is stored separately. For example, a floor tile may share a cell with a wall, chest, bed or workbench.

## Runtime behavior

Only the current floor's buildings are loaded into the active `BuildLayer`. The active floor's surfaces are rendered in a separate `MultiFloorSurfaces` node below the buildings. Ground resources, NPCs and enemies are disabled above floor `0`, and ground collision is disabled while the player is upstairs.

The manager keeps the player on walkable upper-floor cells and returns them to the last valid position if they attempt to step into empty air.

## Saving and migration

The save payload uses schema version `2` under `multi_floor_buildings`:

- `buildings`: building arrays grouped by floor.
- `surfaces`: floor tile coordinates grouped by floor.
- `current_floor`: the active floor.

Version `1` saves are migrated automatically. Old `floor` construction entries are extracted from the building array and converted into independent surface cells.

Construction changes trigger a synchronized full save so inventory costs, storage metadata, removed resources and all vertical-floor data remain consistent.

## Art placeholders

Floor surfaces currently use a simple runtime polygon. `stairs_up` and `stairs_down` still use the generic building scene. Final Oathwake sprites or tiles can replace these visuals later without changing the data model.
