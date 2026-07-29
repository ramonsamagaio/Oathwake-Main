extends HBoxContainer


func _ready() -> void:
	name = "DayNightDebugControls"
	anchors_preset = Control.PRESET_CENTER_RIGHT
	anchor_left = 1.0
	anchor_top = 0.5
	anchor_right = 1.0
	anchor_bottom = 0.5
	offset_left = -180.0
	offset_top = -128.0
	offset_right = -16.0
	offset_bottom = -92.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_constant_override("separation", 6)
	_create_button("DAY", "Set the debug cycle to full daylight", "set_day")
	_create_button("NIGHT", "Set the debug cycle to full night", "set_night")


func _create_button(label_text: String, tooltip: String, method_name: StringName) -> void:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_set_cycle_state.bind(method_name))
	add_child(button)


func _set_cycle_state(method_name: StringName) -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method(method_name):
		cycle.call(method_name)
