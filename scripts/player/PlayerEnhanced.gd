extends "res://scripts/Player.gd"

const HitFlashOverlayScript := preload("res://scripts/effects/HitFlashOverlay.gd")

enum ActionState {
	FREE,
	ATTACKING,
	DASHING,
}

@export var dash_speed: float = 430.0
@export var dash_duration: float = 0.14
@export var dash_cooldown: float = 0.34
@export_range(0.01, 0.20, 0.005) var dash_smoke_interval: float = 0.035
@export_range(0, 8, 1) var dash_smoke_start_count: int = 2
@export_range(0, 8, 1) var dash_smoke_end_count: int = 2
@export var attack_buffer_window: float = 0.32
@export var invulnerability_blink_interval: float = 0.09

var action_state: ActionState = ActionState.FREE
var attack_cooldown_left := 0.0
var attack_buffer_left := 0.0
var attack_elapsed := 0.0
var attack_hit_at := 0.0
var attack_total_time := 0.0
var attack_hit_done := false
var current_attack_cooldown := 0.6
var dash_cooldown_left := 0.0
var dash_time_left := 0.0
var dash_direction := Vector2.DOWN
var dash_glint_timer := 0.0
var dash_smoke_timer := 0.0
var dash_buffered := false
var invulnerability_time_left := 0.0
var invulnerability_blink_left := 0.0
var invulnerability_blink_on := false


func _load_player_tuning() -> void:
	super._load_player_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	dash_speed = float(tuning.get("dash_speed", dash_speed))
	dash_duration = float(tuning.get("dash_duration", dash_duration))
	dash_cooldown = float(tuning.get("dash_cooldown", dash_cooldown))
	dash_smoke_interval = maxf(float(tuning.get("dash_smoke_interval", dash_smoke_interval)), 0.01)
	dash_smoke_start_count = maxi(int(tuning.get("dash_smoke_start_count", dash_smoke_start_count)), 0)
	dash_smoke_end_count = maxi(int(tuning.get("dash_smoke_end_count", dash_smoke_end_count)), 0)
	attack_buffer_window = float(tuning.get("attack_buffer_window", attack_buffer_window))
	invulnerability_blink_interval = float(tuning.get("invulnerability_blink_interval", invulnerability_blink_interval))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		take_damage(10)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_CTRL or event.physical_keycode == KEY_CTRL):
		if not _is_storage_open() and not _is_crafting_open():
			_try_dash()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if _is_storage_open() or _is_crafting_open():
			return
		if _try_interact_with_nearby_npc():
			get_viewport().set_input_as_handled()
			return
		if _try_interact_with_nearby_storage():
			get_viewport().set_input_as_handled()
			return
		if _try_interact_with_nearby_building():
			get_viewport().set_input_as_handled()
			return
		if _try_interact_with_nearby_workbench():
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _is_storage_open() or _is_crafting_open():
			return
		_attack()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_storage_open() or _is_crafting_open() or _is_build_mode_enabled():
			return
		_attack()
		get_viewport().set_input_as_handled()


func _try_interact_with_nearby_building() -> bool:
	var nearest: Node2D = null
	var nearest_distance := 64.0
	for candidate in get_tree().get_nodes_in_group("interactable_building"):
		if not candidate is Node2D or not candidate.has_method("try_interact_with_player"):
			continue
		var node := candidate as Node2D
		var distance := global_position.distance_to(node.global_position)
		if distance <= nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest != null and bool(nearest.call("try_interact_with_player", self))


func _physics_process(delta: float) -> void:
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	attack_buffer_left = maxf(attack_buffer_left - delta, 0.0)
	_update_invulnerability(delta)

	if action_state == ActionState.DASHING:
		_update_dash(delta)
		return

	super._physics_process(delta)

	if action_state == ActionState.ATTACKING:
		_update_attack(delta)
	elif attack_buffer_left > 0.0 and attack_cooldown_left <= 0.0:
		_start_attack_cycle()
	elif dash_buffered and dash_cooldown_left <= 0.0:
		dash_buffered = false
		_start_dash(_get_dash_input_direction())


func _attack() -> void:
	if action_state == ActionState.DASHING:
		attack_buffer_left = attack_buffer_window
		return
	if action_state == ActionState.ATTACKING:
		attack_buffer_left = attack_buffer_window
		if attack_hit_done and attack_cooldown_left <= 0.0:
			_start_attack_cycle()
		return
	if attack_cooldown_left > 0.0:
		attack_buffer_left = attack_buffer_window
		return
	_start_attack_cycle()


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
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_profile"):
		sfx_manager.play_profile("player_attack_swing", global_position)


