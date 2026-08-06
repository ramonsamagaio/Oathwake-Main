extends "res://scripts/player/PlayerLifeAnimationSuite.gd"

const ParryEffectScene := preload("res://scenes/effects/ParryEffect.tscn")
const ButterflyPetScene := preload("res://scenes/pets/ButterflyPet.tscn")
const StunEffectScene := preload("res://scenes/effects/StunEffect.tscn")
const TRINKET_SLOT_ID := "trinket"

@export_group("Guard")
@export_range(0.0, 1.0, 0.01) var block_damage_multiplier := 0.35
@export_range(0.05, 0.50, 0.01) var parry_window_seconds := 0.18
@export_range(0.10, 3.0, 0.05) var parry_stun_seconds := 1.0

@export_group("Stun")
@export_range(0.05, 5.0, 0.05) var default_stun_seconds := 0.50

var _blocking := false
var _parry_window_left := 0.0
var _stun_time_left := 0.0
var _stun_effect: Node2D
var _active_pet: Node2D
var _equipped_pet_item_id := ""
var _bound_equipment_system: Object


func _ready() -> void:
	super._ready()
	call_deferred("_bind_pet_equipment")


func _exit_tree() -> void:
	_unbind_pet_equipment()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if not _is_storage_open() and not _is_crafting_open() and not _is_build_mode_enabled():
				start_block()
				get_viewport().set_input_as_handled()
		else:
			stop_block()
			get_viewport().set_input_as_handled()
		return

	if is_stunned() or _blocking:
		return
	super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	if _is_life_animation_locked():
		super._physics_process(delta)
		return

	var was_stunned := _stun_time_left > 0.0
	_update_guard_timers(delta)
	if was_stunned or _blocking or action_state == ActionState.ATTACKING:
		_tick_locked_combat_timers(delta)
		velocity = Vector2.ZERO
		is_running = false
		was_running = false
		run_slide_timer = 0.0
		_footstep_timer = 0.0
		if _footstep_player != null:
			_footstep_player.stop()
		if action_state == ActionState.ATTACKING and not was_stunned and not _blocking:
			_update_attack(delta)
		elif was_stunned:
			animation_controller.play_if_available("idle_%s" % last_direction)
		_update_world_depth()
		return

	super._physics_process(delta)


func _update_guard_timers(delta: float) -> void:
	_parry_window_left = maxf(_parry_window_left - delta, 0.0)
	_stun_time_left = maxf(_stun_time_left - delta, 0.0)
	if _stun_time_left <= 0.0 and bool(get_meta("combat_stunned", false)):
		set_meta("combat_stunned", false)
		modulate = Color.WHITE
		_remove_stun_effect()


func _tick_locked_combat_timers(delta: float) -> void:
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	attack_buffer_left = maxf(attack_buffer_left - delta, 0.0)
	_update_invulnerability(delta)


func start_block() -> bool:
	if _blocking or is_stunned() or _is_life_animation_locked():
		return false
	if action_state != ActionState.FREE:
		return false
	_blocking = true
	_parry_window_left = parry_window_seconds
	attack_buffer_left = 0.0
	dash_buffered = false
	velocity = Vector2.ZERO
	set_meta("combat_blocking", true)
	return true


func stop_block() -> void:
	_blocking = false
	_parry_window_left = 0.0
	set_meta("combat_blocking", false)


func is_blocking() -> bool:
	return _blocking


func is_parry_window_active() -> bool:
	return _blocking and _parry_window_left > 0.0


func apply_stun(duration := -1.0, _source: Node = null) -> void:
	if _death_animation_active:
		return
	var resolved_duration := default_stun_seconds if float(duration) <= 0.0 else float(duration)
	_stun_time_left = maxf(_stun_time_left, resolved_duration)
	stop_block()
	_cancel_current_action_for_life_animation()
	velocity = Vector2.ZERO
	set_meta("combat_stunned", true)
	modulate = Color(0.78, 0.86, 1.0, 1.0)
	_ensure_stun_effect()
	FloatingCombatTextSpawner.show_text("STUN", global_position + Vector2(0, -34), Color(0.72, 0.88, 1.0, 1.0), false, "damage_number")


func _ensure_stun_effect() -> void:
	if _stun_effect != null and is_instance_valid(_stun_effect):
		return
	_stun_effect = StunEffectScene.instantiate() as Node2D
	add_child(_stun_effect)
	_stun_effect.position = Vector2(0.0, -44.0)
	_stun_effect.z_index = 20


func _remove_stun_effect() -> void:
	if _stun_effect != null and is_instance_valid(_stun_effect):
		_stun_effect.queue_free()
	_stun_effect = null


func is_stunned() -> bool:
	return _stun_time_left > 0.0


