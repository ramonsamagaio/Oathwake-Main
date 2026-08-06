extends "res://scripts/player/WIPPlayer.gd"

signal stamina_changed(current_stamina: float, maximum_stamina: float)

const FINAL_DASH_SMOKE_SCENE := preload("res://scenes/effects/SmokePuff.tscn")
const RUN_SMOKE_PUFF_SCENE := preload("res://scenes/effects/RunSmokePuff.tscn")
const DASH_STAMINA_COST := 10.0
const DEFAULT_MAX_STAMINA := 100.0
const DEFAULT_STAMINA_REGEN_PER_SECOND := 30.0

@export_group("Final Dash FX")
@export_range(0.05, 8.0, 0.05) var dash_smoke_scale := 0.55

@export_group("Stamina")
@export_range(1.0, 1000.0, 1.0) var max_stamina := DEFAULT_MAX_STAMINA
@export_range(0.0, 500.0, 0.5) var stamina_regeneration_per_second := DEFAULT_STAMINA_REGEN_PER_SECOND

var current_stamina := DEFAULT_MAX_STAMINA


func _ready() -> void:
	super._ready()
	_set_stamina(max_stamina)
	_publish_stamina_contract()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_regenerate_stamina(delta)


func _load_player_tuning() -> void:
	super._load_player_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_player_tuning"):
		var tuning: Dictionary = content_db.get_player_tuning("default")
		parry_stun_seconds = maxf(float(tuning.get("parry_stun_seconds", parry_stun_seconds)), 0.05)
		dash_smoke_scale = maxf(float(tuning.get("dash_smoke_scale", dash_smoke_scale)), 0.05)
		max_stamina = maxf(float(tuning.get("max_stamina", DEFAULT_MAX_STAMINA)), 1.0)
		stamina_regeneration_per_second = maxf(
			float(tuning.get("stamina_regeneration_per_second", DEFAULT_STAMINA_REGEN_PER_SECOND)),
			0.0
		)
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	_suppress_inherited_dash_smoke_repeats()
	set_meta("parry_stun_seconds", parry_stun_seconds)
	set_meta("dash_smoke_scale", dash_smoke_scale)
	_publish_stamina_contract()


func _start_dash(direction: Vector2) -> void:
	var previous_state := action_state
	_suppress_inherited_dash_smoke_repeats()
	if previous_state != ActionState.DASHING and current_stamina + 0.001 < DASH_STAMINA_COST:
		dash_buffered = false
		set_meta("last_dash_rejected_for_stamina", true)
		return

	super._start_dash(direction)
	if previous_state == ActionState.DASHING or action_state != ActionState.DASHING:
		return

	set_meta("last_dash_rejected_for_stamina", false)
	_set_stamina(current_stamina - DASH_STAMINA_COST)
	if _is_lateral_dash():
		_spawn_tuned_dash_smoke_once(_dash_horizontal_facing())
	else:
		set_meta("dash_smoke_skipped_for_vertical_dash", true)


func _suppress_inherited_dash_smoke_repeats() -> void:
	dash_smoke_start_count = 0
	dash_smoke_end_count = 0
	dash_smoke_interval = maxf(dash_duration + 1.0, 1.0)


func _is_lateral_dash() -> bool:
	return last_direction == "left" or last_direction == "right"


func _dash_horizontal_facing() -> String:
	if dash_direction.x < -0.001:
		return "left"
	if dash_direction.x > 0.001:
		return "right"
	return "left" if last_direction == "left" else "right"


func _spawn_tuned_dash_smoke_once(relative_facing: String) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var puff := FINAL_DASH_SMOKE_SCENE.instantiate()
	if puff == null:
		return
	puff.set("use_content_db_profile", false)
	puff.set("puff_scale", dash_smoke_scale)
	puff.set("facing", relative_facing)
	parent.add_child(puff)
	if puff is Node2D:
		var puff_node := puff as Node2D
		puff_node.global_position = global_position + Vector2(0.0, 12.0) - dash_direction * 4.0
		puff_node.z_index = z_index - 1
		puff_node.set_meta("dash_smoke_single_emission", true)
		puff_node.set_meta("dash_smoke_relative_facing", relative_facing)
	set_meta("last_dash_smoke_facing", relative_facing)
	set_meta("dash_smoke_skipped_for_vertical_dash", false)


func _spawn_smoke_puff() -> void:
	# Running and run-stop feedback keep the earlier lightweight Godot puff.
	# The authored sprite-sheet smoke is reserved exclusively for lateral dashes.
	if not smoke_puff_enabled:
		return
	var parent := get_parent()
	if parent == null:
		return
	var puff := RUN_SMOKE_PUFF_SCENE.instantiate()
	if puff == null:
		return
	parent.add_child(puff)
	if puff is Node2D:
		var puff_node := puff as Node2D
		var foot_offset := Vector2(0.0, 12.0)
		var side_jitter := Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
		puff_node.global_position = global_position + foot_offset + side_jitter
		puff_node.z_index = z_index - 1
		puff_node.set_meta("run_smoke_emission", true)


func _regenerate_stamina(delta: float) -> void:
	if delta <= 0.0 or current_stamina >= max_stamina:
		return
	if action_state == ActionState.DASHING:
		return
	_set_stamina(current_stamina + stamina_regeneration_per_second * delta)


func _set_stamina(value: float) -> void:
	var resolved := clampf(value, 0.0, max_stamina)
	if is_equal_approx(resolved, current_stamina):
		current_stamina = resolved
		return
	current_stamina = resolved
	stamina_changed.emit(current_stamina, max_stamina)
	set_meta("current_stamina", current_stamina)


func _publish_stamina_contract() -> void:
	set_meta("current_stamina", current_stamina)
	set_meta("max_stamina", max_stamina)
	set_meta("dash_stamina_cost", DASH_STAMINA_COST)
	set_meta("stamina_regeneration_per_second", stamina_regeneration_per_second)


func _finish_death_respawn() -> void:
	super._finish_death_respawn()
	_set_stamina(max_stamina)


func get_current_stamina() -> float:
	return current_stamina


func get_max_stamina() -> float:
	return max_stamina


func get_dash_stamina_cost() -> float:
	return DASH_STAMINA_COST


func get_stamina_regeneration_per_second() -> float:
	return stamina_regeneration_per_second
