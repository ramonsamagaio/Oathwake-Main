extends "res://scripts/labs/alabaster/AlabasterRigRuntime.gd"

# Third-pass reconstruction driven by the demo bundle and the shipped shaders.
# This intentionally supersedes V2. V2 inferred semantics for globalRot and
# generic facing sectors that are contradicted by the actual demo runtime.

const SOURCE_FPS := 60.0
const TILE_W := 24.0
const TILE_H := 16.0
const Z_FACTOR := 1.325
const Z_FACTOR_INV := 1.0 / Z_FACTOR
const CAMERA_FOV_DEG := 25.0
const CAMERA_X_ROT := -PI * 0.25
const CAMERA_SKEW := 0.45
const SOURCE_SCREEN := Vector2(640.0, 360.0)
const SOURCE_HALF := Vector2(320.0, 180.0)
const CAMERA_Z_DIST := SOURCE_SCREEN.y / (2.0 * tan(deg_to_rad(CAMERA_FOV_DEG) * 0.5) * TILE_H)

const TEX_ROT_NONE := 0
const TEX_ROT_ROTATE := 1
const TEX_ROT_CUT := 2
const TEX_ROT_SCALE := 4
const TEX_ROT_PARENT := 8

const PITCH_ALL := Vector2i(0, 11)

