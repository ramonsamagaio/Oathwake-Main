# Procedural World Visuals

These are the **54 visual PNGs currently wired into the Romestead-derived procedural world pipeline**.
They were moved here without changing image bytes, dimensions, atlas coordinates, or Godot UIDs.

## Editing rule

Redraw pixels inside the existing canvas and atlas slots. Keep each PNG filename, canvas size, slot positions and transparency layout unless the corresponding metadata/code is updated at the same time.

Do **not** manually edit or delete the `.png.import` files. They preserve Godot import settings and asset UIDs.

## Folders

- `terrain/` — biome ground sheets, dense-forest wall/canopy sheets, terrain details and the plains cliff atlas.
- `trees/` — trunks/stumps and tree canopy atlases.
- `rocks/` — large/small rocks, mossy boulder and copper ore.
- `plants/` — bushes, wheat, flowers, mushrooms and tiny ground vegetation.
- `objects/` — standalone procedural-world object art. Currently only the tier-0 brazier; its auto-spawn is disabled in the integrated map.
- `wildlife/` — squirrel, rabbit, female deer and bird animation sheets.

## Current files

### terrain

- `plainsgrass2.png`
- `short_grass.png`
- `plainsgrass3.png`
- `plainsgrass1.png`
- `tall_grass.png`
- `forest_path_short_grass_autumn.png`
- `forest_unbreakable_bushes_bottom_.png`
- `forest_unbreakable_bushes_top_.png`
- `tree_wall.png`
- `canopy_.png`
- `plains_3D_cliffs.png`
- `plainsgrass2_details.png`
- `shortgrass_details.png`
- `plainsgrass3_details.png`

### trees

- `flora_stump.png`
- `flora_tree1.png`
- `flora_tree2.png`
- `flora_olive_tree_large.png`
- `flora_olive_tree_stump.png`
- `flora_skinny_tree.png`
- `flora_tall_cypress.png`
- `flora_apple_tree_large.png`
- `flora_apple_tree_stump.png`
- `flora_stone_pine_large.png`
- `flora_stone_pine_stump.png`

### rocks

- `terrain_round_rocks_big.png`
- `terrain_round_rocks_small.png`
- `poi_mossy_boulder_large.png`
- `resources_copper_ore.png`

### plants

- `flora_big_bushes1.png`
- `flora_small_bush1.png`
- `desert_purplebush.png`
- `flora_ground_plants.png`
- `flora_wheat_animated.png`
- `flora_mushrooms.png`
- `flora_bellflowers.png`
- `flora_lilies.png`
- `flora_tiny_flowers.png`
- `flora_tiny_ground_leaves.png`

### objects

- `tier0_brazier.png`

### wildlife

- `squirrel_squirrel_idle.png`
- `squirrel_squirrel_running.png`
- `squirrel_squirrel_feeding.png`
- `rabbit_rabbit_idle.png`
- `rabbit_rabbit_run.png`
- `deer_deer_female_idle.png`
- `deer_deer_female_walk.png`
- `deer_deer_female_run.png`
- `deer_deer_female_alert.png`
- `deer_deer_female_alert_loop.png`
- `bird_idle.png`
- `bird_hop.png`
- `bird_peck.png`
- `bird_fly.png`

## Migration checks performed

- Exactly 54 PNGs in the manifest, with no duplicate source or destination.
- Every PNG and `.png.import` sidecar existed before the move.
- No destination collision existed.
- SHA-256 and PNG dimensions were identical before and after the move.
- Every Godot UID was preserved.
- Every old direct `res://` reference to these 54 images was removed.
- Every new procedural-world PNG reference resolves to an existing file.
- All JSON files in `data/` still parse.
- Every `sprites.json` region referencing a moved image stays inside its PNG bounds.
- Every moved wildlife animation grid stays inside its PNG bounds.

The separate lighting-cookie SVG remains outside this folder because it is not one of the sprite/atlas PNGs and moving it would add unnecessary risk.
