extends Node


func _ready() -> void:
	set_process_unhandled_key_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_F11:
		return
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null and settings_manager.has_method("toggle_borderless_fullscreen"):
		settings_manager.call("toggle_borderless_fullscreen")
		get_viewport().set_input_as_handled()