func get_stun_time_left() -> float:
	return _stun_time_left


func is_combat_movement_locked() -> bool:
	return is_stunned() or _blocking or action_state == ActionState.ATTACKING or _is_life_animation_locked()


func _attack() -> void:
	if is_stunned() or _blocking:
		return
	super._attack()


func _start_attack_cycle() -> void:
	if is_stunned() or _blocking:
		return
	super._start_attack_cycle()


func _start_dash(direction: Vector2) -> void:
	if is_stunned() or _blocking:
		return
	super._start_dash(direction)


func take_damage(amount: int) -> void:
	var resolved_amount := amount
	if _blocking and amount > 0:
		resolved_amount = maxi(int(round(float(amount) * block_damage_multiplier)), 1)
	super.take_damage(resolved_amount)


func apply_combat_result(combat_result: Dictionary) -> void:
	if bool(combat_result.get("miss", false)):
		super.apply_combat_result(combat_result)
		return

	if _blocking:
		var source_value: Variant = combat_result.get("source", null)
		var source: Node = null
		if source_value is Node:
			source = source_value as Node
		if is_parry_window_active() and source != null and is_instance_valid(source) and source.has_method("apply_stun"):
			_perform_parry(source)
			return

		var blocked_result := combat_result.duplicate(true)
		var incoming_damage := float(blocked_result.get("damage", 0.0))
		blocked_result["damage"] = maxf(round(incoming_damage * block_damage_multiplier), 1.0)
		super.apply_combat_result(blocked_result)
		return

	super.apply_combat_result(combat_result)


func _perform_parry(attacker: Node) -> void:
	_parry_window_left = 0.0
	attacker.call("apply_stun", parry_stun_seconds, self)
	_spawn_parry_effect()
	FloatingCombatTextSpawner.show_text("PARRY", global_position + Vector2(0, -38), Color(1.0, 0.93, 0.58, 1.0), false, "damage_number")
	set_meta("last_parry_success_msec", Time.get_ticks_msec())


func _spawn_parry_effect() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var effect := ParryEffectScene.instantiate()
	parent.add_child(effect)
	if effect is Node2D:
		var effect_node := effect as Node2D
		effect_node.global_position = global_position + Vector2(0, -10)
		effect_node.z_index = z_index + 8


func _cancel_current_action_for_life_animation() -> void:
	stop_block()
	super._cancel_current_action_for_life_animation()


func _bind_pet_equipment() -> void:
	var equipment_system: Object = _get_equipment_system()
	if equipment_system == null:
		return
	if _bound_equipment_system == equipment_system:
		refresh_equipped_pet()
		return
	_unbind_pet_equipment()
	_bound_equipment_system = equipment_system
	var callback := Callable(self, "refresh_equipped_pet")
	if equipment_system.has_signal("changed") and not equipment_system.is_connected("changed", callback):
		equipment_system.connect("changed", callback)
	refresh_equipped_pet()


func _unbind_pet_equipment() -> void:
	if _bound_equipment_system == null:
		return
	var callback := Callable(self, "refresh_equipped_pet")
	if _bound_equipment_system.has_signal("changed") and _bound_equipment_system.is_connected("changed", callback):
		_bound_equipment_system.disconnect("changed", callback)
	_bound_equipment_system = null


func refresh_equipped_pet() -> void:
	var equipment_system: Object = _get_equipment_system()
	if equipment_system == null or not equipment_system.has_method("get_equipped_slot"):
		_remove_active_pet()
		return
	var slot_data: Dictionary = equipment_system.call("get_equipped_slot", TRINKET_SLOT_ID)
	var item_id := str(slot_data.get("item_id", ""))
	if item_id == _equipped_pet_item_id and _active_pet != null and is_instance_valid(_active_pet):
		return
	_equipped_pet_item_id = item_id
	_remove_active_pet()
	if item_id.is_empty():
		return
	var item_data := _get_item_data(item_id)
	if str(item_data.get("pet_family", "")) != "butterfly":
		return
	var parent := get_parent()
	if parent == null:
		return
	_active_pet = ButterflyPetScene.instantiate() as Node2D
	parent.add_child(_active_pet)
	_active_pet.global_position = global_position + Vector2(-32, -18)
	if _active_pet.has_method("setup"):
		_active_pet.call("setup", self, item_data)
	set_meta("equipped_pet_id", str(item_data.get("pet_id", "")))


func _remove_active_pet() -> void:
	if _active_pet != null and is_instance_valid(_active_pet):
		_active_pet.queue_free()
	_active_pet = null
	set_meta("equipped_pet_id", "")


func get_active_pet() -> Node2D:
	return _active_pet if _active_pet != null and is_instance_valid(_active_pet) else null
