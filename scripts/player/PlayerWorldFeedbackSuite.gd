extends "res://scripts/player/PlayerShaderSuite.gd"


var _content_character_side_view := false


func _load_player_tuning() -> void:
	super._load_player_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	character_id = str(tuning.get("character_id", character_id))
	_content_character_side_view = false
	if content_db.has_method("has_character") and content_db.has_character(character_id):
		var character_data: Dictionary = content_db.get_character(character_id)
		_content_character_side_view = str(character_data.get("orientation_mode", "top_down")) == "side_view"


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