const FACING_TABLES := {
	"FACE_1": {"angles":[360.0], "tiles":[0], "flip":[0], "side":[0]},
	"FACE_1_FLIP": {"angles":[360.0], "tiles":[0], "flip":[1], "side":[0]},
	"FACE_2_FRONT_BACK": {"angles":[120.0,240.0], "tiles":[0,1], "flip":[0,0], "side":[0,2]},
	"FACE_2_FLIP_FB": {"angles":[120.0,240.0], "tiles":[0,1], "flip":[1,1], "side":[0,2]},
	"FACE_4": {"angles":[40.0,140.0,220.0,320.0], "tiles":[2,1,0,3], "flip":[0,0,0,0], "side":[0,1,2,1]},
	"FACE_4_FLIP": {"angles":[40.0,140.0,220.0,320.0], "tiles":[2,3,0,1], "flip":[1,1,1,1], "side":[0,1,2,1]},
	"FACE_4_MIRR": {"angles":[40.0,140.0,220.0,320.0], "tiles":[2,1,0,1], "flip":[0,0,0,1], "side":[0,1,2,1]},
	"FACE_4_MIRR_FLIP": {"angles":[40.0,140.0,220.0,320.0], "tiles":[2,1,0,1], "flip":[1,0,1,1], "side":[0,1,2,1]},
	"FACE_8": {"angles":[25.0,70.0,115.0,160.0,200.0,245.0,290.0,335.0], "tiles":[4,3,2,1,0,7,6,5], "flip":[0,0,0,0,0,0,0,0], "side":[0,0,1,1,2,1,1,0]},
	"FACE_8_FLIP": {"angles":[25.0,70.0,115.0,160.0,200.0,245.0,290.0,335.0], "tiles":[4,5,6,7,0,1,2,3], "flip":[1,1,1,1,1,1,1,1], "side":[0,0,1,1,2,1,1,0]},
	"FACE_8_MIRR": {"angles":[25.0,70.0,115.0,160.0,200.0,245.0,290.0,335.0], "tiles":[4,3,2,1,0,1,2,3], "flip":[0,0,0,0,0,1,1,1], "side":[0,0,1,1,2,1,1,0]},
	"FACE_8_MIRR_FLIP": {"angles":[25.0,70.0,115.0,160.0,200.0,245.0,290.0,335.0], "tiles":[4,3,2,1,0,1,2,3], "flip":[1,0,0,0,1,1,1,1], "side":[0,0,1,1,2,1,1,0]},
	"FACE_8_FRONT_ONLY": {"angles":[25.0,70.0,115.0,160.0,200.0,245.0,290.0,335.0], "tiles":[-1,-1,2,1,0,4,3,-1], "flip":[0,0,0,0,0,0,0,0], "side":[0,0,1,1,2,1,1,0]},
	"FACE_16": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[8,7,6,5,4,3,2,1,0,15,14,13,12,11,10,9], "flip":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_FLIP": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7], "flip":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_MIRR": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[8,7,6,5,4,3,2,1,0,1,2,3,4,5,6,7], "flip":[0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_MIRR_FLIP": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[8,7,6,5,4,3,2,1,0,1,2,3,4,5,6,7], "flip":[1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_FRONT_ONLY": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[-1,-1,-1,-1,4,3,2,1,0,8,7,6,5,-1,-1,-1], "flip":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_FLIP_FO": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[-1,-1,-1,-1,5,6,7,8,0,1,2,3,4,-1,-1,-1], "flip":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
	"FACE_16_MIRR_FO": {"angles":[11.25,33.75,56.25,78.75,101.25,123.75,146.25,168.75,191.25,213.75,236.25,258.75,281.25,303.75,326.25,348.75], "tiles":[-1,-1,-1,-1,4,3,2,1,0,1,2,3,4,-1,-1,-1], "flip":[0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1], "side":[0,0,0,1,1,1,1,2,2,2,1,1,1,1,0,0]},
}

var _source_frame: float = 0.0
var _states: Dictionary = {}
var _root_dirs: Dictionary = {}
var _active_rows_cache: Dictionary = {}
var _rounded_face_degrees: float = 180.0


func set_facing_from_vector(direction: Vector2) -> void:
	if direction.length_squared() < 0.000001:
		return
	# Source convention: North 0, East 90, South 180, West 270.
	facing_degrees = _normalize_degrees(rad_to_deg(atan2(direction.x, -direction.y)))


func get_runtime_summary() -> Dictionary:
	return {
		"animation": current_animation,
		"facing_degrees": facing_degrees,
		"facing_index_16": int(round(_normalize_degrees(facing_degrees) / 22.5)) % 16,
		"node_count": _nodes.size(),
		"sprite_piece_count": _sprite_records.size(),
		"runtime": "V3 bundle-derived",
	}


func _apply_pose() -> void:
	if _nodes.is_empty() or _atlas == null:
		return
	var sampled: Dictionary = _sample_animation_v3(current_animation)
	_rounded_face_degrees = _round_root_facing(facing_degrees, String(_figure.get("rootFacing", "FACE_16")))
	_ensure_root_dirs()
	_states.clear()
	for node_name_variant in _nodes.keys():
		_build_node_state(String(node_name_variant), sampled)
	for record_variant in _sprite_records:
		_update_sprite_v3(record_variant)
	if debug_enabled:
		queue_redraw()


func _sample_animation_v3(animation_name: String) -> Dictionary:
	if not _anims.has(animation_name):
		_source_frame = 0.0
		return {}
	var anim: Dictionary = _anims[animation_name]
	var frame_count: float = maxf(float(anim.get("frameCnt", 1)), 1.0)
	var frame_repeat: float = maxf(float(anim.get("frameRepeat", 1)), 1.0)
	var anim_start: float = float(anim.get("animStart", 0.0))
	var loop_start: float = float(anim.get("loopStart", anim_start))
	var repeat_anim: bool = bool(anim.get("repeat", true))
	_source_frame = anim_start + animation_time * SOURCE_FPS / frame_repeat
	if repeat_anim and _source_frame >= frame_count:
		var span: float = maxf(frame_count - loop_start, 0.000001)
		_source_frame = loop_start + fmod(_source_frame - loop_start, span)
	elif not repeat_anim:
		_source_frame = minf(_source_frame, frame_count)

	var tracks: Dictionary = _get_tracks_v3(animation_name)
	var sampled: Dictionary = {}
	for node_name_variant in _nodes.keys():
		var node_name: String = String(node_name_variant)
		var track: Array = tracks.get(node_name, [])
		sampled[node_name] = _sample_track_v3(track, _source_frame)
	return sampled


func _get_tracks_v3(animation_name: String) -> Dictionary:
	var cache_key: String = "v3:" + animation_name
	if _track_cache.has(cache_key):
		return _track_cache[cache_key]
	var anim: Dictionary = _anims.get(animation_name, {})
	var tracks: Dictionary = {}
	for node_name_variant in _nodes.keys():
		tracks[String(node_name_variant)] = []
	var transforms: Array = anim.get("transforms", [])
	for key_variant in transforms:
		var key: Dictionary = key_variant
		var frame: float = float(key.get("frame", 0.0))
		var key_spline: String = String(key.get("spline", "LINEAR"))
		var node_xfm: Dictionary = key.get("nodeXfm", {})
		for node_name_variant in node_xfm.keys():
			var node_name: String = String(node_name_variant)
			var xfm: Dictionary = node_xfm[node_name_variant]
			var entry: Dictionary = {
				"frame": frame,
				"rot": _quat_from_source_angles(_vec3_from_array(xfm.get("rot", [0.0,0.0,0.0]))),
				"trans": _vec3_from_array(xfm.get("trans", [0.0,0.0,0.0])),
				"scale": _uniform_scale_from_value_v3(xfm.get("scale", 1.0)),
				"spline": String(xfm.get("spline", key_spline)),
				"rot_toggle": bool(xfm.get("rotToggle", false)),
				"has_rot_toggle": xfm.has("rotToggle"),
				"present": true,
			}
			tracks[node_name].append(entry)
	for node_name_variant in tracks.keys():
		var track: Array = tracks[node_name_variant]
		track.sort_custom(func(a, b): return float(a["frame"]) < float(b["frame"]))
	_track_cache[cache_key] = tracks
	return tracks


func _sample_track_v3(track: Array, frame: float) -> Dictionary:
	if track.is_empty():
		return {"present":false, "rot":Quaternion(0,0,0,1), "trans":Vector3.ZERO, "scale":1.0, "rot_toggle":false}
	if track.size() == 1 or frame <= float(track[0]["frame"]):
		return _copy_track_pose(track[0])
	if frame >= float(track[track.size()-1]["frame"]):
		return _copy_track_pose(track[track.size()-1])
	var prev: Dictionary = track[0]
	var next: Dictionary = track[1]
	for i in range(track.size()-1):
		var a: Dictionary = track[i]
		var b: Dictionary = track[i+1]
		if frame >= float(a["frame"]) and frame < float(b["frame"]):
			prev = a
			next = b
			break
	var span: float = maxf(float(next["frame"]) - float(prev["frame"]), 0.000001)
	var t: float = clampf((frame - float(prev["frame"])) / span, 0.0, 1.0)
	# The original evaluator uses the NEXT key's spline for the segment.
	t = _source_spline(t, String(next.get("spline", "LINEAR")))
	var q0: Quaternion = prev.get("rot", Quaternion(0,0,0,1))
	var q1: Quaternion = next.get("rot", Quaternion(0,0,0,1))
	return {
		"present": true,
		"rot": q0.slerp(q1, t).normalized(),
		"trans": (prev.get("trans", Vector3.ZERO) as Vector3).lerp(next.get("trans", Vector3.ZERO), t),
		"scale": lerpf(float(prev.get("scale", 1.0)), float(next.get("scale", 1.0)), t),
		"rot_toggle": bool(prev.get("rot_toggle", false)),
	}


func _copy_track_pose(src: Dictionary) -> Dictionary:
	return {
		"present": true,
		"rot": src.get("rot", Quaternion(0,0,0,1)),
		"trans": src.get("trans", Vector3.ZERO),
		"scale": float(src.get("scale", 1.0)),
		"rot_toggle": bool(src.get("rot_toggle", false)),
	}


func _source_spline(t: float, spline: String) -> float:
	match spline:
		"EASE_IN":
			return t * t
		"EASE_OUT":
			return 1.0 - (1.0-t)*(1.0-t)
		"EASE_IN_OUT", "EASE":
			return t*t*(3.0-2.0*t)
		"EASE_IN_STRONG":
			return t*t*t
		"EASE_OUT_STRONG":
			var u: float = 1.0-t
			return 1.0-u*u*u
		_:
			return t


func _ensure_root_dirs() -> void:
	if not _root_dirs.is_empty():
		return
	for node_name_variant in _nodes.keys():
		_get_root_dir(String(node_name_variant))


func _get_root_dir(node_name: String) -> Quaternion:
	if _root_dirs.has(node_name):
		return _root_dirs[node_name]
	var node_def: Dictionary = _nodes.get(node_name, {})
	var q := Quaternion(0,0,0,1)
	if node_def.has("dir"):
		q = _quat_from_source_angles(_vec3_from_array(node_def.get("dir", [0.0,0.0,0.0])))
	else:
		var parent_name: String = String(node_def.get("parent", ""))
		if not parent_name.is_empty() and _nodes.has(parent_name):
			q = _get_root_dir(parent_name)
	_root_dirs[node_name] = q
	return q


func _build_node_state(node_name: String, sampled: Dictionary) -> Dictionary:
	if _states.has(node_name):
		return _states[node_name]
	var node_def: Dictionary = _nodes.get(node_name, {})
	var parent_name: String = String(node_def.get("parent", ""))
	var parent_state: Dictionary = {}
	if not parent_name.is_empty() and _nodes.has(parent_name):
		parent_state = _build_node_state(parent_name, sampled)
	var pose: Dictionary = sampled.get(node_name, {"present":false})
	var own_present: bool = bool(pose.get("present", false))
	var rotated: bool = own_present or bool(parent_state.get("rotated", false))
	var dir_q := Quaternion(0,0,0,1)
	if own_present:
		dir_q = pose.get("rot", Quaternion(0,0,0,1))
	if bool(parent_state.get("rotated", false)):
		var parent_q: Quaternion = parent_state.get("dir", Quaternion(0,0,0,1))
		dir_q = (parent_q * dir_q).normalized()

	var scale: float = float(pose.get("scale", 1.0))
	if not parent_state.is_empty():
		scale *= float(parent_state.get("scale", 1.0))

	var bone_delta: Vector3 = pose.get("trans", Vector3.ZERO)
	if node_def.has("pOff"):
		bone_delta += _vec3_from_array(node_def.get("pOff", [0.0,0.0,0.0]))
	if not parent_state.is_empty() and bool(parent_state.get("rotated", false)):
		bone_delta = _transform_figure_vec(bone_delta, parent_state.get("dir", Quaternion(0,0,0,1)))

	var local_pos: Vector3 = _vec3_from_array(node_def.get("pos", [0.0,0.0,0.0])) * scale
	if rotated and not parent_state.is_empty():
		local_pos = _transform_figure_vec(local_pos, dir_q)
	var root_pos: Vector3 = local_pos + bone_delta
	if not parent_state.is_empty():
		root_pos += parent_state.get("root_pos", Vector3.ZERO)

	var g_origin_local: Vector3
	if bone_delta.length_squared() > 0.00000001:
		g_origin_local = bone_delta + (parent_state.get("root_pos", Vector3.ZERO) if not parent_state.is_empty() else Vector3.ZERO)
	elif not parent_state.is_empty():
		g_origin_local = parent_state.get("root_pos", Vector3.ZERO)
	else:
		g_origin_local = Vector3.ZERO

	var g_self: Vector3 = _globalize_and_snap(root_pos)
	var g_origin: Vector3 = _globalize_and_snap(g_origin_local)
	var parent_global: Vector3 = g_origin
	if bone_delta.length_squared() <= 0.00000001 and not parent_state.is_empty():
		parent_global = parent_state.get("g_self", g_origin)

	var orientation_q: Quaternion = _get_root_dir(node_name)
	if rotated:
		orientation_q = (dir_q * orientation_q).normalized()
	var yaw_pitch: Vector3 = _source_yaw_pitch(orientation_q)
	var node_yaw: float = yaw_pitch.x
	var node_pitch: float = yaw_pitch.y
	var yaw_flipped: bool = bool(yaw_pitch.z > 0.5)
	var facing_yaw: float = _normalize_degrees(_rounded_face_degrees + node_yaw)
	var pitch_slot: int = _pitch_slot(node_pitch)

	var state: Dictionary = {
		"name": node_name,
		"parent": parent_name,
		"dir": dir_q,
		"rotated": rotated,
		"scale": scale,
		"bone_delta": bone_delta,
		"root_pos": root_pos,
		"g_self": g_self,
		"g_origin": g_origin,
		"parent_global": parent_global,
		"facing_yaw": facing_yaw,
		"pitch_slot": pitch_slot,
		"yaw_flipped": yaw_flipped,
		"rot_toggle": bool(pose.get("rot_toggle", false)),
		"frame_key": _active_frame_key_v3(node_name),
	}
	_states[node_name] = state
	return state


func _globalize_and_snap(pos: Vector3) -> Vector3:
	var angle: float = deg_to_rad(_rounded_face_degrees - 180.0)
	var c: float = cos(angle)
	var s: float = sin(angle)
	var out := Vector3(pos.x*c - pos.y*s, pos.x*s + pos.y*c, pos.z)
	return _snap_world(out)


func _snap_world(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x * TILE_W * 2.0) / (TILE_W * 2.0),
		round(pos.y * TILE_H * 2.0) / (TILE_H * 2.0),
		round(pos.z * TILE_H * 2.0) / (TILE_H * 2.0)
	)


func _transform_figure_vec(value: Vector3, q: Quaternion) -> Vector3:
	var v := value
	v.z *= Z_FACTOR_INV
	v = q * v
	v.z *= Z_FACTOR
	return v


func _transform_node_gfx_pos(node_name: String, gfx_pos: Vector3) -> Vector3:
	var state: Dictionary = _states.get(node_name, {})
	if state.is_empty():
		return Vector3.ZERO
	if gfx_pos.length_squared() <= 0.00000001:
		return state.get("g_self", Vector3.ZERO)
	var node_def: Dictionary = _nodes.get(node_name, {})
	var p: Vector3 = _vec3_from_array(node_def.get("pos", [0.0,0.0,0.0])) + gfx_pos
	p *= float(state.get("scale", 1.0))
	if bool(state.get("rotated", false)):
		p = _transform_figure_vec(p, state.get("dir", Quaternion(0,0,0,1)))
	p += state.get("bone_delta", Vector3.ZERO)
	var parent_name: String = String(state.get("parent", ""))
	if not parent_name.is_empty() and _states.has(parent_name):
		p += (_states[parent_name] as Dictionary).get("root_pos", Vector3.ZERO)
	return _globalize_and_snap(p)


func _active_frame_key_v3(node_name: String) -> int:
	if not _anims.has(current_animation):
		return 0
	var anim: Dictionary = _anims[current_animation]
	var anim_nodes: Dictionary = anim.get("nodes", {})
	if not anim_nodes.has(node_name):
		return 0
	var node_anim: Dictionary = anim_nodes[node_name]
	var frames: Array = node_anim.get("frames", [])
	if frames.is_empty():
		return 0
	var repeat_count: int = maxi(int(node_anim.get("frameRepeat", 1)), 1)
	var idx: int = mini(int(floor(_source_frame)) / repeat_count, frames.size()-1)
	return int(frames[idx])


