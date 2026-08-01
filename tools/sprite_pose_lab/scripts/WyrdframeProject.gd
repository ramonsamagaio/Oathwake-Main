class_name WyrdframeProject
extends RefCounted

signal structure_changed

const FORMAT_NAME := "wyrdframe_project"
const FORMAT_VERSION := 3
const FILE_EXTENSION := "wyrd"
const DIRECTIONS := ["south", "north", "east", "west"]
const ENTITY_TYPES := ["character", "monster", "boss", "custom"]
const ACTION_PRESETS := {
	"idle": {"name": "Idle", "frames": 4},
	"walk": {"name": "Walk", "frames": 4},
	"run": {"name": "Run", "frames": 6},
	"attack_1h": {"name": "Attack 1H", "frames": 6},
	"attack_2h": {"name": "Attack 2H", "frames": 7},
	"attack_bow": {"name": "Attack Bow", "frames": 7},
	"attack": {"name": "Attack", "frames": 6},
	"cast": {"name": "Cast", "frames": 6},
	"hit": {"name": "Hit", "frames": 4},
	"death": {"name": "Death", "frames": 8},
	"phase": {"name": "Phase", "frames": 8},
	"custom": {"name": "Custom", "frames": 1},
}
const ENTITY_STARTERS := {
	"character": ["idle", "walk", "run", "attack_1h", "attack_2h", "attack_bow", "custom"],
	"monster": ["idle", "walk", "attack", "hit", "death", "custom"],
	"boss": ["idle", "walk", "attack", "cast", "phase", "hit", "death", "custom"],
	"custom": ["custom"],
}

var project_name := "Novo Projeto"
var asset_name := "player"
var entity_type := "character"
var current_action := ""
var current_direction := "south"
var canvas_size := Vector2i(64, 64)
var feet_y := 60
var fps := 8.0
var loop_mode := "loop"
var use_frame_durations := false
var bones: Array = []
var actions: Dictionary = {}
var metadata := {"created_with": "Wyrdframe Studio", "notes": ""}


func _init() -> void:
	reset_project("character")


func reset_project(kind: String = "character") -> void:
	entity_type = kind if (kind in ENTITY_TYPES) else "custom"
	project_name = "Novo Projeto"
	asset_name = "player" if entity_type == "character" else entity_type
	_create_humanoid_rig()
	actions.clear()
	current_action = ""
	current_direction = "south"
	apply_entity_template(entity_type, true)
	current_action = str(actions.keys()[0])
	structure_changed.emit()


func _create_humanoid_rig() -> void:
	bones = [
		_make_bone("root", "Root", "", false, Vector2.ZERO, 0),
		_make_bone("torso", "Tronco", "root", true, Vector2.ZERO, 3),
		_make_bone("head", "Cabeça", "torso", true, Vector2(0, -18), 5),
		_make_bone("left_arm", "Braço esquerdo", "torso", true, Vector2(-11, 0), 4),
		_make_bone("right_arm", "Braço direito", "torso", true, Vector2(11, 0), 2),
		_make_bone("left_leg", "Perna esquerda", "root", true, Vector2(-4, 17), 1),
		_make_bone("right_leg", "Perna direita", "root", true, Vector2(4, 17), 0),
	]


func create_humanoid_basic() -> void:
	_create_humanoid_rig()
	_normalize_actions()
	structure_changed.emit()


func _make_bone(id: String, label: String, parent: String, sprite: bool, pos: Vector2, order: int) -> Dictionary:
	return {
		"id": id, "name": label, "parent": parent, "has_sprite": sprite, "locked": false,
		"rest": {"position": [pos.x, pos.y], "rotation_degrees": 0.0, "pivot": [0.0, 0.0], "z_index": order, "visible": true},
		"constraints": {"rotation_min": -180.0, "rotation_max": 180.0, "foot_contact": id.ends_with("leg")},
		"tags": [],
	}


func bone_ids() -> Array:
	var result: Array = []
	for bone in bones:
		result.append(str(bone.get("id", "")))
	return result


func bone_by_id(id: String) -> Dictionary:
	for bone in bones:
		if str(bone.get("id", "")) == id:
			return bone
	return {}


func add_custom_bone(label: String, parent: String = "root", sprite: bool = true) -> String:
	var id := _unique_id(label, bone_ids(), "bone")
	if bone_by_id(parent).is_empty():
		parent = "root"
	bones.append(_make_bone(id, label, parent, sprite, Vector2.ZERO, 0))
	_normalize_actions()
	structure_changed.emit()
	return id


func rename_bone(id: String, label: String) -> void:
	var bone := bone_by_id(id)
	if not bone.is_empty():
		bone["name"] = label.strip_edges() if not label.strip_edges().is_empty() else id
		structure_changed.emit()


func remove_bone(id: String) -> bool:
	if id == "root":
		return false
	var index := -1
	for i in range(bones.size()):
		if str(bones[i].get("id", "")) == id:
			index = i
			break
	if index < 0:
		return false
	var parent := str(bones[index].get("parent", "root"))
	for bone in bones:
		if str(bone.get("parent", "")) == id:
			bone["parent"] = parent
	bones.remove_at(index)
	for action in actions.values():
		for direction in DIRECTIONS:
			var data: Dictionary = action["directions"][direction]
			data["textures"].erase(id)
			for frame in data["frames"]:
				frame["keys"].erase(id)
	structure_changed.emit()
	return true


func set_bone_parent(id: String, parent: String) -> bool:
	if id == "root" or id == parent or bone_by_id(id).is_empty():
		return false
	if not parent.is_empty() and bone_by_id(parent).is_empty():
		return false
	var cursor := parent
	while not cursor.is_empty():
		if cursor == id:
			return false
		cursor = str(bone_by_id(cursor).get("parent", ""))
	bone_by_id(id)["parent"] = parent
	structure_changed.emit()
	return true


func action_ids() -> Array:
	return actions.keys()


func current_action_data() -> Dictionary:
	if not actions.has(current_action):
		current_action = str(actions.keys()[0])
	return actions[current_action]


func current_clip_data() -> Dictionary:
	return current_action_data()["directions"][current_direction]


func frames() -> Array:
	return current_clip_data()["frames"]


func frame_count() -> int:
	return frames().size()


func frame_at(index: int) -> Dictionary:
	return frames()[clampi(index, 0, frame_count() - 1)]


func add_action_from_preset(preset_id: String, label: String = "", clone_from: String = "") -> String:
	if not ACTION_PRESETS.has(preset_id):
		preset_id = "custom"
	var preset: Dictionary = ACTION_PRESETS[preset_id]
	var id := _unique_id(preset_id, actions.keys(), "action")
	var display := label.strip_edges()
	if display.is_empty():
		display = str(preset["name"])
	var action := {"name": display, "preset": preset_id, "directions": {}, "metadata": {}}
	for direction in DIRECTIONS:
		action["directions"][direction] = _new_direction_data()
	actions[id] = action
	if actions.has(clone_from):
		for direction in DIRECTIONS:
			actions[id]["directions"][direction]["textures"] = actions[clone_from]["directions"][direction]["textures"].duplicate(true)
	var old_direction := current_direction
	current_action = id
	for direction in DIRECTIONS:
		current_direction = direction
		apply_animation_preset(preset_id, false)
	current_direction = old_direction if (old_direction in DIRECTIONS) else "south"
	structure_changed.emit()
	return id


func add_custom_action(label: String = "Nova ação", clone_textures: bool = true) -> String:
	var source := current_action if clone_textures and actions.has(current_action) else ""
	return add_action_from_preset("custom", label, source)


func remove_action(id: String) -> bool:
	if actions.size() <= 1 or not actions.has(id):
		return false
	actions.erase(id)
	if current_action == id:
		current_action = str(actions.keys()[0])
	structure_changed.emit()
	return true


func rename_action(id: String, label: String) -> void:
	if actions.has(id):
		actions[id]["name"] = label.strip_edges() if not label.strip_edges().is_empty() else id
		structure_changed.emit()


func apply_entity_template(kind: String, keep_existing: bool = true) -> void:
	var previous := current_action
	entity_type = kind if (kind in ENTITY_TYPES) else "custom"
	if not keep_existing:
		actions.clear()
	for preset_id in ENTITY_STARTERS.get(entity_type, ["custom"]):
		var found := false
		for action in actions.values():
			if str(action.get("preset", "custom")) == preset_id:
				found = true
				break
		if not found:
			add_action_from_preset(preset_id)
	if actions.has(previous):
		current_action = previous
	elif not actions.is_empty():
		current_action = str(actions.keys()[0])
	structure_changed.emit()


func set_texture(direction: String, bone_id: String, path: String) -> void:
	if not (direction in DIRECTIONS):
		direction = "south"
	current_action_data()["directions"][direction]["textures"][bone_id] = path


func texture_path(direction: String, bone_id: String) -> String:
	if not actions.has(current_action):
		return ""
	return str(actions[current_action]["directions"][direction]["textures"].get(bone_id, ""))


func insert_frame(after: int, duplicate_pose: bool = false) -> int:
	var index := clampi(after + 1, 0, frame_count())
	var frame := _empty_frame()
	if duplicate_pose:
		for id in bone_ids():
			frame["keys"][id] = resolved_transform(after, id)
	frames().insert(index, frame)
	return index


func remove_frame(index: int) -> int:
	if frame_count() <= 1:
		return 0
	frames().remove_at(clampi(index, 0, frame_count() - 1))
	return mini(index, frame_count() - 1)


func move_frame(from: int, to: int) -> int:
	from = clampi(from, 0, frame_count() - 1)
	to = clampi(to, 0, frame_count() - 1)
	var frame := frames()[from]
	frames().remove_at(from)
	frames().insert(to, frame)
	return to


func is_keyed(index: int, bone_id: String) -> bool:
	return frame_at(index)["keys"].has(bone_id)


func ensure_key(index: int, bone_id: String) -> Dictionary:
	var keys: Dictionary = frame_at(index)["keys"]
	if not keys.has(bone_id):
		keys[bone_id] = resolved_transform(index, bone_id)
	return keys[bone_id]


func remove_key(index: int, bone_id: String) -> void:
	frame_at(index)["keys"].erase(bone_id)


func resolved_transform(index: int, bone_id: String) -> Dictionary:
	var bone := bone_by_id(bone_id)
	if bone.is_empty():
		return _default_transform()
	var result := _normalize_transform(bone.get("rest", {}), _default_transform())
	for i in range(mini(index, frame_count() - 1) + 1):
		var keys: Dictionary = frames()[i]["keys"]
		if keys.has(bone_id):
			result = _normalize_transform(keys[bone_id], result)
	return result.duplicate(true)


func set_transform(index: int, bone_id: String, data: Dictionary) -> void:
	frame_at(index)["keys"][bone_id] = _normalize_transform(data, ensure_key(index, bone_id))


func apply_animation_preset(preset_id: String, emit_signal: bool = true) -> void:
	if not ACTION_PRESETS.has(preset_id):
		preset_id = "custom"
	var count := int(ACTION_PRESETS[preset_id]["frames"])
	current_clip_data()["frames"] = []
	for i in range(count):
		current_clip_data()["frames"].append(_empty_frame())
		for id in bone_ids():
			var data: Dictionary = bone_by_id(id).get("rest", {}).duplicate(true)
			_apply_motion(data, id, preset_id, i, count)
			set_transform(i, id, data)
	if emit_signal:
		structure_changed.emit()


