extends "res://scripts/enemies/EnemyBaseEnhanced.gd"

const DIRECTION_ROWS := {
	"down": 0,
	"left": 1,
	"right": 2,
	"up": 3,
}


func _ready() -> void:
	super._ready()


func _load_monster_data() -> void:
	super._load_monster_data()
	_correct_animation_direction_rows()


func _correct_animation_direction_rows() -> void:
	var animation_value: Variant = monster_data.get("animations", {})
	if not (animation_value is Dictionary):
		return
	var corrected := (animation_value as Dictionary).duplicate(true)
	for animation_name_value in corrected.keys():
		var animation_name := str(animation_name_value)
		var animation_definition_value: Variant = corrected.get(animation_name_value, {})
		if not (animation_definition_value is Dictionary):
			continue
		var direction := animation_name.get_slice("_", animation_name.get_slice_count("_") - 1)
		if not DIRECTION_ROWS.has(direction):
			continue
		var animation_definition := (animation_definition_value as Dictionary).duplicate(true)
		animation_definition["row"] = int(DIRECTION_ROWS[direction])
		corrected[animation_name_value] = animation_definition
	monster_data["animations"] = corrected
	animations_data = corrected.duplicate(true)
	set_meta("slime_direction_rows_corrected", true)