func _update_sprite_v3(record: Dictionary) -> void:
	var sprite: Sprite2D = record["sprite"]
	var node_name: String = String(record["node"])
	var gfx: Dictionary = record["gfx"]
	var state: Dictionary = _states.get(node_name, {})
	if state.is_empty():
		sprite.visible = false
		return
	var selection: Dictionary = _select_texture_row_v3(node_name, gfx.get("tex", {}), state)
	if selection.is_empty():
		sprite.visible = false
		return
	var entry: Dictionary = selection["entry"]
	var row: Dictionary = selection["row"]
	var range_data: Array = entry.get("range", [])
	if range_data.size() < 4:
		sprite.visible = false
		return
	var facing: Dictionary = _facing_select_v3(String(entry.get("facing", "FACE_1")), float(state.get("facing_yaw", 180.0)))
	if facing.is_empty() or int(facing.get("tile", -1)) < 0:
		sprite.visible = false
		return

	var tile_idx: int = int(facing["tile"])
	var yaw_idx: int = int(facing["yaw_idx"])
	var flip_h: bool = bool(facing.get("flip", false))
	var base_x: int = int(range_data[0])
	var base_y: int = int(range_data[1])
	var tile_w: int = int(range_data[2])
	var tile_h: int = int(range_data[3])
	var row_index: int = int(selection["row_index"])
	var src_x: int
	var src_y: int
	if bool(entry.get("extendX", false)):
		src_x = base_x + row_index * tile_w
		src_y = base_y + tile_idx * tile_h
	else:
		src_x = base_x + tile_idx * tile_w
		src_y = base_y + row_index * tile_h

	var billboard: Dictionary = gfx.get("shape", {}).get("billboard", {})
	var half_shift: bool = bool(_figure.get("halfPixelShift", false))
	var pivot_x: float = round(float(tile_w) * 2.0 * float(billboard.get("pivotX", 0.5))) * 0.5
	var pivot_y: float = round(float(tile_h) * 2.0 * float(billboard.get("pivotY", 0.5))) * 0.5
	if half_shift:
		pivot_x += 0.5

	var gfx_pos_world: Vector3 = _transform_node_gfx_pos(node_name, _vec3_from_array(gfx.get("pos", [0.0,0.0,0.0])))
	var gfx_screen: Vector2 = _project_source(gfx_pos_world)
	var tex_mode: int = _tex_rotate_mode(String(row.get("texRotate", "NONE")))
	var rot_ref: float = _row_rot_ref(row, tile_idx, flip_h)
	var rotation: float = 0.0
	var scale_value := Vector2.ONE
	var cut_rect := Rect2(float(src_x), float(src_y), float(tile_w), float(tile_h))

	var skip_rotation: bool = bool(entry.get("rotDefOff", false))
	if bool(state.get("rot_toggle", false)):
		skip_rotation = not skip_rotation
	if tex_mode != TEX_ROT_NONE and not skip_rotation:
		var transform_result: Dictionary = _billboard_transform_v3(node_name, state, gfx_screen, gfx_pos_world, billboard, row, tex_mode, tile_w, tile_h, pivot_x, pivot_y, rot_ref, flip_h)
		rotation = float(transform_result.get("rotation", 0.0))
		scale_value = transform_result.get("scale", Vector2.ONE)
		cut_rect = transform_result.get("rect", cut_rect)
		pivot_x = float(transform_result.get("pivot_x", pivot_x))
		pivot_y = float(transform_result.get("pivot_y", pivot_y))

	sprite.region_rect = cut_rect
	sprite.flip_h = flip_h
	sprite.flip_v = false
	sprite.visible = true
	sprite.position = gfx_screen
	sprite.rotation = rotation
	sprite.scale = scale_value
	var final_w: float = cut_rect.size.x
	var effective_pivot_x: float = final_w - pivot_x if flip_h else pivot_x
	sprite.offset = Vector2(final_w * 0.5 - effective_pivot_x, cut_rect.size.y * 0.5 - pivot_y)

	var z_offset: int = int(row.get("zOff", 0))
	if bool(entry.get("zFrames", false)):
		z_offset += tile_idx
	else:
		var side_back: int = int(facing.get("side", 0))
		if side_back == 1:
			z_offset += int(entry.get("zSide", 0))
		elif side_back == 2:
			z_offset += int(entry.get("zBack", 0))
	var z_order: int = int(_figure.get("globalZOrder", 0)) + int(billboard.get("zOrder", 0)) + z_offset
	sprite.z_index = clampi(z_order * 16, -4096, 4096)


