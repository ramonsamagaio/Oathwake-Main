from __future__ import annotations

import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

OLD_BASE = Path("assets/world_lab/romestead_native_png/sources")
NEW_BASE = Path("assets/sprites/world/procedural")

GROUPS = {
    "terrain": {
        "old_dir": "floors",
        "files": [
            "plainsgrass2.png",
            "short_grass.png",
            "plainsgrass3.png",
            "plainsgrass1.png",
            "tall_grass.png",
            "forest_path_short_grass_autumn.png",
            "forest_unbreakable_bushes_bottom_.png",
            "forest_unbreakable_bushes_top_.png",
            "tree_wall.png",
            "canopy_.png",
            "plains_3D_cliffs.png",
            "plainsgrass2_details.png",
            "shortgrass_details.png",
            "plainsgrass3_details.png",
        ],
    },
    "trees": {
        "old_dir": "props",
        "files": [
            "flora_stump.png",
            "flora_tree1.png",
            "flora_tree2.png",
            "flora_olive_tree_large.png",
            "flora_olive_tree_stump.png",
            "flora_skinny_tree.png",
            "flora_tall_cypress.png",
            "flora_apple_tree_large.png",
            "flora_apple_tree_stump.png",
            "flora_stone_pine_large.png",
            "flora_stone_pine_stump.png",
        ],
    },
    "rocks": {
        "old_dir": "props",
        "files": [
            "terrain_round_rocks_big.png",
            "terrain_round_rocks_small.png",
            "poi_mossy_boulder_large.png",
            "resources_copper_ore.png",
        ],
    },
    "plants": {
        "old_dir": "props",
        "files": [
            "flora_big_bushes1.png",
            "flora_small_bush1.png",
            "desert_purplebush.png",
            "flora_ground_plants.png",
            "flora_wheat_animated.png",
            "flora_mushrooms.png",
            "flora_bellflowers.png",
            "flora_lilies.png",
            "flora_tiny_flowers.png",
            "flora_tiny_ground_leaves.png",
        ],
    },
    "objects": {
        "old_dir": "props",
        "files": ["tier0_brazier.png"],
    },
    "wildlife": {
        "old_dir": "wildlife",
        "files": [
            "squirrel_squirrel_idle.png",
            "squirrel_squirrel_running.png",
            "squirrel_squirrel_feeding.png",
            "rabbit_rabbit_idle.png",
            "rabbit_rabbit_run.png",
            "deer_deer_female_idle.png",
            "deer_deer_female_walk.png",
            "deer_deer_female_run.png",
            "deer_deer_female_alert.png",
            "deer_deer_female_alert_loop.png",
            "bird_idle.png",
            "bird_hop.png",
            "bird_peck.png",
            "bird_fly.png",
        ],
    },
}

# flora_lilies.png is consumed through sprites.json / ContentDB only. It was
# intentionally not declared as a RomesteadBiomeWorld2D constant.
NOT_GENERATOR_CONSTANTS = {"flora_lilies.png"}


def git_files() -> list[Path]:
    return [
        Path(p)
        for p in subprocess.check_output(["git", "ls-files"], text=True).splitlines()
    ]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if (
        len(header) < 24
        or header[:8] != b"\x89PNG\r\n\x1a\n"
        or header[12:16] != b"IHDR"
    ):
        raise SystemExit(f"Not a valid PNG: {path}")
    return struct.unpack(">II", header[16:24])


def readable_utf8(path: Path) -> str | None:
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def build_mapping() -> dict[Path, Path]:
    mapping: dict[Path, Path] = {}
    for category, info in GROUPS.items():
        for filename in info["files"]:
            source = OLD_BASE / info["old_dir"] / filename
            destination = NEW_BASE / category / filename
            if source in mapping:
                raise SystemExit(f"Duplicate source in manifest: {source}")
            mapping[source] = destination
    if len(mapping) != 54:
        raise SystemExit(f"Manifest must contain exactly 54 PNGs, got {len(mapping)}")
    if len(set(mapping.values())) != 54:
        raise SystemExit("Destination manifest contains duplicate paths")
    return mapping


