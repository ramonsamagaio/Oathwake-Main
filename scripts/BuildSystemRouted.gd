extends "res://scripts/BuildSystem.gd"


func _unhandled_input(event: InputEvent) -> void:
	if _is_crafting_open():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_set_build_mode_enabled(not build_mode_enabled)
		get_viewport().set_input_as_handled()
		return

	if not build_mode_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var building_id := _get_building_id_for_key(event.keycode)
		if not building_id.is_empty():
			selected_build_type = building_id
			get_viewport().set_input_as_handled()
			_update_preview()
			_update_build_label()

	# Mouse placement and removal are intentionally handled by
	# MultiFloorInputRouter after the GUI has received the click.
