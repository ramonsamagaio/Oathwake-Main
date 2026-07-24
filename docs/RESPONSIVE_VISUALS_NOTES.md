# Responsive Visuals Notes

## Responsive canvas

The project keeps its authored 1600x900 composition as a virtual viewport and scales the complete rendered canvas with `viewport + keep + fractional` stretch settings.

This means UI controls, inventory interaction rectangles, HUD art, intro elements, world rendering and mouse coordinates all receive the same scale transform. Individual inventory slots and buttons are not repositioned.

Different aspect ratios may show letterbox/pillarbox space instead of stretching the authored composition out of shape.

## Slime controls

Select the root node of `scenes/enemies/Slime.tscn` to edit:

- `ground_shadow_enabled`
- `ground_shadow_opacity`
- `ground_shadow_offset`
- `ground_shadow_scale`
- `glow_enabled`
- `glow_color`
- `glow_intensity`
- `glow_offset`
- `glow_scale`
- `glow_pulse_speed`
- `glow_pulse_strength`

The slime aura is a local additive shader and no longer reads the screen texture.

## Dropped item controls

Select the root node of `scenes/items/WorldItem.tscn` to edit:

- `drop_shadow_enabled`
- `shadow_opacity`
- `drop_shadow_width_factor`
- `drop_shadow_height_ratio`

## Global bloom

`ScreenEffectsSettings.tscn` now includes `colored_glow_boost`. It lets saturated dark-fantasy colors contribute a small amount to bloom without lowering the main threshold for the entire map.

## Pickup sound

The `item_pickup` profile appears in the Content Editor Sound Effects section and can be replaced there without changing gameplay code.
