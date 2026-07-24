extends "res://scripts/player/PlayerShaderSuite.gd"

const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")


var _content_character_side_view := false
var _content_visual_scale := 1.0
var _content_visual_offset := Vector2.ZERO
var _content_depth_offset_y := 0.0
var _content_shadow_config: Dictionary = {}
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
	var configured := _attack_animation_variants.duplicate()
	if configured.is_empty():
		configured.append("attack_{direction}")
	for variant in configured:
		var resolved := variant.replace("{direction}", last_direction)
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
		if not _current_item_can_hit("can_hit_monsters", true):
			continue
		_attack_enemy(target)
		if not item_is_broken:
			hit_any_target = true

	for target in _find_nearby_attack_targets("resource_node"):
		if not _current_item_can_hit("can_hit_resources", true):
			continue
		_attack_resource(target)
		if not item_is_broken:
			hit_any_target = true

	if not hit_any_target:
		var sfx_manager := get_node_or_null("/root/SFXManager")
		if sfx_manager != null and sfx_manager.has_method("play_profile"):
			sfx_manager.play_profile("player_attack_swing", global_position)
