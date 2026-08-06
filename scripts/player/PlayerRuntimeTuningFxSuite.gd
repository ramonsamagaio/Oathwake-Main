extends "res://scripts/player/WIPPlayer.gd"

signal stamina_changed(current_stamina: float, maximum_stamina: float)

const FINAL_DASH_SMOKE_SCENE := preload("res://scenes/effects/SmokePuff.tscn")
const RUN_SMOKE_PUFF_SCENE := preload("res://scenes/effects/RunSmokePuff.tscn")
const DEFAULT_DASH_STAMINA_COST := 10.0
const DEFAULT_MAX_STAMINA := 100.0
const DEFAULT_STAMINA_REGEN_PER_SECOND := 30.0
const DEFAULT_STAMINA_REGEN_DELAY_SECONDS := 0.65

@export_group("Final Dash FX")
@export_range(0.05, 8.0, 0.05) var dash_smoke_scale := 0.55

@export_group("Stamina")
@export_range(1.0, 1000.0, 1.0) var max_stamina := DEFAULT_MAX_STAMINA
@export_range(0.0, 1000.0, 1.0) var dash_stamina_cost := DEFAULT_DASH_STAMINA_COST
@export_range(0.0, 500.0, 0.5) var stamina_regeneration_per_second := DEFAULT_STAMINA_REGEN_PER_SECOND
@export_range(0.0, 10.0, 0.05) var stamina_regeneration_delay_seconds := DEFAULT_STAMINA_REGEN_DELAY_SECONDS

var current_stamina := DEFAULT_MAX_STAMINA
var stamina_regeneration_delay_left := 0.0


func _ready() -> void:
	super._ready()
	_set_stamina(max_stamina, true)
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
		dash_stamina_cost = clampf(
			float(tuning.get("dash_stamina_cost", DEFAULT_DASH_STAMINA_COST)),
			0.0,
			max_stamina
		)
		stamina_regeneration_per_second = maxf(
			float(tuning.get("stamina_regeneration_per_second", DEFAULT_STAMINA_REGEN_PER_SECOND)),
			0.0
		)
		stamina_regeneration_delay_seconds = maxf(
			float(tuning.get("stamina_regeneration_delay_seconds", DEFAULT_STAMINA_REGEN_DELAY_SECONDS)),
			0.0
		)
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	stamina_regeneration_delay_left = minf(stamina_regeneration_delay_left, stamina_regeneration_delay_seconds)
	_suppress_inherited_dash_smoke_repeats()
	set_meta("parry_stun_seconds", parry_stun_seconds)
	set_meta("dash_smoke_scale", dash_smoke_scale)
	_publish_stamina_contract()
	stamina_changed.emit(current_stamina, max_stamina)


func _start_dash(direction: Vector2) -> void:
	var previous_state := action_state
	_suppress_inherited_dash_smoke_repeats()
	if previous_state != ActionState.DASHING and current_stamina + 0.001 < dash_stamina_cost:
		dash_buffered = false
		set_meta("last_dash_rejected_for_stamina", true)
		return

	super._start_dash(direction)
	if previous_state == ActionState.DASHING or action_state != ActionState.DASHING:
		return

	set_meta("last_dash_rejected_for_stamina", false)
	_set_stamina(current_stamina - dash_stamina_cost)
	stamina_regeneration_delay_left = stamina_regeneration_delay_seconds
	set_meta("stamina_regeneration_delay_left", stamina_regeneration_delay_left)
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
	# Running and run-stop feedback keep the lightweight procedural puff. The
	# authored sprite-sheet smoke remains exclusive to lateral dashes.
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
	if delta <= 0.0:
		return
	var regeneration_delta := delta
	if stamina_regeneration_delay_left > 0.0:
		var blocked_delta := minf(regeneration_delta, stamina_regeneration_delay_left)
		stamina_regeneration_delay_left = maxf(stamina_regeneration_delay_left - blocked_delta, 0.0)
		regeneration_delta -= blocked_delta
		set_meta("stamina_regeneration_delay_left", stamina_regeneration_delay_left)
	if regeneration_delta <= 0.0 or current_stamina >= max_stamina:
		return
	if action_state == ActionState.DASHING:
		return
	_set_stamina(current_stamina + stamina_regeneration_per_second * regeneration_delta)


func _set_stamina(value: float, force_emit := false) -> void:
	var resolved := clampf(value, 0.0, max_stamina)
	var changed := not is_equal_approx(resolved, current_stamina)
	current_stamina = resolved
	set_meta("current_stamina", current_stamina)
	set_meta("max_stamina", max_stamina)
	if changed or force_emit:
		stamina_changed.emit(current_stamina, max_stamina)


func _publish_stamina_contract() -> void:
	set_meta("current_stamina", current_stamina)
	set_meta("max_stamina", max_stamina)
	set_meta("dash_stamina_cost", dash_stamina_cost)
	set_meta("stamina_regeneration_per_second", stamina_regeneration_per_second)
	set_meta("stamina_regeneration_delay_seconds", stamina_regeneration_delay_seconds)
	set_meta("stamina_regeneration_delay_left", stamina_regeneration_delay_left)


func _finish_death_respawn() -> void:
	super._finish_death_respawn()
	stamina_regeneration_delay_left = 0.0
	_set_stamina(max_stamina, true)
	_publish_stamina_contract()


func _perform_parry(attacker: Node) -> void:
	super._perform_parry(attacker)
	var sfx_manager := get_node_or_null("/root/SFXManager")
	var played := false
	var audio_parent := get_parent()
	if audio_parent == null:
		audio_parent = self
	if sfx_manager != null and sfx_manager.has_method("play_profile"):
		played = bool(sfx_manager.call("play_profile", "player_parry", global_position, audio_parent))
	set_meta("last_parry_sfx_requested", true)
	set_meta("last_parry_sfx_played", played)


func get_current_stamina() -> float:
	return current_stamina


func get_max_stamina() -> float:
	return max_stamina


func get_dash_stamina_cost() -> float:
	return dash_stamina_cost


func get_stamina_regeneration_per_second() -> float:
	return stamina_regeneration_per_second


func get_stamina_regeneration_delay_seconds() -> float:
	return stamina_regeneration_delay_seconds


func get_stamina_regeneration_delay_left() -> float:
	return stamina_regeneration_delay_left
