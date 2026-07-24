extends "res://scripts/player/PlayerWorldFeedbackSuite.gd"

const DEATH_HOLD_TIME := 0.16
const HURT_FALLBACK_DURATION := 0.18
const DEATH_FALLBACK_DURATION := 0.45

var _hurt_animation_active := false
var _hurt_animation_time_left := 0.0
var _death_animation_active := false
var _death_animation_time_left := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _is_life_animation_locked():
		return
	super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	if _death_animation_active:
		_update_death_animation(delta)
		_update_world_depth()
		return
	if _hurt_animation_active:
		_update_invulnerability(delta)
		_update_hurt_animation(delta)
		_update_world_depth()
		return
	super._physics_process(delta)


func take_damage(amount: int) -> void:
	if _death_animation_active:
		return
	var health_before := health
	super.take_damage(amount)
	if health_before > health and health > 0 and not _death_animation_active:
		_start_hurt_animation()


func apply_combat_result(combat_result: Dictionary) -> void:
	if _death_animation_active:
		return
	var health_before := health
	super.apply_combat_result(combat_result)
	if health_before > health and health > 0 and not _death_animation_active:
		_start_hurt_animation()


func _die() -> void:
	if _death_animation_active:
		return
	_death_animation_active = true
	_hurt_animation_active = false
	_hurt_animation_time_left = 0.0
	_cancel_current_action_for_life_animation()
	invulnerability_time_left = 0.0
	invulnerability_blink_left = 0.0
	invulnerability_blink_on = false
	_set_player_visual_alpha(1.0)
	_apply_content_character_flip()
	_death_animation_time_left = _play_life_animation("death", DEATH_FALLBACK_DURATION) + DEATH_HOLD_TIME


func _start_hurt_animation() -> void:
	if _death_animation_active or not _has_player_animation("hurt"):
		return
	_hurt_animation_active = true
	_cancel_current_action_for_life_animation()
	_apply_content_character_flip()
	_hurt_animation_time_left = _play_life_animation("hurt", HURT_FALLBACK_DURATION)


func _update_hurt_animation(delta: float) -> void:
	velocity = Vector2.ZERO
	_hurt_animation_time_left = maxf(_hurt_animation_time_left - delta, 0.0)
	if _hurt_animation_time_left > 0.0:
		return
	_hurt_animation_active = false
	_restore_idle_after_life_animation()


func _update_death_animation(delta: float) -> void:
	velocity = Vector2.ZERO
	_death_animation_time_left = maxf(_death_animation_time_left - delta, 0.0)
	if _death_animation_time_left > 0.0:
		return
	_finish_death_respawn()


func _finish_death_respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	health_changed.emit(health, max_health)
	_death_animation_active = false
	_death_animation_time_left = 0.0
	attack_cooldown_left = 0.0
	dash_cooldown_left = 0.0
	invulnerability_time_left = 0.0
	invulnerability_blink_left = 0.0
	invulnerability_blink_on = false
	_set_player_visual_alpha(1.0)
	_restore_idle_after_life_animation()


func _play_life_animation(animation_name: String, fallback_duration: float) -> float:
	if animated_sprite != null:
		animated_sprite.speed_scale = 1.0
	if not _has_player_animation(animation_name):
		return fallback_duration
	animation_controller.play_if_available(animation_name)
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return fallback_duration
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation_name)
	var fps := animated_sprite.sprite_frames.get_animation_speed(animation_name)
	if frame_count <= 0 or fps <= 0.0:
		return fallback_duration
	return maxf(float(frame_count) / fps, 0.05)


func _cancel_current_action_for_life_animation() -> void:
	var interrupted_attack := action_state == ActionState.ATTACKING and _attack_in_progress
	action_state = ActionState.FREE
	_attack_in_progress = false
	attack_elapsed = 0.0
	attack_hit_done = false
	attack_buffer_left = 0.0
	dash_buffered = false
	dash_time_left = 0.0
	dash_smoke_timer = 0.0
	velocity = Vector2.ZERO
	is_running = false
	was_running = false
	run_slide_timer = 0.0
	_footstep_timer = 0.0
	if _footstep_player != null:
		_footstep_player.stop()
	if animated_sprite != null:
		animated_sprite.speed_scale = 1.0
	if interrupted_attack:
		attack_finished.emit()


func _restore_idle_after_life_animation() -> void:
	if animated_sprite != null:
		animated_sprite.speed_scale = 1.0
	_apply_content_character_flip()
	animation_controller.play_if_available("idle_%s" % last_direction)


func _is_life_animation_locked() -> bool:
	return _hurt_animation_active or _death_animation_active


func is_hurt_animation_active() -> bool:
	return _hurt_animation_active


func is_death_animation_active() -> bool:
	return _death_animation_active


func _start_attack_cycle() -> void:
	if _is_life_animation_locked():
		return
	super._start_attack_cycle()


func _start_dash(direction: Vector2) -> void:
	if _is_life_animation_locked():
		return
	super._start_dash(direction)


func _update_movement_animation(input_direction: Vector2) -> void:
	if _is_life_animation_locked():
		return
	super._update_movement_animation(input_direction)
