extends RefCounted
class_name AlabasterPlayerVisualController

const RigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd")
const DEFAULT_ACTIONS := {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"attack": "atkSwordN1",
	"block": "guard",
	"death": "dead",
	"hurt": "damage",
	"dash": "dash",
}

var rig: Node2D
var active := false
var action_map: Dictionary = DEFAULT_ACTIONS.duplicate(true)
var profile_id := ""
var last_facing := Vector2.DOWN
var current_action := ""


func configure(owner: Node2D, character_data: Dictionary, visual_position: Vector2, visual_scale: float) -> bool:
	dispose()
	if str(character_data.get("visual_runtime", "sprite_sheet")) != "alabaster":
		return false
	profile_id = str(character_data.get("rig_profile_id", "juno"))
	action_map = DEFAULT_ACTIONS.duplicate(true)
	var custom_map = character_data.get("rig_animation_map", {})
	if custom_map is Dictionary:
		for key in custom_map.keys():
			var value := str(custom_map[key]).strip_edges()
			if not value.is_empty():
				action_map[str(key)] = value
	rig = RigScript.new() as Node2D
	if rig == null:
		return false
	rig.name = "AlabasterRigVisual"
	owner.add_child(rig)
	rig.position = visual_position
	rig.scale = Vector2.ONE * visual_scale
	if rig.has_method("set_embedded_world_mode"):
		rig.call("set_embedded_world_mode", true)
	active = true
	face(Vector2.DOWN)
	play("idle")
	return true


func dispose() -> void:
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	rig = null
	active = false
	current_action = ""
	profile_id = ""
	action_map = DEFAULT_ACTIONS.duplicate(true)


func play(action_name: String, speed_scale := 1.0) -> bool:
	if not active or rig == null:
		return false
	var animation_name := animation_for(action_name)
	if animation_name.is_empty() or not has_animation(animation_name):
		return false
	set_speed(speed_scale)
	rig.call("set_animation", animation_name)
	current_action = action_name
	return true


func animation_for(action_name: String) -> String:
	return str(action_map.get(action_name, "")).strip_edges()


func has_action(action_name: String) -> bool:
	var animation_name := animation_for(action_name)
	return not animation_name.is_empty() and has_animation(animation_name)


func has_animation(animation_name: String) -> bool:
	return rig != null and is_instance_valid(rig) and rig.has_method("has_animation") and bool(rig.call("has_animation", animation_name))


func duration_for(action_name: String) -> float:
	if rig == null or not rig.has_method("get_animation_duration_seconds"):
		return 0.0
	var animation_name := animation_for(action_name)
	if animation_name.is_empty():
		return 0.0
	return float(rig.call("get_animation_duration_seconds", animation_name))


func face(direction: Vector2) -> void:
	if not active or direction.length_squared() <= 0.000001:
		return
	last_facing = direction.normalized()
	if rig != null and rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", last_facing)


func set_speed(value: float) -> void:
	if rig != null and rig.has_method("set_animation_speed_scale"):
		rig.call("set_animation_speed_scale", maxf(value, 0.001))


func set_alpha(alpha: float) -> void:
	if rig != null and is_instance_valid(rig):
		rig.modulate.a = alpha


func set_material(material: Material) -> void:
	if rig == null:
		return
	for child in rig.get_children():
		if child is CanvasItem:
			(child as CanvasItem).material = material


func summary() -> Dictionary:
	if rig != null and rig.has_method("get_runtime_summary"):
		return rig.call("get_runtime_summary") as Dictionary
	return {}
