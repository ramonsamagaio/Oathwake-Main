extends "res://scripts/player/WIPPlayer.gd"

const FINAL_DASH_SMOKE_SCENE := preload("res://scenes/effects/SmokePuff.tscn")
const RUN_SMOKE_PUFF_SCENE := preload("res://scenes/effects/RunSmokePuff.tscn")
const DASH_SMOKE_FACING_OPTIONS := ["left", "right"]

@export_group("Final Dash FX")
@export_range(0.05, 8.0, 0.05) var dash_smoke_scale := 0.55
@export_enum("left", "right") var dash_smoke_facing := "right"


func _load_player_tuning() -> void:
	super._load_player_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_player_tuning"):
		var tuning: Dictionary = content_db.get_player_tuning("default")
		parry_stun_seconds = maxf(float(tuning.get("parry_stun_seconds", parry_stun_seconds)), 0.05)
		dash_smoke_scale = maxf(float(tuning.get("dash_smoke_scale", dash_smoke_scale)), 0.05)
		dash_smoke_facing = _normalize_dash_smoke_facing(str(tuning.get("dash_smoke_facing", dash_smoke_facing)))
	_suppress_inherited_dash_smoke_repeats()
	set_meta("parry_stun_seconds", parry_stun_seconds)
	set_meta("dash_smoke_scale", dash_smoke_scale)
	set_meta("dash_smoke_facing", dash_smoke_facing)


func _start_dash(direction: Vector2) -> void:
	var previous_state := action_state
	_suppress_inherited_dash_smoke_repeats()
	super._start_dash(direction)
	if previous_state != ActionState.DASHING and action_state == ActionState.DASHING:
		_spawn_tuned_dash_smoke_once()


func _suppress_inherited_dash_smoke_repeats() -> void:
	dash_smoke_start_count = 0
	dash_smoke_end_count = 0
	dash_smoke_interval = maxf(dash_duration + 1.0, 1.0)


func _spawn_tuned_dash_smoke_once() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var puff := FINAL_DASH_SMOKE_SCENE.instantiate()
	if puff == null:
		return
	puff.set("use_content_db_profile", false)
	puff.set("puff_scale", dash_smoke_scale)
	puff.set("facing", dash_smoke_facing)
	parent.add_child(puff)
	if puff is Node2D:
		var puff_node := puff as Node2D
		puff_node.global_position = global_position + Vector2(0.0, 12.0) - dash_direction * 4.0
		puff_node.z_index = z_index - 1
		puff_node.set_meta("dash_smoke_single_emission", true)
		puff_node.set_meta("dash_smoke_facing", dash_smoke_facing)


func _spawn_smoke_puff() -> void:
	# Running and run-stop feedback keep the earlier lightweight Godot puff.
	# The authored sprite-sheet smoke is reserved exclusively for dash.
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


func _normalize_dash_smoke_facing(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if normalized in DASH_SMOKE_FACING_OPTIONS else "right"
