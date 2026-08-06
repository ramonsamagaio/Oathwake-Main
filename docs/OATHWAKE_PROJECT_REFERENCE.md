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

## Combat action contract

- Player and monsters must have zero locomotion velocity throughout attack windup, contact and recovery.
- Player blocking uses the right mouse button while gameplay is not covered by inventory, storage, crafting or building mode.
- The opening block window is the parry window.
- A successful parry cancels the incoming damage and stuns the attacking monster for 1 second.
- Normal blocking reduces incoming damage but does not stun the attacker.
- Player and monsters expose `apply_stun(duration, source)`, `is_stunned()` and `get_stun_time_left()`.
- Monster attack results include the attacking node under `source`, allowing the defender to parry the correct attacker at the authored contact frame.

## Pet equipment contract

- Pet item: `butterfly_pet_trinket`
- Pet id: `butterfly_pickup`
- Behavior: follows the player and fetches nearby nodes in the `world_item` group.
- World drops expose `collect_for_player(player)` so pets reuse the normal inventory pickup path.
- Gameplay addresses the equipment slot as `trinket`.
- Provisional UI mapping: `trinket` currently aliases the existing `back` slot until a dedicated trinket slot is drawn and added to the inventory artwork.
- Equipping or unequipping emits `EquipmentSystem.changed`, and the player refreshes the active pet automatically.

## Replaceable placeholder sprites

These are deliberately isolated so final pixel-art assets can replace them without changing gameplay code:

- Dash smoke: `assets/sprites/effects/placeholders/dash_smoke_placeholder.svg`
- Parry effect: `assets/sprites/effects/placeholders/parry_effect_placeholder.svg`
- Butterfly pet: `assets/sprites/pets/placeholders/butterfly_pet_placeholder.svg`

Runtime scenes:

- `scenes/effects/SmokePuff.tscn`
- `scenes/effects/ParryEffect.tscn`
- `scenes/pets/ButterflyPet.tscn`