def preflight(mapping: dict[Path, Path]) -> tuple[dict, dict, dict, int]:
    missing: list[str] = []
    collisions: list[str] = []
    before_hashes: dict[Path, str] = {}
    before_sizes: dict[Path, tuple[int, int]] = {}
    before_uids: dict[Path, str] = {}

    for source, destination in mapping.items():
        sidecar = Path(str(source) + ".import")
        if not source.is_file():
            missing.append(str(source))
        if not sidecar.is_file():
            missing.append(str(sidecar))
        if destination.exists() or Path(str(destination) + ".import").exists():
            collisions.append(str(destination))
        if source.is_file():
            before_hashes[source] = sha256(source)
            before_sizes[source] = png_size(source)
        if sidecar.is_file():
            text = sidecar.read_text(encoding="utf-8")
            uid_match = re.search(r'^uid="([^"]+)"', text, re.MULTILINE)
            if not uid_match:
                raise SystemExit(f"Godot import sidecar has no UID: {sidecar}")
            before_uids[source] = uid_match.group(1)

    if missing:
        raise SystemExit("Pre-flight missing files:\n" + "\n".join(missing))
    if collisions:
        raise SystemExit("Pre-flight destination collisions:\n" + "\n".join(collisions))
    if len(set(before_uids.values())) != len(before_uids):
        raise SystemExit("Duplicate Godot UID found among the 54 visual assets")

    direct_reference_count = 0
    for path in git_files():
        text = readable_utf8(path)
        if text is None:
            continue
        for source in mapping:
            if "res://" + source.as_posix() in text:
                direct_reference_count += 1

    return before_hashes, before_sizes, before_uids, direct_reference_count


def move_assets(mapping: dict[Path, Path]) -> None:
    for category in GROUPS:
        (NEW_BASE / category).mkdir(parents=True, exist_ok=True)
    for source, destination in mapping.items():
        subprocess.run(
            ["git", "mv", source.as_posix(), destination.as_posix()], check=True
        )
        subprocess.run(
            ["git", "mv", str(source) + ".import", str(destination) + ".import"],
            check=True,
        )


def replace_direct_references(mapping: dict[Path, Path]) -> dict[str, str]:
    replacements = {
        "res://" + source.as_posix(): "res://" + destination.as_posix()
        for source, destination in mapping.items()
    }
    for path in git_files():
        text = readable_utf8(path)
        if text is None:
            continue
        migrated = text
        for old, new in replacements.items():
            migrated = migrated.replace(old, new)
        if migrated != text:
            path.write_text(migrated, encoding="utf-8")
    return replacements


def migrate_generator_constants() -> None:
    biome_script = Path("scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd")
    script = biome_script.read_text(encoding="utf-8")
    old_root_decl = (
        'const EDITABLE_ROOT := "res://assets/world_lab/romestead_native_png/sources"\n'
    )
    new_root_decl = (
        'const PROCEDURAL_SPRITE_ROOT := "res://assets/sprites/world/procedural"\n'
        'const TERRAIN_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/terrain"\n'
        'const TREE_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/trees"\n'
        'const ROCK_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/rocks"\n'
        'const PLANT_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/plants"\n'
        'const OBJECT_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/objects"\n'
    )
    if old_root_decl not in script:
        raise SystemExit(
            "Expected EDITABLE_ROOT declaration not found; aborting instead of guessing"
        )
    script = script.replace(old_root_decl, new_root_decl, 1)

    root_for_category = {
        "terrain": "TERRAIN_SPRITE_ROOT",
        "trees": "TREE_SPRITE_ROOT",
        "rocks": "ROCK_SPRITE_ROOT",
        "plants": "PLANT_SPRITE_ROOT",
        "objects": "OBJECT_SPRITE_ROOT",
    }
    for category, info in GROUPS.items():
        if category == "wildlife":
            continue
        root_name = root_for_category[category]
        for filename in info["files"]:
            old_expression = f'EDITABLE_ROOT + "/{info["old_dir"]}/{filename}"'
            new_expression = f'{root_name} + "/{filename}"'
            if old_expression not in script:
                if filename in NOT_GENERATOR_CONSTANTS:
                    continue
                raise SystemExit(
                    f"Expected generated-path expression not found: {old_expression}"
                )
            script = script.replace(old_expression, new_expression)

    if "EDITABLE_ROOT" in script:
        raise SystemExit("Stale EDITABLE_ROOT remains after targeted migration")
    biome_script.write_text(script, encoding="utf-8")


