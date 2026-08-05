extends Node

const MANAGER_PATH := "/root/MultiFloorBuildManager"


func _ready() -> void:
	process_priority = -950
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager != null and manager.is_processing_input():
		manager.set_process_input(false)


func _unhandled_input(event: InputEvent) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null or not bool(manager.get("_initialized")):
		return
	var build_system := manager.get("_build_system") as Node
	if build_system == null:
		return
	var build_mode := bool(build_system.get("build_mode_enabled"))

	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_R or event.keycode == KEY_E) and not build_mode:
			if bool(manager.call("try_use_nearby_stairs")):
				get_viewport().set_input_as_handled()
			return
		if build_mode and event.keycode == KEY_PAGEUP:
			if bool(manager.call("try_change_floor", int(manager.call("get_current_floor")) + 1)):
				get_viewport().set_input_as_handled()
			return
		if build_mode and event.keycode == KEY_PAGEDOWN:
			if bool(manager.call("try_change_floor", int(manager.call("get_current_floor")) - 1)):
				get_viewport().set_input_as_handled()
			return

	if not build_mode or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		manager.call("_try_place_current_selection")
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		manager.call("_try_remove_at_cursor")
		get_viewport().set_input_as_handled()
