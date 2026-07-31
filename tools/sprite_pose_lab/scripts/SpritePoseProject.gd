class_name SpritePoseProject
extends RefCounted

const FORMAT_NAME := "oathwake_sprite_pose_project"
const FORMAT_VERSION := 2
const DIRECTIONS := ["south", "north", "east", "west"]

var project_name := "Oathwake Pose Project"
var character_name := "player"
var current_direction := "south"
var current_clip := "idle"
var canvas_size := Vector2i(64, 64)
var feet_y := 60
var fps := 8.0
var loop_mode := "loop"
var use_frame_durations := false

var bones: Array = []
var texture_library: Dictionary = {}
var clips: Dictionary = {}
var metadata: Dictionary = {
	"created_with": "SpritePoseLab",
	"notes": "",
}


func _init() -> void:
	create_humanoid_basic()


func create_humanoid_basic() -> void:
	bones = [
		_make_bone("root", "Root", "", false, Vector2.ZERO, 0),
		_make_bone("torso", "Tronco", "root", true, Vector2(0, 0), 3),
		_make_bone("head", "Cabeça", "torso", true, Vector2(0, -18), 5),
		_make_bone("left_arm", "Braço esquerdo", "torso", true, Vector2(-11, 0), 4),
		_make_bone("right_arm", "Braço direito", "torso", true, Vector2(11, 0), 2),
		_make_bone("left_leg", "Perna esquerda", "root", true, Vector2(-4, 17), 1),
		_make_bone("right_leg", "Perna direita", "root", true, Vector2(4, 17), 0),
	]
	_reset_texture_library()
	clips = {}
	current_clip = "idle"
	clips[current_clip] = {
		"name": "Idle",
		"frames": [_empty_frame()],
	}
	_key_full_pose(0)


func _make_bone(
	bone_id: String,
	display_name: String,
	parent_id: String,
	has_sprite: bool,
	position_value: Vector2,
	z_order: int
) -> Dictionary:
	return {
		"id": bone_id,
		"name": display_name,
		"parent": parent_id,
		"has_sprite": has_sprite,
		"locked": false,
		"rest": {
			"position": [position_value.x, position_value.y],
			"rotation_degrees": 0.0,
			"pivot": [0.0, 0.0],
			"z_index": z_order,
			"visible": true,
		},
		"constraints": {
			"rotation_min": -180.0,
			"rotation_max": 180.0,
			"foot_contact": bone_id.ends_with("leg"),
		},
		"tags": [],
	}


func _reset_texture_library() -> void:
	texture_library = {}
	for direction in DIRECTIONS:
		texture_library[direction] = {}
		for bone in bones:
			texture_library[direction][str(bone.get("id", ""))] = ""


func _empty_frame() -> Dictionary:
	return {
		"duration": 0.125,
		"keys": {},
		"label": "",
	}


func bone_ids() -> Array:
	var result: Array = []
	for bone in bones:
		result.append(str(bone.get("id", "")))
	return result


func bone_by_id(bone_id: String) -> Dictionary:
	for bone in bones:
		if str(bone.get("id", "")) == bone_id:
			return bone
	return {}


func bone_index(bone_id: String) -> int:
	for index in range(bones.size()):
		if str(bones[index].get("id", "")) == bone_id:
			return index
	return -1


func children_of(parent_id: String) -> Array:
	var result: Array = []
	for bone in bones:
		if str(bone.get("parent", "")) == parent_id:
			result.append(str(bone.get("id", "")))
	return result


func add_custom_bone(display_name: String, parent_id: String = "root", has_sprite: bool = true) -> String:
	var safe_id := _unique_bone_id(display_name)
	if bone_by_id(parent_id).is_empty():
		parent_id = "root"
	bones.append(_make_bone(safe_id, display_name, parent_id, has_sprite, Vector2.ZERO, 0))
	for direction in DIRECTIONS:
		if not texture_library.has(direction):
			texture_library[direction] = {}
		texture_library[direction][safe_id] = ""
	return safe_id