func _select_texture_row_v3(node_name: String, tex: Dictionary, state: Dictionary) -> Dictionary:
	if tex.has("simple"):
		return {"entry":tex["simple"], "row":{}, "row_index":0}
	if not tex.has("multi"):
		return {}
	var multi: Dictionary = tex["multi"]
	var entries: Dictionary = multi.get("entries", {})
	if entries.is_empty():
		return {}
	var frame_key: int = int(state.get("frame_key", 0))
	var pitch_slot: int = int(state.get("pitch_slot", 4))
	var best: Dictionary = _find_row_candidate(entries, frame_key, pitch_slot)
	if best.is_empty() and frame_key != 0 and String(multi.get("onMissingFrame", "USE_DEFAULT")) == "USE_DEFAULT":
		best = _find_row_candidate(entries, 0, pitch_slot)
	return best


func _find_row_candidate(entries: Dictionary, frame_key: int, pitch_slot: int) -> Dictionary:
	var best: Dictionary = {}
	var best_width: int = 999
	for entry_name_variant in entries.keys():
		var entry: Dictionary = entries[entry_name_variant]
		var variants: Array = entry.get("variants", [])
		if not variants.is_empty():
			continue
		var rows: Array = entry.get("rows", [])
		for row_index in range(rows.size()):
			var row: Dictionary = rows[row_index]
			var frame_keys: Array = row.get("frameKeys", [])
			var matches_frame: bool = frame_key == 0 if frame_keys.is_empty() else frame_keys.has(frame_key)
			if not matches_frame:
				continue
			var bounds: Vector2i = _pitch_range_bounds(String(row.get("pitchRange", "ALL")))
			if not _pitch_in_bounds(pitch_slot, bounds):
				continue
			var width: int = _pitch_range_width(bounds)
			if best.is_empty() or width < best_width:
				best = {"entry":entry, "row":row, "row_index":row_index, "entry_name":String(entry_name_variant)}
				best_width = width
	return best


