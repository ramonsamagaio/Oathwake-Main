extends "res://scripts/player/PlayerRuntimeTuningFxSuite.gd"

const RigVisualController := preload("res://scripts/player/AlabasterPlayerVisualController.gd")

var _rig_visual := RigVisualController.new()


func _setup_character_visual() -> void:
	super._setup_character_visual()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_character") or not content_db.has_character(character_id):
		return
	var character_data: Dictionary = content_db.get_character(character_id)
	if not _rig_visual.configure(self, character_data, _content_visual_offset, _content_visual_scale):
		return
	_force_rig_visual()
	call_deferred("_configure_rig_night_readability")
	call_deferred("_refresh_player_directional_shadow_source")
	call_deferred("_report_rig_player_ready")


func _report_rig_player_ready() -> void:
	if not _rig_visual.active:
		return
	var data := _rig_visual.summary()
	print("JUNO_PLAYER_RIG_OK character=%s profile=%s animations=%s source=%s" % [
		character_id,
		_rig_visual.profile_id,
		str(data.get("animation_count", "?")),
		str(data.get("animation_bank_source", "?")),
	])


func _configure_rig_night_readability() -> void:
	if not _rig_visual.active:
		return
	if _night_readability_material == null:
		_configure_player_night_readability()
	if _night_readability_material != null:
		_rig_visual.set_material(_night_readability_material)


func _force_rig_visual() -> void:
	if not _rig_visual.active:
		return
	if _rig_visual.rig != null:
		_rig_visual.rig.visible = true
	if animated_sprite != null:
		animated_sprite.visible = false
	if body_visual != null:
		body_visual.visible = false
	if wip_south_sprite != null:
		wip_south_sprite.visible = false


func _set_wip_visual_active(active: bool) -> void:
	if _rig_visual.active:
		super._set_wip_visual_active(false)
		_force_rig_visual()
		return
	super._set_wip_visual_active(active)


func _update_movement_animation(input_direction: Vector2) -> void:
	if not _rig_visual.active:
		super._update_movement_animation(input_direction)
		return
	_force_rig_visual()
	if _is_life_animation_locked() or is_blocking():
		return
	if action_state == ActionState.ATTACKING or action_state == ActionState.DASHING:
		return
	if input_direction != Vector2.ZERO:
		_update_last_direction(input_direction)
		_rig_visual.face(input_direction)
		_rig_visual.play("run" if is_running else "walk")
	else:
		_rig_visual.play("idle")


func _play_attack_animation() -> void:
	if not _rig_visual.active:
		super._play_attack_animation()
		return
	_force_rig_visual()
	_rig_visual.face(_rig_visual.last_facing)
	var native_duration := _rig_visual.duration_for("attack")
	var speed := 1.0
	if native_duration > 0.0:
		speed = clampf(native_duration / maxf(current_attack_cooldown, 0.05), 0.20, 8.0)
	_rig_visual.play("attack", speed)


func _finish_attack_cycle() -> void:
	super._finish_attack_cycle()
	if _rig_visual.active:
		_rig_visual.set_speed(1.0)
		_rig_visual.play("idle")
		_force_rig_visual()


func start_block() -> bool:
	var started := super.start_block()
	if started and _rig_visual.active:
		_force_rig_visual()
		_rig_visual.play("block")
	return started


func stop_block() -> void:
	var was_blocking := is_blocking()
	super.stop_block()
	if was_blocking and _rig_visual.active and not _is_life_animation_locked():
		_rig_visual.set_speed(1.0)
		_rig_visual.play("idle")
		_force_rig_visual()


func _start_dash(direction: Vector2) -> void:
	var was_dashing := action_state == ActionState.DASHING
	super._start_dash(direction)
	if not _rig_visual.active or was_dashing or action_state != ActionState.DASHING:
		return
	if dash_direction != Vector2.ZERO:
		_rig_visual.face(dash_direction)
	var native_duration := _rig_visual.duration_for("dash")
	var speed := 1.0
	if native_duration > 0.0:
		speed = clampf(native_duration / maxf(dash_duration, 0.05), 0.20, 8.0)
	_rig_visual.play("dash", speed)
	_force_rig_visual()


func _has_player_animation(animation_name: String) -> bool:
	if _rig_visual.active and (animation_name == "hurt" or animation_name == "death"):
		return _rig_visual.has_action(animation_name)
	return super._has_player_animation(animation_name)


func _play_life_animation(animation_name: String, fallback_duration: float) -> float:
	if not _rig_visual.active:
		return super._play_life_animation(animation_name, fallback_duration)
	if not _rig_visual.has_action(animation_name):
		return fallback_duration
	_rig_visual.set_speed(1.0)
	_rig_visual.play(animation_name)
	_force_rig_visual()
	var duration := _rig_visual.duration_for(animation_name)
	return maxf(duration, 0.05) if duration > 0.0 else fallback_duration


func _restore_idle_after_life_animation() -> void:
	if not _rig_visual.active:
		super._restore_idle_after_life_animation()
		return
	_rig_visual.set_speed(1.0)
	_rig_visual.play("idle")
	_force_rig_visual()


func _set_player_visual_alpha(alpha: float) -> void:
	super._set_player_visual_alpha(alpha)
	if _rig_visual.active:
		_rig_visual.set_alpha(alpha)


func refresh_alabaster_character_visual() -> void:
	if _rig_visual.active:
		_rig_visual.dispose()
	_setup_character_visual()
	call_deferred("_refresh_player_directional_shadow_source")


func is_alabaster_player_visual_active() -> bool:
	return _rig_visual.active


func get_alabaster_player_rig() -> Node2D:
	return _rig_visual.rig if _rig_visual.active else null
