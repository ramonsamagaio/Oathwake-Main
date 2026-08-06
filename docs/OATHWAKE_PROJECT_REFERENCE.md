# Oathwake project reference

## Canonical repository

- Repository: `ramonsamagaio/Oathwake-REPO-Main`
- Main branch: `main`
- Gameplay engine: Godot 4.6.3

Use this repository automatically for future Oathwake code inspection and implementation work.

## Active player runtime chain

`scenes/Player.tscn` uses `scripts/player/WIPPlayer.gd`.

The active inheritance chain is:

1. `WIPPlayer.gd`
2. `PlayerLightPerspectiveSuite.gd`
3. `PlayerCombatGuardPetSuite.gd`
4. `PlayerLifeAnimationSuite.gd`
5. `PlayerWorldFeedbackSuite.gd`
6. `PlayerShaderSuite.gd`
7. `PlayerEnhanced.gd`
8. `Player.gd`

Combat, guard, stun and equipped-pet behavior must remain in the combat suite rather than being duplicated in the WIP visual layer.

## Enemy runtime chain

`EnemyBaseEnhanced.gd` extends `EnemyBehaviorSuite.gd`, which extends `EnemyScreenCombatSuite.gd` and then `EnemyBase.gd`.

- `peaceful = true` prevents contact attacks.
- `fearful = true` makes the monster flee while the player is inside `fear_radius`.
- Peaceful and fearful may be enabled together for passive wildlife.
- Monster disposition is editable through the Content Editor checkboxes `Peaceful` and `Fearful`.

## Combat action contract

- Player and monsters must have zero locomotion velocity throughout attack windup, contact and recovery.
- Player blocking uses the right mouse button while gameplay is not covered by inventory, storage, crafting or building mode.
- The opening block window is the parry window.
- A successful parry cancels the incoming damage and stuns the attacking monster for 1 second.
- Normal blocking reduces incoming damage but does not stun the attacker.
- Player and monsters expose `apply_stun(duration, source)`, `is_stunned()` and `get_stun_time_left()`.
- Monster attack results include the attacking node under `source`, allowing the defender to parry the correct attacker at the authored contact frame.
- While stunned, player and monsters display the looping seven-frame `StunEffect` above the head.

## Butterfly pet contract

Six butterfly pet variants are registered:

- Blue: `butterfly_pet_trinket`
- Grey: `grey_butterfly_trinket`
- Pink: `pink_butterfly_trinket`
- Red: `red_butterfly_trinket`
- White: `white_butterfly_trinket`
- Yellow: `yellow_butterfly_trinket`

All variants:

- use the five-frame 16x16 sheets in `assets/sprites/pets/Butterflies`;
- follow the player through curved, fluttering steering rather than a fixed offset;
- roam near a stationary player instead of remaining attached to one point;
- trail a moving player at their own speed;
- fetch nearby nodes in the `world_item` group;
- use a ground shadow positioned far below the sprite to communicate high flight.

World drops expose `collect_for_player(player)` so pets reuse the normal inventory pickup path. Gameplay addresses the equipment slot as `trinket`; it currently aliases the existing `back` slot until a dedicated trinket slot is drawn.

## Wild butterflies

The six wild butterfly monster ids are:

- `butterfly_blue`
- `butterfly_grey`
- `butterfly_pink`
- `butterfly_red`
- `butterfly_white`
- `butterfly_yellow`

Each wild butterfly has 10 health, is peaceful and fearful, wanders with fluttering flight, and drops only `butterfly_wings`.

## Terrain-driven spawning

Natural monster spawning is configured through each terrain type's `monster_spawns` list.

- `grass` currently includes slime and all six butterfly colors.
- Natural spawn candidates must be outside the current camera rectangle plus the configured safety margin.
- Per-species `max_alive` values and weighted selection prevent one creature from saturating the map.
- Campfire safe radii continue to reject nearby spawn positions.

## Final effect assets

- Dash smoke uses one-based row 11 from `assets/sprites/effects/FX/PUFFS/Free Smoke Fx  Pixel 07.png`.
- Parry uses one-based row 6 from `assets/sprites/effects/FX/IMPACTS/parry.png`.
- Stun loops `STUN_0001.png` through `STUN_0007.png` from `assets/sprites/effects/FX/CONDITIONS/STUN`.

Runtime scenes:

- `scenes/effects/SmokePuff.tscn`
- `scenes/effects/ParryEffect.tscn`
- `scenes/effects/StunEffect.tscn`
- `scenes/pets/ButterflyPet.tscn`
- `scenes/enemies/ButterflyMonster.tscn`

## Supplemental content files

- `data/pet_items.json` contains the six pet trinkets.
- `data/butterfly_monsters.json` contains the six wild butterflies.
- `data/supplemental_items.json` contains `butterfly_wings` and the inventory-valid `campfire` item.
- `ContentDB.gd` merges these files into the normal item and monster dictionaries at runtime.
