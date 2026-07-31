class_name SpritePoseModel
extends RefCounted

const DIRECTIONS := ["south", "north", "east", "west"]
const PARTS := ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]
const DEFAULT_POSITIONS := {
	"head": [0.0, -18.0],
	"torso": [0.0, 0.0],
	"left_arm": [-11.0, 0.0],
	"right_arm": [11.0, 0.0],
	"left_leg": [-4.0, 17.0],
	"right_leg": [4.0, 17.0],
}
const DEFAULT_Z := {
	"head": 5,
	"torso": 3,
	"left_arm": 4,
	"right_arm": 2,
	"left_leg": 1,
	"right_leg": 0,
}

var frames: Array = []
var part_library: Dictionary = {}
var canvas_size := Vector2i(64, 64)
var feet_y := 60
var fps := 8.0
var use_frame_durations := false
var character_name := "player"
var animation_name := "run"


func _init() -> void:
	reset()


func reset() -> void:
	part_library.clear()
	for direction in DIRECTIONS:
		part_library[direction] = empty_direction_library()
	frames = [default_frame("south")]


func empty_direction_library() -> Dictionary:
	var result := {}
	for part_name in PARTS:
		result[part_name] = ""
	return result


func default_frame(direction: String) -> Dictionary:
	var parts := {}
	for part_name in PARTS:
		parts[part_name] = default_part(part_name)
	return {
		"direction": direction if direction in DIRECTIONS else "south",
		"duration": 0.125,
		"parts": parts,
	}


func default_part(part_name: String) -> Dictionary:
	return {
		"position": DEFAULT_POSITIONS.get(part_name, [0.0, 0.0]).duplicate(),
		"rotation_degrees": 0.0,
		"pivot": [0.0, 0.0],
		"z_index": int(DEFAULT_Z.get(part_name, 0)),
		"visible": true,
	}


func normalize_frame(source: Dictionary) -> Dictionary:
	var direction := str(source.get("direction", "south"))
	var result := default_frame(direction)
	result["duration"] = maxf(0.01, float(source.get("duration", 0.125)))
	var source_parts: Dictionary = {}
	if source.get("parts", {}) is Dictionary:
		source_parts = source["parts"]
	var result_parts: Dictionary = result["parts"]
	for part_name in PARTS:
		if not source_parts.has(part_name) or not (source_parts[part_name] is Dictionary):
			continue
		var source_part: Dictionary = source_parts[part_name]
		var position := vector_from_value(source_part.get("position", DEFAULT_POSITIONS[part_name]))
		var pivot := vector_from_value(source_part.get("pivot", [0.0, 0.0]))
		result_parts[part_name] = {
			"position": [position.x, position.y],
			"rotation_degrees": float(source_part.get("rotation_degrees", 0.0)),
			"pivot": [pivot.x, pivot.y],
			"z_index": int(source_part.get("z_index", DEFAULT_Z[part_name])),
			"visible": bool(source_part.get("visible", true)),
		}
	return result


func normalize_library(source: Variant) -> Dictionary:
	var source_dict: Dictionary = {}
	if source is Dictionary:
		source_dict = source
	var result := {}
	for direction in DIRECTIONS:
		result[direction] = normalize_direction_library(source_dict.get(direction, {}))
	return result


func normalize_direction_library(source: Variant) -> Dictionary:
	var source_dict: Dictionary = {}
	if source is Dictionary:
		source_dict = source
	var result := {}
	for part_name in PARTS:
		result[part_name] = str(source_dict.get(part_name, ""))
	return result


func pose_document(frame_index: int) -> Dictionary:
	var frame: Dictionary = frames[frame_index]
	var direction := str(frame.get("direction", "south"))
	return {
		"format": "oathwake_sprite_pose",
		"format_version": 1,
		"canvas": canvas_document(),
		"direction_parts": part_library.get(direction, {}).duplicate(true),
		"frame": frame.duplicate(true),
	}


func cycle_document() -> Dictionary:
	return {
		"format": "oathwake_sprite_pose_cycle",
		"format_version": 1,
		"character": safe_name(character_name, "player"),
		"animation": safe_name(animation_name, "animation"),
		"canvas": canvas_document(),
		"playback": {
			"fps": fps,
			"use_frame_durations": use_frame_durations,
		},
		"part_library": part_library.duplicate(true),
		"frames": frames.duplicate(true),
	}


func canvas_document() -> Dictionary:
	return {
		"width": canvas_size.x,
		"height": canvas_size.y,
		"feet_y": feet_y,
	}


func apply_canvas_document(value: Variant) -> void:
	if value is not Dictionary:
		return
	canvas_size = Vector2i(
		clampi(int(value.get("width", 64)), 1, 2048),
		clampi(int(value.get("height", 64)), 1, 2048)
	)
	feet_y = clampi(int(value.get("feet_y", 60)), 0, canvas_size.y - 1)


func apply_pose_document(data: Dictionary, frame_index: int) -> bool:
	if data.get("frame", null) is not Dictionary:
		return false
	var frame := normalize_frame(data["frame"])
	frames[frame_index] = frame
	var direction := str(frame.get("direction", "south"))
	if data.get("direction_parts", null) is Dictionary:
		part_library[direction] = normalize_direction_library(data["direction_parts"])
	apply_canvas_document(data.get("canvas", {}))
	return true


func apply_cycle_document(data: Dictionary) -> bool:
	if data.get("frames", null) is not Array:
		return false
	var loaded_frames: Array = []
	for frame_data in data["frames"]:
		if frame_data is Dictionary:
			loaded_frames.append(normalize_frame(frame_data))
	if loaded_frames.is_empty():
		return false
	frames = loaded_frames
	part_library = normalize_library(data.get("part_library", {}))
	apply_canvas_document(data.get("canvas", {}))
	var playback: Dictionary = {}
	if data.get("playback", {}) is Dictionary:
		playback = data["playback"]
	fps = clampf(float(playback.get("fps", 8.0)), 1.0, 60.0)
	use_frame_durations = bool(playback.get("use_frame_durations", false))
	character_name = str(data.get("character", "player"))
	animation_name = str(data.get("animation", "animation"))
	return true


func frame_filename(index: int) -> String:
	var direction := safe_name(str(frames[index].get("direction", "south")), "south")
	return "%s_%s_%s_%02d.png" % [
		safe_name(character_name, "player"),
		safe_name(animation_name, "animation"),
		direction,
		index + 1,
	]


func sheet_filename() -> String:
	var direction := "mixed"
	if not frames.is_empty():
		direction = str(frames[0].get("direction", "south"))
		for frame in frames:
			if str(frame.get("direction", direction)) != direction:
				direction = "mixed"
				break
	return "%s_%s_%s_sheet.png" % [
		safe_name(character_name, "player"),
		safe_name(animation_name, "animation"),
		safe_name(direction, "mixed"),
	]


func pose_filename(index: int) -> String:
	return "%s_%s_pose_%02d.json" % [
		safe_name(character_name, "player"),
		safe_name(animation_name, "animation"),
		index + 1,
	]


func cycle_filename() -> String:
	return "%s_%s_cycle.json" % [
		safe_name(character_name, "player"),
		safe_name(animation_name, "animation"),
	]


func safe_name(value: String, fallback: String) -> String:
	var result := value.strip_edges().to_lower().to_snake_case()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]+")
	result = regex.sub(result, "_", true)
	while result.contains("__"):
		result = result.replace("__", "_")
	result = result.trim_prefix("_").trim_suffix("_")
	return fallback if result.is_empty() else result


func vector_from_value(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO
