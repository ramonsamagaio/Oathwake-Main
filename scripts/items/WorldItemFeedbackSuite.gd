extends "res://scripts/items/WorldItemShaderSuite.gd"

const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")

@export_category("Dropped Item Shadow")
@export var drop_shadow_enabled := true
# Legacy ellipse values remain serialized for scene compatibility, but the runtime
# now projects the item's actual sprite silhouette through World Shadows.
@export_range(0.20, 0.80, 0.01) var drop_shadow_width_factor := 0.46
@export_range(0.15, 0.60, 0.01) var drop_shadow_height_ratio := 0.30


func _process(delta: float) -> void:
	super._process(delta)
	WorldDepthRuntime.apply_node_depth(self)
	if _shadow == null or collected:
		return
	_shadow.visible = drop_shadow_enabled
	_shadow.z_index = 0


func _try_collect() -> void:
	var was_collected := collected
	super._try_collect()
	if not was_collected and collected:
		var sfx_manager := get_node_or_null("/root/SFXManager")
		if sfx_manager != null and sfx_manager.has_method("play_profile"):
			sfx_manager.play_profile("item_pickup", global_position)


func _sync_outline_visual() -> void:
	super._sync_outline_visual()
	_configure_drop_shadow()


func _configure_drop_shadow() -> void:
	if sprite == null:
		return
	_refresh_projected_shadow()
	if _shadow == null:
		return
	_shadow.visible = drop_shadow_enabled and not collected
	_shadow.z_index = 0