func _apply_motion(data: Dictionary, id: String, preset: String, index: int, count: int) -> void:
	var phase := TAU * float(index) / float(maxi(1, count))
	var pos := _vec(data.get("position", [0, 0]))
	if preset == "idle":
		if id == "torso": pos.y += roundf(sin(phase))
	elif preset == "walk" or preset == "run":
		var swing := sin(phase) * (18.0 if preset == "walk" else 30.0)
		if id == "left_arm" or id == "right_leg": data["rotation_degrees"] = -swing
		if id == "right_arm" or id == "left_leg": data["rotation_degrees"] = swing
		if id == "torso": pos.y += roundf(abs(sin(phase)) * (1.0 if preset == "walk" else 2.0))
	elif preset.begins_with("attack"):
		var t := float(index) / float(maxi(1, count - 1))
		if id == "right_arm": data["rotation_degrees"] = lerpf(-55.0, 85.0, t)
		if preset == "attack_2h" and id == "left_arm": data["rotation_degrees"] = lerpf(55.0, -70.0, t)
	elif preset == "cast":
		if id == "left_arm": data["rotation_degrees"] = -45.0 - sin(phase) * 20.0
		if id == "right_arm": data["rotation_degrees"] = 45.0 + sin(phase) * 20.0
	elif preset == "hit" and id == "torso":
		pos.x += [0.0, -2.0, 1.0, 0.0][index % 4]
	elif preset == "death" and id == "root":
		var t := float(index) / float(maxi(1, count - 1))
		data["rotation_degrees"] = t * 80.0
		pos.y += roundf(t * 8.0)
	data["position"] = [pos.x, pos.y]


func _new_direction_data() -> Dictionary:
	var textures := {}
	for id in bone_ids():
		textures[id] = ""
	return {"frames": [_empty_frame()], "textures": textures, "metadata": {}}


func _empty_frame() -> Dictionary:
	return {"duration": 0.125, "keys": {}, "label": "", "metadata": {}}


func _default_transform() -> Dictionary:
	return {"position": [0.0, 0.0], "rotation_degrees": 0.0, "pivot": [0.0, 0.0], "z_index": 0, "visible": true}


func _normalize_transform(source: Variant, fallback: Dictionary) -> Dictionary:
	var src: Dictionary = source if source is Dictionary else {}
	var pos := _vec(src.get("position", fallback.get("position", [0, 0])))
	var pivot := _vec(src.get("pivot", fallback.get("pivot", [0, 0])))
	return {"position": [pos.x, pos.y], "rotation_degrees": float(src.get("rotation_degrees", fallback.get("rotation_degrees", 0))), "pivot": [pivot.x, pivot.y], "z_index": int(src.get("z_index", fallback.get("z_index", 0))), "visible": bool(src.get("visible", fallback.get("visible", true)))}


func _vec(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO


func _unique_id(value: String, used: Array, fallback: String) -> String:
	var base := value.strip_edges().to_lower().to_snake_case()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]+")
	base = regex.sub(base, "_", true)
	if base.is_empty():
		base = fallback
	var result := base
	var suffix := 2
	while result in used:
		result = "%s_%d" % [base, suffix]
		suffix += 1
	return result


func _normalize_actions() -> void:
	for action in actions.values():
		for direction in DIRECTIONS:
			if not action["directions"].has(direction):
				action["directions"][direction] = _new_direction_data()
			var data: Dictionary = action["directions"][direction]
			for id in bone_ids():
				if not data["textures"].has(id):
					data["textures"][id] = ""
			if data["frames"].is_empty():
				data["frames"] = [_empty_frame()]


func project_filename() -> String:
	var safe := asset_name.strip_edges().to_lower().to_snake_case()
	return "%s.%s" % [safe if not safe.is_empty() else "wyrdframe_project", FILE_EXTENSION]


func to_document() -> Dictionary:
	return {"format": FORMAT_NAME, "version": FORMAT_VERSION, "application": "Wyrdframe Studio", "project": {"name": project_name, "asset_name": asset_name, "entity_type": entity_type, "current_action": current_action, "current_direction": current_direction}, "canvas": {"width": canvas_size.x, "height": canvas_size.y, "feet_y": feet_y}, "rig": {"preset": "custom", "bones": bones.duplicate(true)}, "animation": {"fps": fps, "loop_mode": loop_mode, "use_frame_durations": use_frame_durations, "actions": actions.duplicate(true)}, "metadata": metadata.duplicate(true)}