def verify_identity(
    mapping: dict[Path, Path],
    before_hashes: dict[Path, str],
    before_sizes: dict[Path, tuple[int, int]],
    before_uids: dict[Path, str],
) -> None:
    for source, destination in mapping.items():
        if not destination.is_file():
            raise SystemExit(f"Moved PNG missing: {destination}")
        sidecar = Path(str(destination) + ".import")
        if not sidecar.is_file():
            raise SystemExit(f"Moved import sidecar missing: {sidecar}")
        if sha256(destination) != before_hashes[source]:
            raise SystemExit(f"PNG bytes changed during move: {source} -> {destination}")
        if png_size(destination) != before_sizes[source]:
            raise SystemExit(
                f"PNG dimensions changed during move: {source} -> {destination}"
            )
        sidecar_text = sidecar.read_text(encoding="utf-8")
        uid_match = re.search(r'^uid="([^"]+)"', sidecar_text, re.MULTILINE)
        if not uid_match or uid_match.group(1) != before_uids[source]:
            raise SystemExit(f"Godot UID changed during move: {source} -> {destination}")
        expected_source = f'source_file="res://{destination.as_posix()}"'
        if expected_source not in sidecar_text:
            raise SystemExit(f".import source_file not migrated: {sidecar}")


def verify_no_stale_references(replacements: dict[str, str]) -> None:
    stale: list[str] = []
    for path in git_files():
        text = readable_utf8(path)
        if text is None:
            continue
        for old in replacements:
            if old in text:
                stale.append(f"{path}: {old}")
    if stale:
        raise SystemExit("Stale moved-asset references remain:\n" + "\n".join(stale))


def verify_new_references_resolve() -> None:
    broken: list[str] = []
    pattern = re.compile(
        r"res://assets/sprites/world/procedural/[A-Za-z0-9_./-]+\.png"
    )
    for path in git_files():
        text = readable_utf8(path)
        if text is None:
            continue
        for reference in set(pattern.findall(text)):
            disk_path = Path(reference.removeprefix("res://"))
            if not disk_path.is_file():
                broken.append(f"{path}: {reference}")
    if broken:
        raise SystemExit(
            "New procedural sprite references do not resolve:\n" + "\n".join(broken)
        )


def verify_json_and_regions() -> None:
    for json_path in Path("data").glob("*.json"):
        try:
            json.loads(json_path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"Invalid JSON after migration: {json_path}: {exc}")

    sprites = json.loads(Path("data/sprites.json").read_text(encoding="utf-8"))
    for sprite_id, entry in sprites.items():
        reference = str(entry.get("texture_path", ""))
        if not reference.startswith("res://assets/sprites/world/procedural/"):
            continue
        image = Path(reference.removeprefix("res://"))
        if not image.is_file():
            raise SystemExit(
                f"Sprite {sprite_id} points to missing moved texture: {reference}"
            )
        width, height = png_size(image)
        region = entry.get("region", {})
        if entry.get("region_enabled", False) and isinstance(region, dict):
            x = int(region.get("x", 0))
            y = int(region.get("y", 0))
            w = int(region.get("w", 0))
            h = int(region.get("h", 0))
            if (
                x < 0
                or y < 0
                or w <= 0
                or h <= 0
                or x + w > width
                or y + h > height
            ):
                raise SystemExit(
                    f"Sprite region outside moved atlas: {sprite_id} {region} "
                    f"vs {width}x{height} ({reference})"
                )

    monsters = json.loads(Path("data/monsters.json").read_text(encoding="utf-8"))
    for monster_id, monster in monsters.items():
        animations = monster.get("animations", {})
        if not isinstance(animations, dict):
            continue
        for animation_name, animation in animations.items():
            if not isinstance(animation, dict):
                continue
            reference = str(animation.get("texture_path", ""))
            if not reference.startswith(
                "res://assets/sprites/world/procedural/wildlife/"
            ):
                continue
            image = Path(reference.removeprefix("res://"))
            width, height = png_size(image)
            frame_width = int(animation.get("frame_width", 0))
            frame_height = int(animation.get("frame_height", 0))
            frames = int(animation.get("frames", 1))
            start = int(animation.get("frame_start", 0))
            row = int(animation.get("row", 0))
            if (
                frame_width <= 0
                or frame_height <= 0
                or (start + frames) * frame_width > width
                or (row + 1) * frame_height > height
            ):
                raise SystemExit(
                    "Wildlife animation grid outside atlas: "
                    f"{monster_id}/{animation_name} -> {reference}; "
                    f"frame={frame_width}x{frame_height}, start={start}, "
                    f"frames={frames}, row={row}, image={width}x{height}"
                )


