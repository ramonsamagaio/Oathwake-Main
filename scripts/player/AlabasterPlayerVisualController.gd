extends RefCounted
class_name AlabasterPlayerVisualController

const JunoRigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")
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
var directional_action_map: Dictionary = {}
var profile_id := ""
var last_facing := Vector2.DOWN
var current_action := ""


func configure(owner: Node2D, character_data: Dictionary, visual_position: Vector2, visual_scale: float) -> bool:
	dispose()
	if str(character_data.get("visual_runtime", "sprite_sheet")) != "alabaster":
		return false
	profile_id = str(character_data.get("rig_profile_id", "juno"))
	action_map = DEFAULT_ACTIONS.duplicate(true)
	directional_action_map = {}
	var custom_map = character_data.get("rig_animation_map", {})
	if custom_map is Dictionary:
		for key in custom_map.keys():
			var value := str(custom_map[key]).strip_edges()
			if not value.is_empty():
				action_map[str(key)] = value
	var directional_value: Variant = character_data.get("rig_directional_animation_map", {})
	if directional_value is Dictionary:
		directional_action_map = (directional_value as Dictionary).duplicate(true)

	if profile_id == "male_dummy" or profile_id == "male_temp":
		var skin_rig = PlayableSkinRigScript.new()
		if skin_rig == null:
			return false
		skin_rig.call("configure_skin_profile", profile_id)
		rig = skin_rig as Node2D
	else:
		rig = JunoRigScript.new() as Node2D
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
	directional_action_map = {}


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


func play_animation_name(animation_name: String, action_name := "custom", speed_scale := 1.0) -> bool:
	var clean_name := animation_name.strip_edges()
	if not active or rig == null or clean_name.is_empty() or not has_animation(clean_name):
		return false
	set_speed(speed_scale)
	rig.call("set_animation", clean_name)
	current_action = action_name
	return true


func animation_for(action_name: String) -> String:
	var direction_key := _master_direction_key(last_facing)
	var action_value: Variant = directional_action_map.get(action_name, {})
	if action_value is Dictionary:
		var override_name := str((action_value as Dictionary).get(direction_key, "")).strip_edges()
		if not override_name.is_empty():
			return override_name
	return str(action_map.get(action_name, "")).strip_edges()


func has_action(action_name: String) -> bool:
	var animation_name := animation_for(action_name)
	return not animation_name.is_empty() and has_animation(animation_name)


func has_animation(animation_name: String) -> bool:
	return rig != null and is_instance_valid(rig) and rig.has_method("has_animation") and bool(rig.call("has_animation", animation_name))


func duration_for(action_name: String) -> float:
	return duration_for_animation(animation_for(action_name))


func duration_for_animation(animation_name: String) -> float:
	if rig == null or not rig.has_method("get_animation_duration_seconds"):
		return 0.0
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


func _master_direction_key(direction: Vector2) -> String:
	if direction.length_squared() <= 0.000001:
		return "s"
	var angle := fposmod(rad_to_deg(atan2(direction.x, -direction.y)), 360.0)
	var index := int(round(angle / 45.0)) % 8
	match index:
		0: return "n"
		1, 7: return "ne"
		2, 6: return "e"
		3, 5: return "se"
		_: return "s"
