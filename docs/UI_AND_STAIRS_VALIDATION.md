# UI and stair usability update

- Building input is routed through `_unhandled_input`, after Godot UI controls receive clicks.
- Runtime buttons receive larger hit targets, solid backgrounds and visible hover/pressed states.
- Building mode has a dedicated clickable panel with floor navigation.
- Campfires are built directly from raw resources. Retrieved campfires become inventory items and are consumed first when placed again.
- Stairs support `R` or `E`, have a larger interaction radius and trigger automatically when stepped on.
- Building stairs creates a free upper landing surface and moves the player away from the stair cell after transitioning.
- Lower floors remain visible as dark, non-interactive ghost layers.
