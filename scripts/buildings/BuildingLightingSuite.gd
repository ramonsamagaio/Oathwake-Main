extends "res://scripts/buildings/Building.gd"

const ContentGlowRuntime := preload("res://scripts/effects/ContentGlowRuntime.gd")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")


func _ready() -> void:
	super._ready()
	_apply_content_presentation()


func setup(new_building_id: String, new_data: Dictionary = {}) -> void:
	super.setup(new_building_id, new_data)
	_apply_content_presentation()


func _on_content_reloaded() -> void:
	super._on_content_reloaded()
	_apply_content_presentation()


func _apply_content_presentation() -> void:
	ContentGlowRuntime.apply_glow(self, building_data.get("glow", {}) if building_data.get("glow", {}) is Dictionary else {}, 24)
	var depth_value: Variant = building_data.get("depth_sort", {})
	var depth_config: Dictionary = (depth_value as Dictionary) if depth_value is Dictionary else {}
	if content_sprite != null and content_sprite.visible:
		var depth_y := WorldDepthRuntime.get_sprite_depth_y(content_sprite, float(depth_config.get("line_ratio", 0.64)))
		WorldDepthRuntime.apply_depth(self, depth_y + float(depth_config.get("offset_y", 0.0)))
	else:
		WorldDepthRuntime.apply_node_depth(self, float(depth_config.get("offset_y", 0.0)))

	var shadow_value: Variant = building_data.get("shadow", {})
	var shadow_config: Dictionary = (shadow_value as Dictionary).duplicate(true) if shadow_value is Dictionary else {}
	if not shadow_config.has("enabled"):
		shadow_config["enabled"] = true
	var visual_size := DirectionalShadowRuntime.estimate_target_visual_size(self)
	var foot_offset := DirectionalShadowRuntime.estimate_target_foot_offset(self)
	DirectionalShadowRuntime.apply_to_target(self, shadow_config, visual_size, foot_offset)
