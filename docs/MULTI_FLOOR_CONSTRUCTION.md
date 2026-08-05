# Multi-floor construction

The existing `BuildSystem` remains the placement authority. `MultiFloorBuildManager` stores an independent building list for each vertical floor and swaps the active list into the current map's `BuildLayer`.

## Player controls

- `B`: toggle build mode.
- `7`: select Floor Tile.
- `8`: select Stairs Up.
- `Page Up` / `Page Down`: inspect another constructed floor while build mode is active.
- `R`: use nearby stairs while build mode is inactive.
- Left mouse button: place the selected construction.
- Right mouse button: remove the construction under the cursor.

## Structural rules

- Floor `0` is ground level.
- A construction on floor `1` or higher requires structural support in the same grid cell on the floor below.
- Floor tiles, walls, doors and stair pieces count as structural support.
- A support piece cannot be removed while a construction depends on it above.
- Placing `Stairs Up` automatically creates its linked `Stairs Down` endpoint on the next floor.
- The generated lower endpoint must be removed from the floor below by removing its matching `Stairs Up` piece.
- The default maximum is eight floors, indexed from `0` through `7`.

## Runtime behavior

Only the current floor's player-built constructions are loaded into the active `BuildLayer`. Ground resources, NPCs and enemies are disabled above floor `0`, and ground collision is disabled while the player is upstairs. The manager prevents the player from crossing cells that do not have structural support below.

## Saving

The floor graph is stored under `multi_floor_buildings` in the active slot. Construction changes trigger a synchronized complete game save so inventory costs, removed resources, storage metadata and all floor data remain consistent.

## Art placeholders

`floor`, `stairs_up` and `stairs_down` currently use the generic building scene and fallback visuals. Final Oathwake sprites can be assigned later through `data/buildings.json` without changing the floor system.
