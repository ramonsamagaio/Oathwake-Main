# Juno weapon source paths

## Canonical Oathwake runtime paths

The weapon runtime now reads the committed PNG assets directly through Godot's ResourceLoader. No Base64 or runtime PNG decoding is used for weapons.

- `res://assets/sprites/weapons/player-melee.png`
- `res://assets/sprites/weapons/player-ranged.png`

Other reference/test sheets currently committed in the same directory:

- `res://assets/sprites/weapons/chakrams-01.png`
- `res://assets/sprites/weapons/crossbow-01.png`
- `res://assets/sprites/weapons/hammers.png`
- `res://assets/sprites/weapons/projectiles.png`
- `res://assets/sprites/weapons/weapon-test.png`

`player-weapon.json` remains the authority for FIG geometry, ranges, pivots, facing and sockets. Its spriteSheets block maps:

- source sheet `melee` -> `player-melee.png` (`672x152`)
- source sheet `ranged` -> `player-ranged.png` (`672x92`)

## Figure-to-atlas mapping used by Oathwake

| Oathwake item | Source FIG | Required atlas |
| --- | --- | --- |
| `juno_sword` | `#sword` | `player-melee.png` |
| `juno_broadsword` | `#broadsword` | `player-melee.png` |
| `juno_hammer` | `#hammer` / `#hammerBack` | `player-melee.png` |
| `juno_spear` | `#spear` / `#spearBack` | `player-melee.png` |
| `juno_tonfa` | `#tonfa` | `player-melee.png` |
| `juno_crossbow` | `#crossbow` | `player-ranged.png` |
| `juno_chakram` | `#chakram` | `player-ranged.png` |
| `juno_kama` | `#kama` | `player-ranged.png` |
| `juno_bomb` | `#bomb` | `player-ranged.png` |
| `juno_gauntlet` | `#gauntlet` | both `player-melee.png` and `player-ranged.png` |

The Gauntlet is intentionally treated as a mixed-atlas FIG because the supplied `player-weapon.json` references both sheet names inside the same figure.

## Original demo locations

For provenance/reference, the original demo paths are:

- `terra/data/figures/weapon/player-weapon.json`
- `terra/media/char/weapon/player-melee.png`
- `terra/media/char/weapon/player-ranged.png`

The runtime must not read those demo paths directly.

## Inventory icon atlas

The supplied player data references `terra/media/gui/items-icons.png` and known 32x32 crops:

| Oathwake ID | Juno weapon | Icon crop |
| --- | --- | --- |
| `juno_sword` | Claio Solas | `[128,0,32,32]` |
| `juno_crossbow` | Bogha Solas | `[160,0,32,32]` |
| `juno_hammer` | Ortrom Solas | `[192,0,32,32]` |
| `juno_chakram` | Fain Solas | `[224,0,32,32]` |
| `juno_spear` | Lann Solas | `[256,0,32,32]` |
| `juno_tonfa` | Dorn Solas | `[288,0,32,32]` |
| `juno_kama` | Corran Solas | `[320,0,32,32]` |
| `juno_bomb` | Boma Solas | `[352,0,32,32]` |

That icon atlas is metadata-only until a committed Oathwake copy exists at a canonical project path. Do not point runtime item sprites at a non-existent PNG.
