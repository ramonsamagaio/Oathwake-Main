"""Build Photoshop-friendly atlases from lossless Romestead XNB extractions.

Every source sheet is copied byte-for-byte. Combined atlases only arrange the
native images on transparent canvases; no source is resized or filtered.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image


FLOOR_SOURCES = [
    "autotiles/grass/plainsgrass1.png",
    "autotiles/grass/plainsgrass2.png",
    "autotiles/grass/plainsgrass3.png",
    "autotiles/grass/plainsgrass_tall.png",
    "autotiles/grass/short_grass.png",
    "autotiles/shortgrass_details.png",
    "autotiles/plainsgrass1_details.png",
    "autotiles/plainsgrass2_details.png",
    "autotiles/plainsgrass3_details.png",
    "autotiles/dirt_tileset.png",
    "autotiles/dirt_tileset_details.png",
    "autotiles/soil_damp_tileset.png",
    "autotiles/soil_dry_tileset.png",
    "autotiles/beachtile.png",
    "autotiles/beachdetails.png",
    "autotiles/sandtile.png",
    "autotiles/swamp_bottom1.png",
    "autotiles/swamp_bottom2.png",
    "autotiles/swamp_water_grass_green.png",
    "autotiles/swampgrass_green_details.png",
    "autotiles/burntgrass_tileset.png",
    "autotiles/ash_tileset.png",
    "tiles/world_tile_ground.png",
    "rendering/water.png",
    "autotiles/roads/forest_path_short_grass_autumn.png",
    "autotiles/roads/forest_path_tall_grass_autumn.png",
    "autotiles/forest_unbreakable_bushes_bottom_.png",
    "autotiles/forest_unbreakable_bushes_top_.png",
    "autotiles/tree_wall.png",
    "autotiles/canopy_.png",
    "autotiles/plains_3D_cliffs.png",
]

PROP_SOURCES = [
    "sprites/flora/stump.png",
    "sprites/flora/tree1.png",
    "sprites/flora/tree2.png",
    "sprites/flora/stone_pine_large.png",
    "sprites/flora/skinny_tree.png",
    "sprites/flora/tall_cypress.png",
    "sprites/flora/apple_tree_large.png",
    "sprites/flora/apple_tree_stump.png",
    "sprites/flora/stone_pine_stump.png",
    "sprites/flora/olive_tree_large.png",
    "sprites/flora/olive_tree_stump.png",
    "sprites/flora/big_bushes1.png",
    "sprites/flora/bush3.png",
    "sprites/flora/small_bush1.png",
    "sprites/flora/tiny_flowers.png",
    "sprites/flora/tiny_ground_leaves.png",
    "sprites/flora/mushrooms.png",
    "sprites/flora/bellflowers.png",
    "sprites/flora/lilies.png",
    "sprites/flora/desert/purplebush.png",
    "sprites/flora/ground_plants.png",
    "sprites/flora/wheat.png",
    "sprites/flora/wheat_animated.png",
    "sprites/biomes/swamp/swamp_trees.png",
    "sprites/terrain/round_rocks_big.png",
    "sprites/terrain/round_rocks_small.png",
    "sprites/poi/mossy_boulder_large.png",
    "sprites/poi/rock_cave.png",
    "sprites/resources/rocks.png",
    "sprites/resources/copper_ore.png",
    "tiles/rocks.png",
    "sprites/decor/decorations/tier0/brazier.png",
    "sprites/decor/decorations/tier0/bonfire.png",
]

WILDLIFE_SOURCES = [
    "sprites/creatures/wildlife/squirrel/squirrel_idle.png",
    "sprites/creatures/wildlife/squirrel/squirrel_running.png",
    "sprites/creatures/wildlife/squirrel/squirrel_feeding.png",
    "sprites/creatures/wildlife/rabbit/rabbit_idle.png",
    "sprites/creatures/wildlife/rabbit/rabbit_run.png",
    "sprites/creatures/wildlife/deer/deer_female_idle.png",
    "sprites/creatures/wildlife/deer/deer_female_walk.png",
    "sprites/creatures/wildlife/deer/deer_female_run.png",
    "sprites/creatures/wildlife/deer/deer_female_alert.png",
    "sprites/creatures/wildlife/deer/deer_female_alert_loop.png",
    "sprites/creatures/wildlife/bird/bird_idle.png",
    "sprites/creatures/wildlife/bird/bird_fly.png",
    "sprites/creatures/wildlife/bird/idle.png",
    "sprites/creatures/wildlife/bird/hop.png",
    "sprites/creatures/wildlife/bird/peck.png",
    "sprites/creatures/wildlife/bird/fly.png",
]

FLOOR_SAMPLE_TILES = [
    ("water", "autotiles/swamp_bottom2.png", (0, 0, 16, 16)),
    ("shore", "autotiles/beachtile.png", (32, 16, 48, 32)),
    ("meadow", "autotiles/grass/short_grass.png", (32, 16, 48, 32)),
    ("forest", "autotiles/grass/plainsgrass_tall.png", (32, 16, 48, 32)),
    ("swamp", "autotiles/swamp_bottom1.png", (0, 0, 16, 16)),
    ("dry_plains", "autotiles/soil_dry_tileset.png", (32, 16, 48, 32)),
]

PROP_SAMPLE_SPRITES = [
    ("tree_canopy", "sprites/flora/tree1.png", (0, 0, 48, 80)),
    ("tree_trunk", "sprites/flora/stump.png", (0, 0, 32, 32)),
    ("round_rock", "sprites/terrain/round_rocks_big.png", (0, 0, 48, 48)),
    ("bush", "sprites/flora/big_bushes1.png", (0, 0, 32, 32)),
    ("wheat", "sprites/flora/wheat_animated.png", (0, 64, 16, 96)),
    ("brazier", "sprites/decor/decorations/tier0/brazier.png", (0, 0, 32, 32)),
]


def copy_sources(source_root: Path, destination_root: Path, sources: list[str], group: str) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for relative in sources:
        source = source_root / relative
        source_path = Path(relative)
        editable_name = source_path.name
        if group in {"props", "wildlife"}:
            editable_name = f"{source_path.parent.name}_{source_path.name}"
        destination = destination_root / "sources" / group / editable_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        with Image.open(source) as image:
            records.append({
                "name": Path(relative).stem,
                "source": relative.replace("\\", "/"),
                "editable_file": destination.relative_to(destination_root).as_posix(),
                "native_size": [image.width, image.height],
            })
    return records


def pack_native_sheets(source_root: Path, sources: list[str], output: Path, max_width: int = 1024, padding: int = 8) -> list[dict[str, object]]:
    opened = [(relative, Image.open(source_root / relative).convert("RGBA")) for relative in sources]
    placements: list[tuple[str, Image.Image, int, int]] = []
    x = padding
    y = padding
    row_height = 0
    used_width = 0
    for relative, image in opened:
        if x + image.width + padding > max_width and x > padding:
            x = padding
            y += row_height + padding
            row_height = 0
        placements.append((relative, image, x, y))
        x += image.width + padding
        row_height = max(row_height, image.height)
        used_width = max(used_width, x)
    height = y + row_height + padding
    atlas = Image.new("RGBA", (max(16, used_width), max(16, height)), (0, 0, 0, 0))
    records: list[dict[str, object]] = []
    for relative, image, px, py in placements:
        atlas.alpha_composite(image, (px, py))
        records.append({
            "name": Path(relative).stem,
            "source": relative.replace("\\", "/"),
            "rect": [px, py, image.width, image.height],
            "native_size": [image.width, image.height],
            "scaled": False,
        })
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, format="PNG", optimize=False)
    return records


def build_runtime_floor_samples(source_root: Path, output: Path) -> list[dict[str, object]]:
    atlas = Image.new("RGBA", (16 * len(FLOOR_SAMPLE_TILES), 16), (0, 0, 0, 0))
    records: list[dict[str, object]] = []
    for index, (name, relative, rect) in enumerate(FLOOR_SAMPLE_TILES):
        with Image.open(source_root / relative) as source:
            crop = source.convert("RGBA").crop(rect)
        atlas.alpha_composite(crop, (index * 16, 0))
        records.append({"name": name, "source": relative, "source_rect": list(rect), "atlas_rect": [index * 16, 0, 16, 16]})
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, format="PNG", optimize=False)
    return records


def build_runtime_prop_samples(source_root: Path, output: Path) -> list[dict[str, object]]:
    cell = 96
    atlas = Image.new("RGBA", (cell * len(PROP_SAMPLE_SPRITES), cell), (0, 0, 0, 0))
    records: list[dict[str, object]] = []
    for index, (name, relative, rect) in enumerate(PROP_SAMPLE_SPRITES):
        with Image.open(source_root / relative) as source:
            crop = source.convert("RGBA").crop(rect)
        target_x = index * cell + (cell - crop.width) // 2
        target_y = cell - crop.height
        atlas.alpha_composite(crop, (target_x, target_y))
        records.append({
            "name": name,
            "source": relative,
            "source_rect": list(rect),
            "atlas_rect": [index * cell, 0, cell, cell],
            "sprite_offset": [target_x - index * cell, target_y],
            "scaled": False,
        })
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, format="PNG", optimize=False)
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", type=Path)
    parser.add_argument("destination_root", type=Path)
    args = parser.parse_args()

    destination = args.destination_root
    destination.mkdir(parents=True, exist_ok=True)
    # Remove only the legacy flattened prop files generated by the first
    # version of this utility. New prop names include their source folder so
    # identically named sheets such as resources/rocks and tiles/rocks coexist.
    for relative in PROP_SOURCES:
        legacy_file = destination / "sources" / "props" / Path(relative).name
        legacy_file.unlink(missing_ok=True)
    manifest = {
        "native_tile_size": [16, 16],
        "notes": "All source pixels remain at 1:1 native resolution. Combined atlases add transparent padding only.",
        "floor_sources": copy_sources(args.source_root, destination, FLOOR_SOURCES, "floors"),
        "prop_sources": copy_sources(args.source_root, destination, PROP_SOURCES, "props"),
        "wildlife_sources": copy_sources(args.source_root, destination, WILDLIFE_SOURCES, "wildlife"),
        "floor_atlas": pack_native_sheets(args.source_root, FLOOR_SOURCES, destination / "romestead_floors_native_atlas.png"),
        "prop_atlas": pack_native_sheets(args.source_root, PROP_SOURCES, destination / "romestead_props_native_atlas.png"),
        "wildlife_atlas": pack_native_sheets(args.source_root, WILDLIFE_SOURCES, destination / "romestead_wildlife_native_atlas.png"),
        "runtime_floor_samples": build_runtime_floor_samples(args.source_root, destination / "runtime" / "romestead_floor_samples_native.png"),
        "runtime_prop_samples": build_runtime_prop_samples(args.source_root, destination / "runtime" / "romestead_prop_samples_native.png"),
    }
    (destination / "romestead_native_atlas_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps({"floors": len(FLOOR_SOURCES), "props": len(PROP_SOURCES), "wildlife": len(WILDLIFE_SOURCES), "tile_size": 16}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
