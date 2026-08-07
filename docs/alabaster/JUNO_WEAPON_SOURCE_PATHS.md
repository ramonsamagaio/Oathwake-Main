# Juno weapon source files to copy from the demo

Copy paths are relative to the demo installation root.

## Required figure definition

`terra/data/figures/weapon/player-weapon.json`

This single file contains the named weapon FIG entries referenced by Juno:

- `FIG:weapon.player-weapon#sword`
- `FIG:weapon.player-weapon#hammer`
- `FIG:weapon.player-weapon#hammerBack`
- `FIG:weapon.player-weapon#spear`
- `FIG:weapon.player-weapon#spearBack`
- `FIG:weapon.player-weapon#tonfa`
- `FIG:weapon.player-weapon#crossbow`
- `FIG:weapon.player-weapon#chakram`
- `FIG:weapon.player-weapon#kama`
- `FIG:weapon.player-weapon#bomb`

## Weapon atlases/media

Copy the complete folder if possible:

`terra/media/char/weapon/`

The demo manifest includes at least:

- `terra/media/char/weapon/chakrams-01.png`
- `terra/media/char/weapon/crossbow-01.png`
- `terra/media/char/weapon/hammers.png`
- `terra/media/char/weapon/player-melee.png`
- `terra/media/char/weapon/player-ranged.png`
- `terra/media/char/weapon/projectiles.png`
- `terra/media/char/weapon/weapon-test.png`

Copying the full `terra/media/char/weapon/` folder is preferred because `player-weapon.json` is the authority for which atlas/range each named FIG uses.

The Oathwake runtime accepts `player-melee.png` and `player-ranged.png` only as complete direct PNG assets. If either file is absent, `BonesWeapons` uses its procedural socket-driven fallback. Do not reconstruct weapon PNGs from partial Base64 fragments and never decode weapon media in the attack hot path.

## Inventory icon atlas

`terra/media/gui/items-icons.png`

Known Juno item icon crops from the supplied player data:

| Oathwake ID | Juno weapon | FIG | Icon crop |
| --- | --- | --- | --- |
| `juno_sword` | Claio Solas | `#sword` | `[128,0,32,32]` |
| `juno_crossbow` | Bogha Solas | `#crossbow` | `[160,0,32,32]` |
| `juno_hammer` | Ortrom Solas | `#hammer` | `[192,0,32,32]` |
| `juno_chakram` | Fain Solas | `#chakram` | `[224,0,32,32]` |
| `juno_spear` | Lann Solas | `#spear` | `[256,0,32,32]` |
| `juno_tonfa` | Dorn Solas | `#tonfa` | `[288,0,32,32]` |
| `juno_kama` | Corran Solas | `#kama` | `[320,0,32,32]` |
| `juno_bomb` | Boma Solas | `#bomb` | `[352,0,32,32]` |

## Recommended package to send into the Oathwake project

Copy these three things together:

1. `terra/data/figures/weapon/player-weapon.json`
2. the full `terra/media/char/weapon/` folder
3. `terra/media/gui/items-icons.png`

Once `player-weapon.json` and its atlas PNGs are present, the Oathwake importer can map the exact regions/pivots/facing rules for each weapon instead of using the temporary procedural placeholders.