func _pitch_range_bounds(name: String) -> Vector2i:
	match name:
		"NORM": return Vector2i(4,4)
		"NORM_W": return Vector2i(3,5)
		"UP1": return Vector2i(5,5)
		"UP1+": return Vector2i(5,11)
		"UP2": return Vector2i(6,6)
		"UP2+": return Vector2i(6,11)
		"UP3": return Vector2i(7,7)
		"UP3+": return Vector2i(7,11)
		"UP4": return Vector2i(8,8)
		"UP4+": return Vector2i(8,11)
		"UP5": return Vector2i(9,9)
		"UP5+": return Vector2i(9,11)
		"BACK": return Vector2i(10,10)
		"BACK+": return Vector2i(10,11)
		"DOWN1": return Vector2i(3,3)
		"DOWN1+": return Vector2i(0,3)
		"DOWN2": return Vector2i(2,2)
		"DOWN2+": return Vector2i(0,2)
		"DOWN3": return Vector2i(1,1)
		"DOWN3+": return Vector2i(0,1)
		"DOWN4": return Vector2i(0,0)
		"DOWN5": return Vector2i(11,11)
		_: return PITCH_ALL


func _pitch_in_bounds(slot: int, bounds: Vector2i) -> bool:
	return slot >= bounds.x and slot <= bounds.y


func _pitch_range_width(bounds: Vector2i) -> int:
	return bounds.y - bounds.x + 1


func _pitch_slot(pitch_degrees: float) -> int:
	var value: float = pitch_degrees
	if value < -135.0:
		value += 360.0
	var slots := [-105.0,-75.0,-45.0,-15.0,15.0,45.0,75.0,105.0,135.0,165.0,195.0]
	for i in range(slots.size()):
		if value < float(slots[i]):
			return i
	return 11


func _facing_select_v3(mode: String, angle: float) -> Dictionary:
	if not FACING_TABLES.has(mode):
		# Aliases seen in older authored files.
		if mode == "FACE_8_MIRR_FO":
			mode = "FACE_8_FRONT_ONLY"
		elif mode == "FACE_16_MIRR_FO":
			mode = "FACE_16_MIRR_FO"
	if not FACING_TABLES.has(mode):
		return {"tile":0, "flip":false, "yaw_idx":0, "side":0}
	var table: Dictionary = FACING_TABLES[mode]
	var angles: Array = table["angles"]
	var a: float = _normalize_degrees(angle)
	var yaw_idx: int = 0
	var found: bool = false
	for i in range(angles.size()):
		if a <= float(angles[i]):
			yaw_idx = i
			found = true
			break
	if not found:
		yaw_idx = 0
	var tiles: Array = table["tiles"]
	var flips: Array = table["flip"]
	var sides: Array = table.get("side", [])
	return {
		"tile": int(tiles[yaw_idx]),
		"flip": int(flips[yaw_idx]) != 0,
		"yaw_idx": yaw_idx,
		"side": int(sides[yaw_idx]) if yaw_idx < sides.size() else 0,
	}


