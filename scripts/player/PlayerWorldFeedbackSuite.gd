extends "res://scripts/player/PlayerShaderSuite.gd"

const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")


var _content_character_side_view := false
var _content_visual_scale := 1.0
var _content_visual_offset := Vector2.ZERO
var _content_depth_offset_y := 0.0
var _content_shadow_config: Dictionary = {}
var _content_light_config: Dictionary = {}
var _attack_animation_variants: Array[String] = []
var _attack_variant_bag: Array[String] = []
var _last_attack_animation := ""
var _avoid_immediate_attack_repeat := true


func _load_player_tuning() -> void:
	super._load_player_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	character_id = str(tuning.get("character_id", character_id))
	_content_visual_scale = clampf(float(tuning.get("visual_scale", 1.0)), 0.1, 8.0)
	_content_visual_offset = Vector2(
		float(tuning.get("visual_offset_x", 0.0)),
		float(tuning.get("visual_offset_y", 0.0))
	)
	_content_depth_offset_y = float(tuning.get("depth_sort_offset_y", 0.0))
	var shadow_value: Variant = tuning.get("shadow", {})
	_content_shadow_config = (shadow_value as Dictionary).duplicate(true) if shadow_value is Dictionary else {}
	var light_value: Variant = tuning.get("light", {})
	_content_light_config = (light_value as Dictionary).duplicate(true) if light_value is Dictionary else {}
	_content_character_side_view = false
	_attack_animation_variants.clear()
	_attack_variant_bag.clear()
	_last_attack_animation = ""
	if content_db.has_method("has_character") and content_db.has_character(character_id):
		var character_data: Dictionary = content_db.get_character(character_id)
		_content_character_side_view = str(character_data.get("orientation_mode", "top_down")) == "side_view"
		_avoid_immediate_attack_repeat = bool(character_data.get("avoid_immediate_attack_repeat", true))
		var variants_value: Variant = character_data.get("attack_animation_variants", [])
		if variants_value is Array:
			for variant in variants_value as Array:
				var clean_variant := str(variant).strip_edges()
				if not clean_variant.is_empty():
					_attack_animation_variants.append(clean_variant)


func _setup_character_visual() -> void:
	super._setup_character_visual()
	_apply_player_visual_tuning()
	_apply_player_light_tuning()
	_apply_player_directional_shadow()
	_update_world_depth()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_world_depth()


func _apply_player_visual_tuning() -> void:
	var tuned_scale := Vector2.ONE * _content_visual_scale
	if animated_sprite != null:
		animated_sprite.scale = tuned_scale
		animated_sprite.position = _content_visual_offset
	if body_visual is Node2D:
		var body_node := body_visual as Node2D
		body_node.scale = tuned_scale
		body_node.position = _content_visual_offset


func _apply_player_light_tuning() -> void:
	var light := get_node_or_null("NightLight") as Node2D
	if light == null:
		return
	var enabled := bool(_content_light_config.get("enabled", true))
	light.visible = enabled
	_set_player_light_property(light, "visual_enabled", enabled and bool(_content_light_config.get("visual_aura_enabled", true)))
	_set_player_light_property(light, "visual_uses_day_night_multiplier", true)
	_set_player_light_property(light, "use_point_light", enabled)
	_set_player_light_property(light, "glow_color", _player_light_color(_content_light_config.get("color", "#AFCBFFFF"), Color(0.69, 0.80, 1.0, 1.0)))
	_set_player_light_property(light, "intensity", maxf(float(_content_light_config.get("aura_intensity", 0.75)), 0.0))
	_set_player_light_property(light, "alpha", clampf(float(_content_light_config.get("aura_alpha", 0.30)), 0.0, 1.0))
	_set_player_light_property(light, "scale_multiplier", maxf(float(_content_light_config.get("aura_scale", 0.44)), 0.01))
	_set_player_light_property(light, "blur_amount", maxf(float(_content_light_config.get("blur", 1.25)), 0.0))
	_set_player_light_property(light, "point_light_energy", maxf(float(_content_light_config.get("emission", 0.85)), 0.0))
	_set_player_light_property(light, "point_light_scale", maxf(float(_content_light_config.get("radius_scale", 1.20)), 0.05))
	_set_player_light_property(light, "day_light_multiplier", maxf(float(_content_light_config.get("day_multiplier", 0.0)), 0.0))
	_set_player_light_property(light, "night_light_multiplier", maxf(float(_content_light_config.get("night_multiplier", 1.0)), 0.0))
	_set_player_light_property(light, "light_uses_aura_alpha", false)
	light.position = _player_light_vector(_content_light_config.get("offset", {}), Vector2(0.0, 6.0))
	if light.has_method("refresh_from_config"):
		light.call("refresh_from_config")


func _set_player_light_property(target: Object, property_name: StringName, value: Variant) -> void:
	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return


func _player_light_vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _player_light_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)