func rename_bone(bone_id: String, display_name: String) -> void:
	var bone := bone_by_id(bone_id)
	if bone.is_empty():
		return
	bone["name"] = display_name.strip_edges() if not display_name.strip_edges().is_empty() else bone_id


func remove_bone(bone_id: String) -> bool:
	if bone_id == "root":
		return false
	var index := bone_index(bone_id)
	if index < 0:
		return false
	var parent_id := str(bones[index].get("parent", "root"))
	for bone in bones:
		if str(bone.get("parent", "")) == bone_id:
			bone["parent"] = parent_id
	bones.remove_at(index)
	for direction in DIRECTIONS:
		if texture_library.has(direction):
			texture_library[direction].erase(bone_id)
	for clip_name in clips.keys():
		var clip: Dictionary = clips[clip_name]
		for frame in clip.get("frames", []):
			var keys: Dictionary = frame.get("keys", {})
			keys.erase(bone_id)
	return true


func set_bone_parent(bone_id: String, parent_id: String) -> bool:
	if bone_id == "root" or bone_id == parent_id:
		return false
	var bone := bone_by_id(bone_id)
	if bone.is_empty() or bone_by_id(parent_id).is_empty():
		return false
	var cursor := parent_id
	while not cursor.is_empty():
		if cursor == bone_id:
			return false
		var parent_bone := bone_by_id(cursor)
		if parent_bone.is_empty():
			break
		cursor = str(parent_bone.get("parent", ""))
	bone["parent"] = parent_id
	return true


func _unique_bone_id(display_name: String) -> String:
	var base := _safe_id(display_name)
	if base.is_empty():
		base = "bone"
	var candidate := base
	var suffix := 2
	while not bone_by_id(candidate).is_empty():
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _safe_id(value: String) -> String:
	var result := value.strip_edges().to_lower().to_snake_case()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]+")
	result = regex.sub(result, "_", true)
	while result.contains("__"):
		result = result.replace("__", "_")
	return result.trim_prefix("_").trim_suffix("_")


func current_clip_data() -> Dictionary:
	if not clips.has(current_clip):
		clips[current_clip] = {"name": current_clip.capitalize(), "frames": [_empty_frame()]}
	return clips[current_clip]


func frames() -> Array:
	var clip := current_clip_data()
	return clip.get("frames", [])


func frame_count() -> int:
	return frames().size()


func frame_at(frame_index: int) -> Dictionary:
	var all_frames := frames()
	if all_frames.is_empty():
		all_frames.append(_empty_frame())
	return all_frames[clampi(frame_index, 0, all_frames.size() - 1)]


func add_clip(clip_id: String, display_name: String) -> String:
	var safe_id := _safe_id(clip_id)
	if safe_id.is_empty():
		safe_id = "animation"
	var candidate := safe_id
	var suffix := 2
	while clips.has(candidate):
		candidate = "%s_%d" % [safe_id, suffix]
		suffix += 1
	clips[candidate] = {"name": display_name, "frames": [_empty_frame()]}
	current_clip = candidate
	_key_full_pose(0)
	return candidate


func insert_frame(after_index: int, duplicate_resolved: bool = false) -> int:
	var all_frames := frames()
	var insert_index := clampi(after_index + 1, 0, all_frames.size())
	var new_frame := _empty_frame()
	if duplicate_resolved and not all_frames.is_empty():
		for bone_id in bone_ids():
			new_frame["keys"][bone_id] = resolved_transform(after_index, bone_id)
	all_frames.insert(insert_index, new_frame)
	return insert_index


func remove_frame(frame_index: int) -> int:
	var all_frames := frames()
	if all_frames.size() <= 1:
		return 0
	all_frames.remove_at(clampi(frame_index, 0, all_frames.size() - 1))
	return mini(frame_index, all_frames.size() - 1)


func move_frame(from_index: int, to_index: int) -> int:
	var all_frames := frames()
	if all_frames.is_empty():
		return 0
	from_index = clampi(from_index, 0, all_frames.size() - 1)
	to_index = clampi(to_index, 0, all_frames.size() - 1)
	var frame := all_frames[from_index]
	all_frames.remove_at(from_index)
	all_frames.insert(to_index, frame)
	return to_index


