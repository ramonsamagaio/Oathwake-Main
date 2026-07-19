extends "res://scripts/player/PlayerShaderSuite.gd"


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
