extends Node

# CI validation branch: runtime bed interaction smoke test.
const FLOOR_MANAGER_PATH := "/root/MultiFloorBuildManager"
const FEEDBACK_UI_PATH := "/root/BuildMenuOverlay"
const HINT_OWNER := "building_interaction"

@export var bed_interaction_distance := 96.0
@export var stair_hint_distance := 104.0

var _floor_manager: Node
var _build_system: Node
var _player: CharacterBody2D
var _main: Node
var _last_hint := ""


func _ready() -> void:
	process_priority = -940
	set_process_unhandled_input(true)
	call_deferred("_resolve_context")


func _process(_delta: float) -> void:
	if not _has_valid_context():
		_resolve_context()
		_clear_hint()
		return
	if bool(_build_system.get("build_mode_enabled")):
		_clear_hint()
		return

	var hint := ""
	if _is_stair_nearby():
		hint = "[E / R]  Use Stairs"
	elif _get_nearest_bed_position() != Vector2.INF:
		hint = "[E / R]  Use Bed · Set Respawn"
	_set_hint(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_E and event.keycode != KEY_R:
		return
	if not _has_valid_context() or bool(_build_system.get("build_mode_enabled")):
		return

	# Stairs are handled by MultiFloorInputRouter first. If the event reaches this
	# manager, no stair consumed it, so the nearby bed gets the interaction.
	if try_use_nearby_bed():
		get_viewport().set_input_as_handled()


func try_use_nearby_bed() -> bool:
	if not _has_valid_context():
		return false
	var bed_position := _get_nearest_bed_position()
	if bed_position == Vector2.INF:
		return false
	if not _player.has_method("set_respawn_point"):
		_show_feedback("This bed cannot be used yet.")
		return false

	_player.call("set_respawn_point", bed_position)
	_show_feedback("Bed activated. This is now your respawn point.", false, 2.2)
	if _main != null and _main.has_method("save_game"):
		_main.call_deferred("save_game")
	return true


func _get_nearest_bed_position() -> Vector2:
	if _build_system == null or _player == null or not _build_system.has_method("get_nearest_bed_position"):
		return Vector2.INF
	return _build_system.call("get_nearest_bed_position", _player.global_position, bed_interaction_distance)


func _is_stair_nearby() -> bool:
	if _floor_manager == null or not _floor_manager.has_method("_find_nearest_stair"):
		return false
	var stair: Variant = _floor_manager.call("_find_nearest_stair", stair_hint_distance)
	return stair is Dictionary and not stair.is_empty()


func _resolve_context() -> void:
	_floor_manager = get_node_or_null(FLOOR_MANAGER_PATH)
	_build_system = get_tree().get_first_node_in_group("build_system")
	if _build_system == null:
		_player = null
		_main = null
		return
	_player = _build_system.get("player") as CharacterBody2D
	_main = _build_system.get("main") as Node


func _has_valid_context() -> bool:
	return _floor_manager != null and is_instance_valid(_floor_manager) \
		and _build_system != null and is_instance_valid(_build_system) \
		and _player != null and is_instance_valid(_player)


func _set_hint(message: String) -> void:
	if message == _last_hint:
		return
	_last_hint = message
	var feedback_ui := get_node_or_null(FEEDBACK_UI_PATH)
	if feedback_ui == null:
		return
	if message.is_empty():
		if feedback_ui.has_method("clear_interaction_hint"):
			feedback_ui.call("clear_interaction_hint", HINT_OWNER)
	elif feedback_ui.has_method("set_interaction_hint"):
		feedback_ui.call("set_interaction_hint", message, HINT_OWNER)


func _clear_hint() -> void:
	_set_hint("")


func _show_feedback(message: String, is_error := true, duration := 2.4) -> void:
	var feedback_ui := get_node_or_null(FEEDBACK_UI_PATH)
	if feedback_ui != null and feedback_ui.has_method("show_feedback"):
		feedback_ui.call("show_feedback", message, is_error, duration)
	else:
		print(message)
