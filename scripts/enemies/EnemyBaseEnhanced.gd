extends "res://scripts/enemies/EnemyScreenCombatSuite.gd"

const HitFlashOverlayScript := preload("res://scripts/effects/HitFlashOverlay.gd")
const ContentGlowRuntime := preload("res://scripts/effects/ContentGlowRuntime.gd")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")


func _ready() -> void:
	super._ready()
	_apply_content_visual_effects()
	_update_world_depth()
	_connect_content_visual_reload()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_world_depth()


func _get_fallback_visual_nodes() -> Array:
	var fallback_nodes := super._get_fallback_visual_nodes()
	var filtered: Array = []
	for node in fallback_nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node.is_in_group("persistent_content_visual"):
			continue
		if str(node.name) in ["GroundShadow", "ContentGlow", "SlimeGlow", "GlowOverlayNative"]:
			continue
		filtered.append(node)
	return filtered


func _apply_content_visual_effects() -> void:
	ContentGlowRuntime.apply_content_effects(self, monster_data, 24)


func _connect_content_visual_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_on_content_visuals_reloaded")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)


func _on_content_visuals_reloaded() -> void:
	_refresh_runtime_monster_content()
	_apply_content_visual_effects()
	_update_world_depth()


func _refresh_runtime_monster_content() -> void:
	_load_monster_data()
	health = mini(health, max_health)
	if _monster_locomotion != null and is_instance_valid(_monster_locomotion):
		_monster_locomotion.configure(monster_data, movement_mode, direction_mode, locomotion_data, speed)
	if nameplate != null and is_instance_valid(nameplate):
		_update_nameplate()


func _update_world_depth() -> void:
	var depth_config_value: Variant = monster_data.get("depth_sort", {})
	var depth_config := depth_config_value as Dictionary if depth_config_value is Dictionary else {}
	WorldDepthRuntime.apply_node_depth(self, float(depth_config.get("offset_y", 0.0)))


func _play_hit_feedback(is_critical: bool) -> void:
	var vfx_profile := _get_vfx_profile()
	var flash_duration := float(vfx_profile.get("white_hit_flash_duration", 0.08))
	if is_critical:
		flash_duration = float(vfx_profile.get("critical_white_hit_flash_duration", max(flash_duration, 0.10)))
	HitFlashOverlayScript.flash_node(self, flash_duration)
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_hit_for_target"):
		sfx_manager.play_hit_for_target(self, is_critical)

	if enable_knockback:
		var hit_bump_scale := float(vfx_profile.get("hit_bump_scale", 1.04))
		var critical_bump_scale := float(vfx_profile.get("critical_bump_scale", 1.08))
		var bump_scale := original_scale * (critical_bump_scale if is_critical else hit_bump_scale)
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", bump_scale, 0.04)
		scale_tween.tween_property(self, "scale", original_scale, 0.08)