func is_keyed(frame_index: int, bone_id: String) -> bool:
	var frame := frame_at(frame_index)
	var keys: Dictionary = frame.get("keys", {})
	return keys.has(bone_id)


func ensure_key(frame_index: int, bone_id: String) -> Dictionary:
	var frame := frame_at(frame_index)
	var keys: Dictionary = frame.get("keys", {})
	if not keys.has(bone_id):
		keys[bone_id] = resolved_transform(frame_index, bone_id)
	frame["keys"] = keys
	return keys[bone_id]


func remove_key(frame_index: int, bone_id: String) -> void:
	var frame := frame_at(frame_index)
	var keys: Dictionary = frame.get("keys", {})
	keys.erase(bone_id)


func resolved_transform(frame_index: int, bone_id: String) -> Dictionary:
	var bone := bone_by_id(bone_id)
	if bone.is_empty():
		return _default_transform()
	var result: Dictionary = _normalize_transform(bone.get("rest", {}), _default_transform())
	var all_frames := frames()
	var last_index := mini(frame_index, all_frames.size() - 1)
	for index in range(last_index + 1):
		var keys: Dictionary = all_frames[index].get("keys", {})
		if keys.has(bone_id):
			result = _normalize_transform(keys[bone_id], result)
	return result.duplicate(true)


func set_transform(frame_index: int, bone_id: String, transform_data: Dictionary) -> void:
	var key := ensure_key(frame_index, bone_id)
	var normalized := _normalize_transform(transform_data, key)
	var frame := frame_at(frame_index)
	frame["keys"][bone_id] = normalized


func set_texture(direction: String, bone_id: String, path: String) -> void:
	if not (direction in DIRECTIONS):
		direction = "south"
	if not texture_library.has(direction):
		texture_library[direction] = {}
	texture_library[direction][bone_id] = path


func texture_path(direction: String, bone_id: String) -> String:
	if texture_library.has(direction):
		return str(texture_library[direction].get(bone_id, ""))
	return ""


func _default_transform() -> Dictionary:
	return {
		"position": [0.0, 0.0],
		"rotation_degrees": 0.0,
		"pivot": [0.0, 0.0],
		"z_index": 0,
		"visible": true,
	}


func _normalize_transform(source: Variant, fallback: Dictionary) -> Dictionary:
	var source_dict: Dictionary = {}
	if source is Dictionary:
		source_dict = source
	var position_value := _vector_from(source_dict.get("position", fallback.get("position", [0.0, 0.0])))
	var pivot_value := _vector_from(source_dict.get("pivot", fallback.get("pivot", [0.0, 0.0])))
	return {
		"position": [position_value.x, position_value.y],
		"rotation_degrees": float(source_dict.get("rotation_degrees", fallback.get("rotation_degrees", 0.0))),
		"pivot": [pivot_value.x, pivot_value.y],
		"z_index": int(source_dict.get("z_index", fallback.get("z_index", 0))),
		"visible": bool(source_dict.get("visible", fallback.get("visible", true))),
	}