func _apply_player_directional_shadow() -> void:
	var visual_size := DirectionalShadowRuntime.estimate_target_visual_size(self)
	var foot_offset := DirectionalShadowRuntime.estimate_target_foot_offset(self)
	if animated_sprite != null and animated_sprite.visible:
		visual_size = WorldDepthRuntime.get_animated_sprite_visual_size(animated_sprite)
		foot_offset = WorldDepthRuntime.get_animated_sprite_foot_offset(animated_sprite)
	var config := _content_shadow_config.duplicate(true)
	if not config.has("enabled"):
		config["enabled"] = true
	DirectionalShadowRuntime.apply_to_target(self, config, visual_size, foot_offset)


func _update_world_depth() -> void:
	WorldDepthRuntime.apply_node_depth(self, _content_depth_offset_y)


func _play_attack_animation() -> void:
	if not animation_controller.has_any_valid_animation():
		return
	var animation_name := _next_attack_animation_name()
	if animation_name.is_empty() or not animation_controller.play_if_available(animation_name):
		return
	_last_attack_animation = animation_name
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation_name)
	var fps := animated_sprite.sprite_frames.get_animation_speed(animation_name)
	if frame_count <= 0 or fps <= 0.0:
		return
	var native_duration := float(frame_count) / fps
	animated_sprite.speed_scale = clampf(native_duration / maxf(current_attack_cooldown, 0.05), 0.20, 8.0)


func _next_attack_animation_name() -> String:
	var candidates: Array[String] = []
	var configured: Array[String] = _attack_animation_variants.duplicate()
	if configured.is_empty():
		configured.append("attack_{direction}")
	for variant: String in configured:
		var resolved: String = variant.replace("{direction}", last_direction)
		if _has_player_animation(resolved) and not candidates.has(resolved):
			candidates.append(resolved)
	var canonical := "attack_%s" % last_direction
	if candidates.is_empty() and _has_player_animation(canonical):
		candidates.append(canonical)
	if candidates.is_empty():
		return ""

	var valid_bag: Array[String] = []
	for candidate in _attack_variant_bag:
		if candidates.has(candidate):
			valid_bag.append(candidate)
	_attack_variant_bag = valid_bag
	if _attack_variant_bag.is_empty():
		_attack_variant_bag = candidates.duplicate()
		_attack_variant_bag.shuffle()
		if _avoid_immediate_attack_repeat and _attack_variant_bag.size() > 1 and _attack_variant_bag.back() == _last_attack_animation:
			var last_index := _attack_variant_bag.size() - 1
			var replacement_index := 0
			var temporary := _attack_variant_bag[replacement_index]
			_attack_variant_bag[replacement_index] = _attack_variant_bag[last_index]
			_attack_variant_bag[last_index] = temporary
	return _attack_variant_bag.pop_back()


func _start_attack_cycle() -> void:
	_refresh_attack_substats()
	action_state = ActionState.ATTACKING
	_attack_in_progress = true
	attack_elapsed = 0.0
	attack_hit_done = false
	attack_buffer_left = 0.0
	attack_hit_at = maxf(attack_windup_time + attack_hit_time, 0.01)
	attack_total_time = maxf(attack_hit_at + attack_recovery_time, attack_hit_at + 0.04)
	attack_cooldown_left = current_attack_cooldown
	attack_started.emit()
	_play_attack_feedback()
	_play_attack_animation()
	_apply_content_character_flip()


func _start_dash(direction: Vector2) -> void:
	super._start_dash(direction)
	var animation_name := "dash_%s" % last_direction
	if _has_player_animation(animation_name):
		animation_controller.play_if_available(animation_name)
	_apply_content_character_flip()


func _update_movement_animation(input_direction: Vector2) -> void:
	if action_state == ActionState.ATTACKING:
		return
	if input_direction != Vector2.ZERO:
		_update_last_direction(input_direction)
	_apply_content_character_flip()

	if action_state == ActionState.DASHING:
		var dash_name := "dash_%s" % last_direction
		if _has_player_animation(dash_name):
			animation_controller.play_if_available(dash_name)
			return
		animation_controller.play_if_available("walk_%s" % last_direction)
		return

	if input_direction != Vector2.ZERO:
		var locomotion_name := "run_%s" % last_direction if is_running else "walk_%s" % last_direction
		if _has_player_animation(locomotion_name):
			animation_controller.play_if_available(locomotion_name)
			return
		animation_controller.play_if_available("walk_%s" % last_direction)
		return

	animation_controller.play_if_available("idle_%s" % last_direction)


func _has_player_animation(animation_name: String) -> bool:
	return (
		animated_sprite != null
		and animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(animation_name)
		and animated_sprite.sprite_frames.get_frame_count(animation_name) > 0
	)


func _apply_content_character_flip() -> void:
	if animated_sprite == null:
		return
	if not _content_character_side_view:
		animated_sprite.flip_h = false
		return
	if last_direction == "left":
		animated_sprite.flip_h = true
	elif last_direction == "right":
		animated_sprite.flip_h = false


func _perform_attack_hits() -> void:
	var hit_any_target := false
	var item_is_broken := _is_current_hotbar_item_broken()

	for target in _find_nearby_attack_targets("enemy"):
		if _apply_attack_to_enemy(target, item_is_broken):
			hit_any_target = true

	for target in _find_nearby_attack_targets("resource_node"):
		if _apply_attack_to_resource(target, item_is_broken):
			hit_any_target = true

	if hit_any_target:
		_consume_current_item_durability()