func _update_attack(delta: float) -> void:
	attack_elapsed += delta
	if not attack_hit_done and attack_elapsed >= attack_hit_at:
		attack_hit_done = true
		_perform_attack_hits()

	if attack_hit_done and attack_buffer_left > 0.0 and attack_cooldown_left <= 0.0:
		_start_attack_cycle()
		return

	if attack_elapsed < attack_total_time:
		return
	_finish_attack_cycle()
	if dash_buffered and dash_cooldown_left <= 0.0:
		dash_buffered = false
		_start_dash(_get_dash_input_direction())
	elif attack_buffer_left > 0.0 and attack_cooldown_left <= 0.0:
		_start_attack_cycle()


func _finish_attack_cycle() -> void:
	if action_state != ActionState.ATTACKING:
		return
	action_state = ActionState.FREE
	_attack_in_progress = false
	attack_finished.emit()
	if animated_sprite != null:
		animated_sprite.speed_scale = 1.0


func _refresh_attack_substats() -> void:
	var equipment_system = _get_equipment_system()
	var actor_data := player_stats_resolver.get_total_player_data(self, equipment_system)
	var held_item_data := _get_current_held_item_data()
	var derived := combat_calculator.calculate_derived_stats(actor_data, held_item_data)
	current_attack_cooldown = maxf(float(derived.get("attack_cooldown", 0.6)), 0.05)
	_get_combat_data()
	if not attack_timing_enabled:
		attack_windup_time = 0.04
		attack_hit_time = 0.02
		attack_recovery_time = maxf(current_attack_cooldown - 0.06, 0.06)


func _play_attack_animation() -> void:
	if not animation_controller.has_any_valid_animation():
		return
	var animation_name := "attack_%s" % last_direction
	if not animation_controller.play_if_available(animation_name):
		return
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation_name)
	var fps := animated_sprite.sprite_frames.get_animation_speed(animation_name)
	if frame_count <= 0 or fps <= 0.0:
		return
	var native_duration := float(frame_count) / fps
	animated_sprite.speed_scale = clampf(native_duration / maxf(current_attack_cooldown, 0.05), 0.20, 8.0)


func _update_movement_animation(input_direction: Vector2) -> void:
	if action_state == ActionState.ATTACKING:
		return
	if action_state == ActionState.DASHING:
		animation_controller.play_if_available("walk_%s" % last_direction)
		return
	super._update_movement_animation(input_direction)


func _try_dash() -> void:
	if dash_cooldown_left > 0.0 or action_state == ActionState.DASHING:
		return
	if action_state == ActionState.ATTACKING:
		if not attack_hit_done:
			dash_buffered = true
			return
		_finish_attack_cycle()
	_start_dash(_get_dash_input_direction())