def write_readme() -> None:
    lines = [
        "# Procedural World Visuals",
        "",
        "These are the **54 visual PNGs currently wired into the Romestead-derived procedural world pipeline**.",
        "They were moved here without changing image bytes, dimensions, atlas coordinates, or Godot UIDs.",
        "",
        "## Editing rule",
        "",
        "Redraw pixels inside the existing canvas and atlas slots. Keep each PNG filename, canvas size, slot positions and transparency layout unless the corresponding metadata/code is updated at the same time.",
        "",
        "Do **not** manually edit or delete the `.png.import` files. They preserve Godot import settings and asset UIDs.",
        "",
        "## Folders",
        "",
        "- `terrain/` — biome ground sheets, dense-forest wall/canopy sheets, terrain details and the plains cliff atlas.",
        "- `trees/` — trunks/stumps and tree canopy atlases.",
        "- `rocks/` — large/small rocks, mossy boulder and copper ore.",
        "- `plants/` — bushes, wheat, flowers, mushrooms and tiny ground vegetation.",
        "- `objects/` — standalone procedural-world object art. Currently only the tier-0 brazier; its auto-spawn is disabled in the integrated map.",
        "- `wildlife/` — squirrel, rabbit, female deer and bird animation sheets.",
        "",
        "## Current files",
        "",
    ]
    for category, info in GROUPS.items():
        lines.extend([f"### {category}", ""])
        lines.extend([f"- `{filename}`" for filename in info["files"]])
        lines.append("")
    lines.extend(
        [
            "## Migration checks performed",
            "",
            "- Exactly 54 PNGs in the manifest, with no duplicate source or destination.",
            "- Every PNG and `.png.import` sidecar existed before the move.",
            "- No destination collision existed.",
            "- SHA-256 and PNG dimensions were identical before and after the move.",
            "- Every Godot UID was preserved.",
            "- Every old direct `res://` reference to these 54 images was removed.",
            "- Every new procedural-world PNG reference resolves to an existing file.",
            "- All JSON files in `data/` still parse.",
            "- Every `sprites.json` region referencing a moved image stays inside its PNG bounds.",
            "- Every moved wildlife animation grid stays inside its PNG bounds.",
            "",
            "The separate lighting-cookie SVG remains outside this folder because it is not one of the sprite/atlas PNGs and moving it would add unnecessary risk.",
            "",
        ]
    )
    NEW_BASE.mkdir(parents=True, exist_ok=True)
    (NEW_BASE / "README.md").write_text("\n".join(lines), encoding="utf-8")


def verify_final_manifest(mapping: dict[Path, Path]) -> None:
    actual = sorted(NEW_BASE.rglob("*.png"))
    expected = sorted(mapping.values())
    if actual != expected:
        extra = sorted(set(actual) - set(expected))
        missing = sorted(set(expected) - set(actual))
        raise SystemExit(
            f"Final 54-file set mismatch; extra={extra}; missing={missing}"
        )


def main() -> None:
    mapping = build_mapping()
    before_hashes, before_sizes, before_uids, direct_ref_count = preflight(mapping)
    move_assets(mapping)
    replacements = replace_direct_references(mapping)
    migrate_generator_constants()
    verify_identity(mapping, before_hashes, before_sizes, before_uids)
    verify_no_stale_references(replacements)
    verify_new_references_resolve()
    verify_json_and_regions()
    write_readme()
    verify_final_manifest(mapping)

    subprocess.run(["git", "diff", "--check"], check=True)
    print("SAFE MIGRATION VALIDATED")
    print(f"PNG files moved: {len(mapping)}")
    print(f"Godot UIDs preserved: {len(before_uids)}")
    print(f"Direct old references observed before move: {direct_ref_count}")


if __name__ == "__main__":
    main()
