extends Node

const MANAGER_PATH := "/root/MultiFloorBuildManager"
const BUILD_MENU_PATH := "/root/BuildMenuOverlay"
const CAMPFIRE_ID := "campfire"


func _ready() -> void:
	process_priority = -950
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null:
		return
	if manager.is_processing_input():
		manager.set_process_input(false)
	var build_system := manager.get("_build_system") as Node
	if build_system != null and build_system.is_processing_unhandled_input():
		build_system.set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null or not bool(manager.get("_initialized")):
		return
	var build_system := manager.get("_build_system") as Node
	if build_system == null:
		return
	var build_mode := bool(build_system.get("build_mode_enabled"))

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			if build_system.has_method("set_build_mode_enabled"):
				build_system.call("set_build_mode_enabled", not build_mode)
			get_viewport().set_input_as_handled()
			return

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

		if build_mode and build_system.has_method("_get_building_id_for_key"):
			var building_id := str(build_system.call("_get_building_id_for_key", event.keycode))
			if not building_id.is_empty():
				build_system.set("selected_build_type", building_id)
				if build_system.has_method("_update_preview"):
					build_system.call("_update_preview")
				if build_system.has_method("_update_build_label"):
					build_system.call("_update_build_label")
				get_viewport().set_input_as_handled()
				return

	if not build_mode or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not _can_afford_selected_building(build_system):
			_show_feedback(_get_missing_resources_message(build_system))
			get_viewport().set_input_as_handled()
			return
		manager.call("_try_place_current_selection")
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		manager.call("_try_remove_at_cursor")
		get_viewport().set_input_as_handled()


func _can_afford_selected_building(build_system: Node) -> bool:
	var building_id := str(build_system.get("selected_build_type"))
	var main := build_system.get("main") as Node
	if building_id == CAMPFIRE_ID and main != null and main.has_method("can_spend_resource"):
		if bool(main.call("can_spend_resource", CAMPFIRE_ID, 1)):
			return true
	if not build_system.has_method("_can_spend_building_cost"):
		return true
	return bool(build_system.call("_can_spend_building_cost", building_id))


func _get_missing_resources_message(build_system: Node) -> String:
	var building_id := str(build_system.get("selected_build_type"))
	var display_name := building_id.capitalize()
	if build_system.has_method("_get_building_display_name"):
		display_name = str(build_system.call("_get_building_display_name", building_id))

	var required: PackedStringArray = []
	if build_system.has_method("_get_building_cost"):
		var costs: Variant = build_system.call("_get_building_cost", building_id)
		if costs is Array:
			for cost_variant in costs:
				if cost_variant is Dictionary:
					var cost: Dictionary = cost_variant
					var amount := int(cost.get("amount", 0))
					var resource_name := str(cost.get("resource", "")).capitalize()
					if amount > 0 and not resource_name.is_empty():
						required.append("%d %s" % [amount, resource_name])

	if required.is_empty():
		return "Not enough resources to build %s." % display_name
	return "Not enough resources to build %s. Required: %s." % [display_name, ", ".join(required)]


func _show_feedback(message: String) -> void:
	var build_menu := get_node_or_null(BUILD_MENU_PATH)
	if build_menu != null and build_menu.has_method("show_feedback"):
		build_menu.call("show_feedback", message, true)
	else:
		print(message)