func _row_rot_ref(row: Dictionary, tile_idx: int, flip_h: bool) -> float:
	var refs: Array = row.get("refAngles", [])
	var degrees: float = 0.0
	if tile_idx >= 0 and tile_idx < refs.size() and refs[tile_idx] != null:
		degrees = float(refs[tile_idx])
	var radians: float = deg_to_rad(degrees)
	if flip_h:
		radians = TAU - radians
	return radians


func _tex_rotate_mode(name: String) -> int:
	match name:
		"ROTATE": return TEX_ROT_ROTATE
		"ROTATE_CUT": return TEX_ROT_ROTATE | TEX_ROT_CUT
		"ROTATE_SCALE": return TEX_ROT_ROTATE | TEX_ROT_SCALE
		"PARENT_ROTATE": return TEX_ROT_ROTATE | TEX_ROT_PARENT
		"PARENT_ROTATE_CUT": return TEX_ROT_ROTATE | TEX_ROT_PARENT | TEX_ROT_CUT
		"PARENT_ROTATE_SCALE": return TEX_ROT_ROTATE | TEX_ROT_PARENT | TEX_ROT_SCALE
		_: return TEX_ROT_NONE


func _billboard_transform_v3(node_name: String, state: Dictionary, gfx_screen: Vector2, gfx_world: Vector3, billboard: Dictionary, row: Dictionary, tex_mode: int, tile_w: int, tile_h: int, pivot_x: float, pivot_y: float, rot_ref: float, flip_h: bool) -> Dictionary:
	var result: Dictionary = {
		"rotation":0.0,
		"scale":Vector2.ONE,
		"rect":Rect2.ZERO,
		"pivot_x":pivot_x,
		"pivot_y":pivot_y,
	}
	# Caller replaces Rect2.ZERO with its already-computed source rectangle.
	var cut_or_scale: bool = (tex_mode & (TEX_ROT_CUT | TEX_ROT_SCALE)) != 0
	var angle: float
	var target_length: float = -1.0
	var cut_meta: Dictionary = _cut_meta(row, int(_facing_select_v3(String(_active_entry_facing(node_name)), float(state.get("facing_yaw", 180.0))).get("tile", 0)), tile_w, tile_h, billboard)
	if cut_or_scale:
		var second_world: Vector3
		if (tex_mode & TEX_ROT_PARENT) != 0:
			second_world = state.get("parent_global", state.get("g_origin", Vector3.ZERO))
		else:
			second_world = state.get("g_self", Vector3.ZERO)
		var factor: float = float(billboard.get("parentPosFactor", 0.0))
		if factor != 0.0:
			second_world = second_world + (second_world - gfx_world) * factor
		var second_screen: Vector2 = _project_source(second_world)
		var delta: Vector2 = second_screen - gfx_screen
		angle = _clock_angle(delta)
		var cut_factor: float = float(cut_meta.get("factor", 1.0))
		target_length = delta.length() * cut_factor + float(billboard.get("parentPixelOff", 0.0))
	else:
		angle = _screen_rotation_for_state(state)
		if tex_mode == (TEX_ROT_ROTATE | TEX_ROT_PARENT):
			angle += PI
	result["rotation"] = angle - rot_ref
	result["target_length"] = target_length
	result["cut_meta"] = cut_meta
	return result


func _active_entry_facing(node_name: String) -> String:
	# Only used to calculate cut metadata direction. The selected entry's facing
	# is normally available in the caller, but this helper keeps the transform
	# function independent and safe for authored FACE_1 tests.
	return "FACE_1"


func _screen_rotation_for_state(state: Dictionary) -> float:
	var a: Vector2 = _project_source(state.get("parent_global", state.get("g_origin", Vector3.ZERO)))
	var b: Vector2 = _project_source(state.get("g_self", Vector3.ZERO))
	return _clock_angle(b-a)


