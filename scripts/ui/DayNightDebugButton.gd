class_name DayNightDebugButton
extends Button

enum TargetMode { DAY, NIGHT }

@export var target_mode: TargetMode = TargetMode.DAY


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_apply_target_time)


func _apply_target_time() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle == null:
		push_warning("DayNightDebugButton could not find the day/night cycle.")
		return
	if target_mode == TargetMode.NIGHT and cycle.has_method("set_night"):
		cycle.call("set_night")
	elif target_mode == TargetMode.DAY and cycle.has_method("set_day"):
		cycle.call("set_day")