func _start_dash(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		direction = last_move_direction
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	dash_direction = direction.normalized()
	_update_last_direction(dash_direction)
	action_state = ActionState.DASHING
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown
	dash_glint_timer = 0.0
	dash_smoke_timer = maxf(dash_smoke_interval, 0.01)
	velocity = dash_direction * dash_speed
	_spawn_dash_smoke_burst(dash_smoke_start_count)
	_spawn_dash_glint()
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_profile"):
		sfx_manager.play_profile("player_dash", global_position)


func _update_dash(delta: float) -> void:
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	dash_glint_timer -= delta
	dash_smoke_timer -= delta
	velocity = dash_direction * dash_speed
	move_and_slide()
	if dash_glint_timer <= 0.0:
		dash_glint_timer = 0.045
		_spawn_dash_glint()
	if dash_time_left > 0.0 and dash_smoke_timer <= 0.0:
		dash_smoke_timer = maxf(dash_smoke_interval, 0.01)
		_spawn_smoke_puff()
	if dash_time_left > 0.0:
		return
	action_state = ActionState.FREE
	velocity = dash_direction * minf(run_speed, dash_speed * 0.20)
	_spawn_dash_smoke_burst(dash_smoke_end_count)
	if attack_buffer_left > 0.0 and attack_cooldown_left <= 0.0:
		_start_attack_cycle()


func _spawn_dash_smoke_burst(puff_count: int) -> void:
	for _index in range(maxi(puff_count, 0)):
		_spawn_smoke_puff()


func _get_dash_input_direction() -> Vector2:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	return direction.normalized() if direction != Vector2.ZERO else last_move_direction


func _spawn_dash_glint() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var vfx_profile := _get_default_vfx_profile()
	var count := int(vfx_profile.get("dash_glint_count", 3))
	var alpha := float(vfx_profile.get("dash_glint_alpha", 0.24))
	var lifetime := float(vfx_profile.get("dash_glint_lifetime", 0.12))
	var spread := float(vfx_profile.get("dash_glint_spread", 7.0))
	for index in range(maxi(count, 0)):
		var glint := Polygon2D.new()
		glint.name = "DashGlint"
		glint.z_index = z_index - 1
		glint.color = Color(0.72, 0.88, 1.0, alpha)
		glint.polygon = PackedVector2Array([Vector2(-1, 0), Vector2(0, -1), Vector2(2, 0), Vector2(0, 1)])
		parent.add_child(glint)
		var side := Vector2(-dash_direction.y, dash_direction.x) * randf_range(-spread, spread)
		glint.global_position = global_position - dash_direction * randf_range(3.0, 13.0) + side
		glint.scale = Vector2.ONE * randf_range(0.7, 1.3)
		var tween := glint.create_tween()
		tween.set_parallel(true)
		tween.tween_property(glint, "global_position", glint.global_position - dash_direction * 10.0, lifetime)
		tween.tween_property(glint, "modulate:a", 0.0, lifetime)
		tween.tween_property(glint, "scale", glint.scale * 0.45, lifetime)
		tween.set_parallel(false)
		tween.tween_callback(glint.queue_free)


func take_damage(amount: int) -> void:
	if amount <= 0 or is_invulnerable():
		return
	var health_before := health
	super.take_damage(amount)
	if health_before != health:
		_start_invulnerability()


func apply_combat_result(combat_result: Dictionary) -> void:
	if bool(combat_result.get("miss", false)):
		super.apply_combat_result(combat_result)
		return
	if is_invulnerable():
		return
	var health_before := health
	super.apply_combat_result(combat_result)
	if health_before != health:
		_start_invulnerability()


func _play_hit_flash(_flash_color: Color) -> void:
	var vfx_profile := _get_default_vfx_profile()
	HitFlashOverlayScript.flash_node(self, float(vfx_profile.get("white_hit_flash_duration", 0.08)))
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_hit_for_target"):
		sfx_manager.play_hit_for_target(self, false)


func _start_invulnerability() -> void:
	invulnerability_time_left = get_current_invulnerability_duration()
	invulnerability_blink_left = 0.0
	invulnerability_blink_on = false
	_set_player_visual_alpha(1.0)


func _update_invulnerability(delta: float) -> void:
	if invulnerability_time_left <= 0.0:
		return
	invulnerability_time_left = maxf(invulnerability_time_left - delta, 0.0)
	invulnerability_blink_left -= delta
	if invulnerability_blink_left <= 0.0:
		invulnerability_blink_left = maxf(invulnerability_blink_interval, 0.02)
		invulnerability_blink_on = not invulnerability_blink_on
		_set_player_visual_alpha(0.28 if invulnerability_blink_on else 1.0)
	if invulnerability_time_left <= 0.0:
		invulnerability_blink_on = false
		_set_player_visual_alpha(1.0)


func _set_player_visual_alpha(alpha: float) -> void:
	if animated_sprite != null:
		animated_sprite.modulate.a = alpha
	if body_visual != null:
		body_visual.modulate.a = alpha


func is_invulnerable() -> bool:
	return invulnerability_time_left > 0.0


func get_current_invulnerability_duration() -> float:
	var equipment_system = _get_equipment_system()
	var actor_data := player_stats_resolver.get_total_player_data(self, equipment_system)
	var held_item_data := _get_current_held_item_data()
	var derived := combat_calculator.calculate_derived_stats(actor_data, held_item_data)
	return maxf(float(derived.get("invulnerability_duration", 2.0)), 0.0)


func get_current_attack_cooldown() -> float:
	_refresh_attack_substats()
	return current_attack_cooldown


func get_current_attack_speed() -> float:
	return 1.0 / maxf(get_current_attack_cooldown(), 0.01)


func _get_default_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