func _vector_from(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO


func _key_full_pose(frame_index: int) -> void:
	for bone_id in bone_ids():
		var bone := bone_by_id(bone_id)
		set_transform(frame_index, bone_id, bone.get("rest", {}))


func apply_animation_preset(preset_id: String) -> void:
	match preset_id:
		"idle_4":
			_build_humanoid_motion(4, "idle")
		"walk_4":
			_build_humanoid_motion(4, "walk")
		"run_6":
			_build_humanoid_motion(6, "run")
		_:
			return


func _build_humanoid_motion(count: int, motion: String) -> void:
	var clip := current_clip_data()
	clip["frames"] = []
	for frame_number in range(count):
		clip["frames"].append(_empty_frame())
	var torso_bob := [0.0, 1.0, 0.0, -1.0, 0.0, 1.0]
	var swing := [0.0, 18.0, 0.0, -18.0, -8.0, 8.0]
	if motion == "run":
		swing = [28.0, 12.0, -18.0, -28.0, -12.0, 18.0]
	for frame_number in range(count):
		for bone_id in bone_ids():
			var transform_data := bone_by_id(bone_id).get("rest", {}).duplicate(true)
			if bone_id == "torso":
				var pos := _vector_from(transform_data.get("position", [0.0, 0.0]))
				var amplitude := 1.0 if motion != "run" else 2.0
				pos.y += torso_bob[frame_number % torso_bob.size()] * amplitude
				transform_data["position"] = [pos.x, pos.y]
			elif bone_id == "head":
				var head_pos := _vector_from(transform_data.get("position", [0.0, -18.0]))
				head_pos.y += torso_bob[frame_number % torso_bob.size()] * 0.5
				transform_data["position"] = [head_pos.x, head_pos.y]
			elif motion != "idle" and bone_id == "left_arm":
				transform_data["rotation_degrees"] = -swing[frame_number % swing.size()]
			elif motion != "idle" and bone_id == "right_arm":
				transform_data["rotation_degrees"] = swing[frame_number % swing.size()]
			elif motion != "idle" and bone_id == "left_leg":
				transform_data["rotation_degrees"] = swing[frame_number % swing.size()]
			elif motion != "idle" and bone_id == "right_leg":
				transform_data["rotation_degrees"] = -swing[frame_number % swing.size()]
			set_transform(frame_number, bone_id, transform_data)


func to_document() -> Dictionary:
	return {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"project": {
			"name": project_name,
			"character": character_name,
			"current_direction": current_direction,
			"current_clip": current_clip,
		},
		"canvas": {
			"width": canvas_size.x,
			"height": canvas_size.y,
			"feet_y": feet_y,
		},
		"rig": {
			"preset": "custom",
			"bones": bones.duplicate(true),
		},
		"parts": {
			"texture_library": texture_library.duplicate(true),
		},
		"animations": {
			"fps": fps,
			"loop_mode": loop_mode,
			"use_frame_durations": use_frame_durations,
			"clips": clips.duplicate(true),
		},
		"metadata": metadata.duplicate(true),
	}


func load_document(document: Dictionary) -> bool:
	if str(document.get("format", "")) != FORMAT_NAME:
		return false
	var project_section: Dictionary = document.get("project", {})
	var canvas_section: Dictionary = document.get("canvas", {})
	var rig_section: Dictionary = document.get("rig", {})
	var parts_section: Dictionary = document.get("parts", {})
	var animation_section: Dictionary = document.get("animations", {})
	project_name = str(project_section.get("name", project_name))
	character_name = str(project_section.get("character", character_name))
	current_direction = str(project_section.get("current_direction", "south"))
	canvas_size = Vector2i(
		clampi(int(canvas_section.get("width", 64)), 1, 2048),
		clampi(int(canvas_section.get("height", 64)), 1, 2048)
	)
	feet_y = clampi(int(canvas_section.get("feet_y", canvas_size.y - 4)), 0, canvas_size.y - 1)
	var loaded_bones: Variant = rig_section.get("bones", [])
	if not (loaded_bones is Array) or loaded_bones.is_empty():
		return false
	bones = loaded_bones.duplicate(true)
	texture_library = parts_section.get("texture_library", {}).duplicate(true)
	for direction in DIRECTIONS:
		if not texture_library.has(direction):
			texture_library[direction] = {}
		for bone_id in bone_ids():
			if not texture_library[direction].has(bone_id):
				texture_library[direction][bone_id] = ""
	fps = maxf(1.0, float(animation_section.get("fps", 8.0)))
	loop_mode = str(animation_section.get("loop_mode", "loop"))
	use_frame_durations = bool(animation_section.get("use_frame_durations", false))
	var loaded_clips: Variant = animation_section.get("clips", {})
	if not (loaded_clips is Dictionary) or loaded_clips.is_empty():
		return false
	clips = loaded_clips.duplicate(true)
	current_clip = str(project_section.get("current_clip", clips.keys()[0]))
	if not clips.has(current_clip):
		current_clip = str(clips.keys()[0])
	metadata = document.get("metadata", {}).duplicate(true)
	return true