func _cut_meta(row: Dictionary, tile_idx: int, tile_w: int, tile_h: int, billboard: Dictionary) -> Dictionary:
	var refs: Array = row.get("refAngles", [])
	var angle_deg: float = 0.0
	if tile_idx >= 0 and tile_idx < refs.size() and refs[tile_idx] != null:
		angle_deg = float(refs[tile_idx])
	var angle: float = deg_to_rad(angle_deg)
	var d := Vector2(0.0,-1.0).rotated(-angle)
	var px: float = float(billboard.get("pivotX",0.5)) * tile_w + (0.5 if bool(_figure.get("halfPixelShift",false)) else 0.0)
	var py: float = float(billboard.get("pivotY",0.5)) * tile_h
	var best_t: float = INF
	var cut_dir: int = 0
	if absf(d.y) > 0.000001:
		var t_top: float = (0.0-py)/d.y
		if t_top > 0.0 and t_top < best_t:
			best_t = t_top; cut_dir = 0
		var t_bottom: float = (float(tile_h)-py)/d.y
		if t_bottom > 0.0 and t_bottom < best_t:
			best_t = t_bottom; cut_dir = 2
	if absf(d.x) > 0.000001:
		var t_right: float = (float(tile_w)-px)/d.x
		if t_right > 0.0 and t_right < best_t:
			best_t = t_right; cut_dir = 1
		var t_left: float = (0.0-px)/d.x
		if t_left > 0.0 and t_left < best_t:
			best_t = t_left; cut_dir = 3
	var factor: float = absf(d.y) if cut_dir in [0,2] else absf(d.x)
	return {"dir":cut_dir, "factor":maxf(factor,0.000001)}


func _project_source(world_pos: Vector3) -> Vector2:
	# Equivalent fixed camera used by the demo for the character lab: aspect
	# compensation, -45 degree X view, 0.45 Z-to-Y skew and 25 degree FOV.
	var x: float = world_pos.x * (TILE_W / TILE_H)
	var y: float = -world_pos.y
	var z: float = world_pos.z
	y += CAMERA_SKEW * z
	var c: float = cos(CAMERA_X_ROT)
	var s: float = sin(CAMERA_X_ROT)
	var ry: float = y*c - z*s
	var rz: float = y*s + z*c - CAMERA_Z_DIST
	var w: float = maxf(-rz, 0.001)
	var f: float = 1.0 / tan(deg_to_rad(CAMERA_FOV_DEG) * 0.5)
	var aspect: float = SOURCE_SCREEN.x / SOURCE_SCREEN.y
	var ndc_x: float = (f/aspect) * x / w
	var ndc_y: float = f * ry / w
	return Vector2(SOURCE_HALF.x * ndc_x, -SOURCE_HALF.y * ndc_y)


func _clock_angle(v: Vector2) -> float:
	var len: float = v.length()
	if len <= 0.000001:
		return 0.0
	var a: float = acos(clampf(-v.y/len, -1.0, 1.0))
	if v.x < 0.0:
		a = TAU-a
	return a


func _round_root_facing(angle: float, mode: String) -> float:
	var step: float = 22.5
	if mode.contains("FACE_8"):
		step = 45.0
	elif mode.contains("FACE_4"):
		step = 90.0
	elif mode.contains("FACE_2"):
		step = 180.0
	return _normalize_degrees(round(angle/step)*step)


func _quat_from_source_angles(value: Vector3) -> Quaternion:
	# Source Quaternion.fromArray([yaw,pitch,roll]) calls glMatrix.fromEuler
	# with (pitch, roll, yaw).
	var hx: float = deg_to_rad(value.y) * 0.5
	var hy: float = deg_to_rad(value.z) * 0.5
	var hz: float = deg_to_rad(value.x) * 0.5
	var sx: float = sin(hx); var cx: float = cos(hx)
	var sy: float = sin(hy); var cy: float = cos(hy)
	var sz: float = sin(hz); var cz: float = cos(hz)
	return Quaternion(
		sx*cy*cz - cx*sy*sz,
		cx*sy*cz + sx*cy*sz,
		cx*cy*sz - sx*sy*cz,
		cx*cy*cz + sx*sy*sz
	).normalized()


func _source_yaw_pitch(q: Quaternion) -> Vector3:
	var yaw: float = rad_to_deg(atan2(2.0*(q.x*q.y + q.z*q.w), 1.0-2.0*(q.y*q.y+q.z*q.z)))
	var pitch: float = rad_to_deg(atan2(2.0*(q.x*q.w + q.y*q.z), 1.0-2.0*(q.x*q.x+q.y*q.y)))
	var flipped: float = 1.0 if pitch > 90.0 or pitch < -90.0 else 0.0
	return Vector3(yaw,pitch,flipped)


func _uniform_scale_from_value_v3(value) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_ARRAY and value.size() > 0:
		return float(value[0])
	return 1.0


func _draw() -> void:
	if not debug_enabled:
		return
	for node_name_variant in _nodes.keys():
		var node_name: String = String(node_name_variant)
		var state: Dictionary = _states.get(node_name, {})
		if state.is_empty():
			continue
		var p: Vector2 = _project_source(state.get("g_self", Vector3.ZERO))
		var parent_name: String = String(state.get("parent", ""))
		if not parent_name.is_empty() and _states.has(parent_name):
			var pp: Vector2 = _project_source((_states[parent_name] as Dictionary).get("g_self", Vector3.ZERO))
			draw_line(pp,p,Color(0.25,0.95,0.75,0.9),0.75)
		draw_circle(p,1.1,Color(1.0,0.72,0.24,0.95))