func load_document(doc: Dictionary) -> bool:
	var format_name := str(doc.get("format", ""))
	if format_name == "oathwake_sprite_pose_project":
		return _load_legacy_v2(doc)
	if format_name != FORMAT_NAME:
		return false
	var p: Dictionary = doc.get("project", {})
	var c: Dictionary = doc.get("canvas", {})
	var r: Dictionary = doc.get("rig", {})
	var a: Dictionary = doc.get("animation", {})
	var loaded_bones: Variant = r.get("bones", [])
	var loaded_actions: Variant = a.get("actions", {})
	if not (loaded_bones is Array) or loaded_bones.is_empty():
		return false
	if not (loaded_actions is Dictionary) or loaded_actions.is_empty():
		return false
	project_name = str(p.get("name", "Projeto"))
	asset_name = str(p.get("asset_name", "asset"))
	entity_type = str(p.get("entity_type", "custom"))
	current_action = str(p.get("current_action", ""))
	current_direction = str(p.get("current_direction", "south"))
	canvas_size = Vector2i(clampi(int(c.get("width", 64)), 1, 2048), clampi(int(c.get("height", 64)), 1, 2048))
	feet_y = clampi(int(c.get("feet_y", 60)), 0, canvas_size.y - 1)
	bones = loaded_bones.duplicate(true)
	actions = loaded_actions.duplicate(true)
	fps = maxf(1.0, float(a.get("fps", 8.0)))
	loop_mode = str(a.get("loop_mode", "loop"))
	use_frame_durations = bool(a.get("use_frame_durations", false))
	metadata = doc.get("metadata", {}).duplicate(true)
	_normalize_actions()
	if not actions.has(current_action):
		current_action = str(actions.keys()[0])
	if not (current_direction in DIRECTIONS):
		current_direction = "south"
	structure_changed.emit()
	return true


func _load_legacy_v2(doc: Dictionary) -> bool:
	var p: Dictionary = doc.get("project", {})
	var c: Dictionary = doc.get("canvas", {})
	var r: Dictionary = doc.get("rig", {})
	var parts: Dictionary = doc.get("parts", {})
	var animations: Dictionary = doc.get("animations", {})
	var loaded_bones: Variant = r.get("bones", [])
	var old_clips: Variant = animations.get("clips", {})
	if not (loaded_bones is Array) or loaded_bones.is_empty():
		return false
	if not (old_clips is Dictionary) or old_clips.is_empty():
		return false
	bones = loaded_bones.duplicate(true)
	project_name = str(p.get("name", "Projeto migrado"))
	asset_name = str(p.get("character", "asset"))
	entity_type = "custom"
	current_direction = str(p.get("current_direction", "south"))
	canvas_size = Vector2i(int(c.get("width", 64)), int(c.get("height", 64)))
	feet_y = clampi(int(c.get("feet_y", 60)), 0, canvas_size.y - 1)
	actions.clear()
	var old_textures: Dictionary = parts.get("texture_library", {})
	for old_id in old_clips.keys():
		var action_id := _unique_id(str(old_id), actions.keys(), "action")
		var old_clip: Dictionary = old_clips[old_id]
		var action := {"name": str(old_clip.get("name", old_id)), "preset": "custom", "directions": {}, "metadata": {"migrated_from_v2": true}}
		for direction in DIRECTIONS:
			var data := _new_direction_data()
			data["textures"] = old_textures.get(direction, {}).duplicate(true)
			if direction == current_direction:
				data["frames"] = old_clip.get("frames", [_empty_frame()]).duplicate(true)
			action["directions"][direction] = data
		actions[action_id] = action
	current_action = str(p.get("current_clip", actions.keys()[0]))
	if not actions.has(current_action):
		current_action = str(actions.keys()[0])
	fps = maxf(1.0, float(animations.get("fps", 8.0)))
	loop_mode = str(animations.get("loop_mode", "loop"))
	use_frame_durations = bool(animations.get("use_frame_durations", false))
	metadata = doc.get("metadata", {}).duplicate(true)
	_normalize_actions()
	structure_changed.emit()
	return true
