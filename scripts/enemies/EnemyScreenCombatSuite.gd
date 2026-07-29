extends "res://scripts/enemies/EnemyBase.gd"

const DEFAULT_SCREEN_ACTIVATION_MARGIN := 72.0

var attack_contact_frame := 1
var screen_activation_margin := DEFAULT_SCREEN_ACTIVATION_MARGIN


func _load_monster_data() -> void:
	super._load_monster_data()
	var fallback_frame := 1
	match monster_id:
		"slime":
			fallback_frame = 5
		"skeleton":
			fallback_frame = 2
	attack_contact_frame = maxi(int(monster_data.get("attack_hit_frame", fallback_frame)), 1)


func _update_movement(delta: float) -> Dictionary:
	if not is_visible_for_activation():
		return {
			"velocity": Vector2.ZERO,
			"state": "idle",
			"facing_direction": facing_direction,
			"visual_offset": Vector2.ZERO,
		}
	return super._update_movement(delta)


func is_visible_for_activation() -> bool:
	if not is_inside_tree() or not visible:
		return false
	var viewport := get_viewport()
	if viewport == null:
		return true
	var visible_rect := viewport.get_visible_rect().grow(screen_activation_margin)
	var screen_position := viewport.get_canvas_transform() * global_position
	return visible_rect.has_point(screen_position)


func get_attack_contact_frame() -> int:
	return attack_contact_frame


func _attack_player() -> void:
	if _attack_in_progress:
		return

	_attack_in_progress = true
	var animation_duration := _play_forced_animation("attack")
	attack_started.emit()
	_play_attack_tell()
	await _wait_for_attack_contact_frame(animation_duration)

	if not is_inside_tree() or is_dead:
		_attack_in_progress = false
		return

	# Contact damage is evaluated on the authored animation frame, not during the
	# preparation pose. Moving out of the damage area before that frame avoids it.
	if player_in_contact and _can_damage_player():
		var target_data := {}
		if player.has_method("_get_combat_data"):
			target_data = player.call("_get_combat_data")
		var combat_result := combat_calculator.calculate_damage(get_combat_data(), target_data)
		attack_hit_frame.emit()
		if player.has_method("apply_combat_result"):
			player.call("apply_combat_result", combat_result)
		else:
			player.take_damage(int(combat_result.get("damage", damage)))

	await _wait_attack_step(maxf(attack_recovery_time, 0.01))
	attack_finished.emit()
	_attack_in_progress = false


func _wait_for_attack_contact_frame(animation_duration: float) -> void:
	var sprite := _active_monster_sprite()
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
		await _wait_attack_step(maxf(attack_windup_time + attack_hit_time, 0.0))
		return

	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		await _wait_attack_step(maxf(attack_windup_time + attack_hit_time, 0.0))
		return
	var target_frame_index := clampi(attack_contact_frame - 1, 0, frame_count - 1)
	var timeout_seconds := maxf(animation_duration + 0.25, attack_windup_time + attack_hit_time + 0.10)
	var deadline_msec := Time.get_ticks_msec() + int(ceil(timeout_seconds * 1000.0))

	while is_inside_tree() and not is_dead and _attack_in_progress:
		if sprite == null or not is_instance_valid(sprite):
			return
		if sprite.frame >= target_frame_index:
			return
		if Time.get_ticks_msec() >= deadline_msec:
			return
		await get_tree().process_frame


func _active_monster_sprite() -> AnimatedSprite2D:
	var scene_sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if scene_sprite != null and scene_sprite.visible:
		return scene_sprite
	var generated_sprite := find_child("MonsterSprite", true, false) as AnimatedSprite2D
	if generated_sprite != null and generated_sprite.visible:
		return generated_sprite
	return scene_sprite if scene_sprite != null else generated_sprite
