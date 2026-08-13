extends "res://scripts/labs/alabaster/AlabasterRigRuntime.gd"

# Runtime rebuilt from the demo's bundle.js semantics.
# It intentionally ignores the earlier V2/V3 guesses and only implements
# behavior that is directly supported by the shipped runtime/shaders.

const SRC_FPS: float = 60.0
const TILE_W: float = 24.0
const TILE_H: float = 16.0
const Z_FACTOR: float = 1.325
const Z_FACTOR_INV: float = 1.0 / Z_FACTOR
const FOV_DEG: float = 25.0
const CAMERA_X_ROT: float = -PI * 0.25
const CAMERA_SKEW: float = 0.45
const SCREEN_W: float = 640.0
const SCREEN_H: float = 360.0
const CAMERA_Z: float = SCREEN_H / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5) * TILE_H)

const ROT_NONE: int = 0
const ROT_ROTATE: int = 1
const ROT_CUT: int = 2
const ROT_SCALE: int = 4
const ROT_PARENT: int = 8

var _src_frame: float = 0.0
var _rounded_face: float = 180.0
var _states: Dictionary = {}
var _root_dirs: Dictionary = {}


func set_facing_from_vector(direction: Vector2) -> void:
	if direction.length_squared() < 0.000001:
		return
	# Demo convention: north=0, east=90, south=180, west=270.
	facing_degrees = _normalize_degrees(rad_to_deg(atan2(direction.x, -direction.y)))


func get_runtime_summary() -> Dictionary:
	return {
		"animation": current_animation,
		"facing_degrees": facing_degrees,
		"facing_index_16": int(round(_normalize_degrees(facing_degrees) / 22.5)) % 16,
		"node_count": _nodes.size(),
		"sprite_piece_count": _sprite_records.size(),
		"runtime": "bundle-source",
	}


func _apply_pose() -> void:
	if _nodes.is_empty() or _atlas == null:
		return
	var sampled: Dictionary = _sample_animation_source(current_animation)
	_rounded_face = _round_root_face(facing_degrees, String(_figure.get("rootFacing", "FACE_16")))
	_ensure_root_dirs()
	_states.clear()
	for node_name_variant in _nodes.keys():
		_build_state(String(node_name_variant), sampled)
	for record_variant in _sprite_records:
		_update_sprite_source(record_variant)
	if debug_enabled:
		queue_redraw()


func _sample_animation_source(animation_name: String) -> Dictionary:
	if not _anims.has(animation_name):
		_src_frame = 0.0
		return {}
	var anim: Dictionary = _anims[animation_name]
	var frame_count: float = maxf(float(anim.get("frameCnt", 1.0)), 1.0)
	var frame_repeat: float = maxf(float(anim.get("frameRepeat", 1.0)), 1.0)
	var start_frame: float = float(anim.get("animStart", 0.0))
	var loop_frame: float = float(anim.get("loopStart", start_frame))
	var repeat_anim: bool = bool(anim.get("repeat", true))
	_src_frame = start_frame + animation_time * SRC_FPS / frame_repeat
	if repeat_anim and _src_frame >= frame_count:
		var span: float = maxf(frame_count - loop_frame, 0.000001)
		_src_frame = loop_frame + fmod(_src_frame - loop_frame, span)
	elif not repeat_anim:
		_src_frame = minf(_src_frame, frame_count)

	var tracks: Dictionary = _source_tracks(animation_name)
	var result: Dictionary = {}
	for node_name_variant in _nodes.keys():
		var node_name: String = String(node_name_variant)
		var track: Array = tracks.get(node_name, [])
		result[node_name] = _sample_source_track(track, _src_frame, frame_repeat)
	return result


func _source_tracks(animation_name: String) -> Dictionary:
	var cache_key: String = "source:" + animation_name
	if _track_cache.has(cache_key):
		return _track_cache[cache_key]
	var anim: Dictionary = _anims.get(animation_name, {})
	var result: Dictionary = {}
	for node_name_variant in _nodes.keys():
		result[String(node_name_variant)] = []
	var anim_repeat: float = maxf(float(anim.get("frameRepeat", 1.0)), 1.0)
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
				"rot": _source_quat(_vec3_from_array(xfm.get("rot", [0.0, 0.0, 0.0]))),
				"trans": _vec3_from_array(xfm.get("trans", [0.0, 0.0, 0.0])),
				"scale": _source_scale(xfm.get("scale", 1.0)),
				"spline": String(xfm.get("spline", key_spline)),
				"frame_repeat": maxf(float(xfm.get("frameRepeat", key.get("frameRepeat", 1.0))), 1.0),
				"rot_toggle": bool(xfm.get("rotToggle", false)),
				"present": true,
				"anim_repeat": anim_repeat,
			}
			result[node_name].append(entry)
	for node_name_variant in result.keys():
		var track: Array = result[node_name_variant]
		track.sort_custom(func(a, b): return float(a["frame"]) < float(b["frame"]))
	_track_cache[cache_key] = result
	return result


func _sample_source_track(track: Array, frame: float, anim_repeat: float) -> Dictionary:
	if track.is_empty():
		return _identity_pose(false)
	if track.size() == 1:
		return _pose_from_key(track[0])
	var prev: Dictionary = {}
	var next: Dictionary = {}
	for key_variant in track:
		var key: Dictionary = key_variant
		if float(key["frame"]) > frame:
			next = key
			break
		prev = key
	if prev.is_empty() or next.is_empty():
		return _pose_from_key(next if prev.is_empty() else prev)
	var local_frame: float = frame - float(prev["frame"])
	var next_repeat: float = maxf(float(next.get("frame_repeat", 1.0)), 1.0)
	if next_repeat != 1.0:
		var frame_step: float = next_repeat
		var source_half_frame: float = 0.5 / maxf(anim_repeat, 1.0)
		local_frame = floor((local_frame + source_half_frame) / frame_step) * frame_step
	var frame_delta: float = maxf(float(next["frame"]) - float(prev["frame"]), 0.000001)
	var weight: float = clampf(local_frame / frame_delta, 0.0, 1.0)
	weight = _source_spline(weight, String(next.get("spline", "LINEAR")))
	var q0: Quaternion = prev.get("rot", Quaternion(0.0, 0.0, 0.0, 1.0))
	var q1: Quaternion = next.get("rot", Quaternion(0.0, 0.0, 0.0, 1.0))
	var t0: Vector3 = prev.get("trans", Vector3.ZERO)
	var t1: Vector3 = next.get("trans", Vector3.ZERO)
	return {
		"present": true,
		"rot": q0.slerp(q1, weight).normalized(),
		"trans": t0.lerp(t1, weight),
		"scale": lerpf(float(prev.get("scale", 1.0)), float(next.get("scale", 1.0)), weight),
		"rot_toggle": bool(prev.get("rot_toggle", false)),
	}


func _identity_pose(present: bool) -> Dictionary:
	return {
		"present": present,
		"rot": Quaternion(0.0, 0.0, 0.0, 1.0),
		"trans": Vector3.ZERO,
		"scale": 1.0,
		"rot_toggle": false,
	}


func _pose_from_key(key: Dictionary) -> Dictionary:
	return {
		"present": true,
		"rot": key.get("rot", Quaternion(0.0, 0.0, 0.0, 1.0)),
		"trans": key.get("trans", Vector3.ZERO),
		"scale": float(key.get("scale", 1.0)),
		"rot_toggle": bool(key.get("rot_toggle", false)),
	}


func _source_spline(weight: float, name: String) -> float:
	match name:
		"EASE_IN":
			return weight * weight
		"EASE_OUT":
			var inv: float = 1.0 - weight
			return 1.0 - inv * inv
		"EASE_IN_OUT", "EASE":
			return weight * weight * (3.0 - 2.0 * weight)
		"EASE_IN_STRONG":
			return weight * weight * weight
		"EASE_OUT_STRONG":
			var inv2: float = 1.0 - weight
			return 1.0 - inv2 * inv2 * inv2
		_:
			return weight


func _ensure_root_dirs() -> void:
	if not _root_dirs.is_empty():
		return
	for node_name_variant in _nodes.keys():
		_root_dir(String(node_name_variant))


func _root_dir(node_name: String) -> Quaternion:
	if _root_dirs.has(node_name):
		return _root_dirs[node_name]
	var node_def: Dictionary = _nodes.get(node_name, {})
	var result := Quaternion(0.0, 0.0, 0.0, 1.0)
	if node_def.has("dir"):
		result = _source_quat(_vec3_from_array(node_def.get("dir", [0.0, 0.0, 0.0])))
	else:
		var parent_name: String = String(node_def.get("parent", ""))
		if not parent_name.is_empty() and _nodes.has(parent_name):
			result = _root_dir(parent_name)
	_root_dirs[node_name] = result
	return result


func _build_state(node_name: String, sampled: Dictionary) -> Dictionary:
	if _states.has(node_name):
		return _states[node_name]
	var node_def: Dictionary = _nodes.get(node_name, {})
	var parent_name: String = String(node_def.get("parent", ""))
	var parent_state: Dictionary = {}
	if not parent_name.is_empty() and _nodes.has(parent_name):
		parent_state = _build_state(parent_name, sampled)

	var pose: Dictionary = sampled.get(node_name, _identity_pose(false))
	var rotated: bool = bool(pose.get("present", false))
	var dir_q: Quaternion = Quaternion(0.0, 0.0, 0.0, 1.0)
	if rotated:
		dir_q = pose.get("rot", dir_q)

	var bone_delta: Vector3 = Vector3.ZERO
	if node_def.has("pOff"):
		bone_delta += _vec3_from_array(node_def.get("pOff", [0.0, 0.0, 0.0]))
	if rotated:
		bone_delta += pose.get("trans", Vector3.ZERO)

	var parent_rotated: bool = bool(parent_state.get("rotated", false))
	if bone_delta.length_squared() > 0.00000001 and parent_rotated:
		bone_delta = _figure_transform(bone_delta, parent_state.get("dir", Quaternion(0.0, 0.0, 0.0, 1.0)))

	var origin_local: Vector3
	if bone_delta.length_squared() > 0.00000001:
		origin_local = bone_delta
		if not parent_state.is_empty():
			origin_local += parent_state.get("root_pos", Vector3.ZERO)
	elif not parent_state.is_empty():
		origin_local = parent_state.get("root_pos", Vector3.ZERO)
	else:
		origin_local = Vector3.ZERO

	if parent_rotated:
		rotated = true
		var parent_q: Quaternion = parent_state.get("dir", Quaternion(0.0, 0.0, 0.0, 1.0))
		dir_q = (parent_q * dir_q).normalized()

	var scale: float = float(pose.get("scale", 1.0)) if bool(pose.get("present", false)) else 1.0
	var root_pos: Vector3 = _vec3_from_array(node_def.get("pos", [0.0, 0.0, 0.0]))
	if scale != 1.0:
		root_pos *= scale
	if rotated and not parent_name.is_empty():
		root_pos = _figure_transform(root_pos, dir_q)
	root_pos += bone_delta
	if not parent_state.is_empty():
		root_pos += parent_state.get("root_pos", Vector3.ZERO)

	var g_self: Vector3 = _globalize(root_pos)
	var g_origin: Vector3
	if bone_delta.length_squared() > 0.00000001:
		g_origin = _globalize(origin_local)
	elif not parent_state.is_empty():
		g_origin = parent_state.get("g_self", Vector3.ZERO)
	else:
		g_origin = Vector3.ZERO

	var orient: Quaternion = _root_dir(node_name)
	if rotated:
		orient = (dir_q * orient).normalized()
	var yaw_pitch: Vector2 = _yaw_pitch(orient)
	var pitch_slot: int = _pitch_slot(yaw_pitch.y)
	var yaw_flipped: bool = yaw_pitch.y > 90.0 or yaw_pitch.y < -90.0
	var node_yaw: float = yaw_pitch.x
	var facing_yaw: float = _normalize_degrees(_rounded_face + node_yaw)

	var state: Dictionary = {
		"parent": parent_name,
		"parent_state": parent_state,
		"rotated": rotated,
		"dir": dir_q,
		"scale": scale,
		"bone_delta": bone_delta,
		"root_pos": root_pos,
		"g_self": g_self,
		"g_origin": g_origin,
		"parent_global": g_origin if bone_delta.length_squared() > 0.00000001 else (parent_state.get("g_self", g_origin) if not parent_state.is_empty() else g_origin),
		"facing_yaw": facing_yaw,
		"pitch": pitch_slot,
		"yaw_flipped": yaw_flipped,
		"frame_key": _frame_key(node_name),
		"rot_toggle": bool(pose.get("rot_toggle", false)),
	}
	_states[node_name] = state
	return state


func _frame_key(node_name: String) -> int:
	if not _anims.has(current_animation):
		return 0
	var anim: Dictionary = _anims[current_animation]
	var node_anims: Dictionary = anim.get("nodes", {})
	if not node_anims.has(node_name):
		return 0
	var node_anim: Dictionary = node_anims[node_name]
	var frames: Array = node_anim.get("frames", [])
	if frames.is_empty():
		return 0
	var repeat_count: int = maxi(int(node_anim.get("frameRepeat", 1)), 1)
	var index: int = mini(int(floor(_src_frame)) / repeat_count, frames.size() - 1)
	return int(frames[index])


func _globalize(local_pos: Vector3) -> Vector3:
	var angle: float = deg_to_rad(_rounded_face - 180.0)
	var c: float = cos(angle)
	var s: float = sin(angle)
	var out := Vector3(local_pos.x * c - local_pos.y * s, local_pos.x * s + local_pos.y * c, local_pos.z)
	return _snap_world(out)


func _snap_world(value: Vector3) -> Vector3:
	return Vector3(
		round(value.x * TILE_W * 2.0) / (TILE_W * 2.0),
		round(value.y * TILE_H * 2.0) / (TILE_H * 2.0),
		round(value.z * TILE_H * 2.0) / (TILE_H * 2.0)
	)


func _figure_transform(value: Vector3, q: Quaternion) -> Vector3:
	var result: Vector3 = value
	result.z *= Z_FACTOR_INV
	result = q * result
	result.z *= Z_FACTOR
	return result


func _gfx_world_pos(node_name: String, local_gfx_pos: Vector3) -> Vector3:
	var state: Dictionary = _states.get(node_name, {})
	if state.is_empty():
		return Vector3.ZERO
	if local_gfx_pos.length_squared() <= 0.00000001:
		return state.get("g_self", Vector3.ZERO)
	var node_def: Dictionary = _nodes.get(node_name, {})
	var p: Vector3 = _vec3_from_array(node_def.get("pos", [0.0, 0.0, 0.0])) + local_gfx_pos
	var scale: float = float(state.get("scale", 1.0))
	if scale != 1.0:
		p *= scale
	if bool(state.get("rotated", false)):
		p = _figure_transform(p, state.get("dir", Quaternion(0.0, 0.0, 0.0, 1.0)))
	p += state.get("bone_delta", Vector3.ZERO)
	var parent_name: String = String(state.get("parent", ""))
	if not parent_name.is_empty() and _states.has(parent_name):
		var parent_state: Dictionary = _states[parent_name]
		p += parent_state.get("root_pos", Vector3.ZERO)
	return _globalize(p)


func _update_sprite_source(record: Dictionary) -> void:
	var sprite: Sprite2D = record["sprite"]
	var node_name: String = String(record["node"])
	var gfx: Dictionary = record["gfx"]
	var state: Dictionary = _states.get(node_name, {})
	if state.is_empty():
		sprite.visible = false
		return
	var selected: Dictionary = _select_texture(gfx.get("tex", {}), state)
	if selected.is_empty():
		sprite.visible = false
		return
	var entry: Dictionary = selected["entry"]
	var row: Dictionary = selected["row"]
	var range_data: Array = entry.get("range", [])
	if range_data.size() < 4:
		sprite.visible = false
		return

	var facing: Dictionary = _select_facing_source(String(entry.get("facing", "FACE_1")), float(state.get("facing_yaw", 180.0)), bool(state.get("yaw_flipped", false)) and bool(entry.get("flipRoll", false)))
	if facing.is_empty() or int(facing.get("tile", -1)) < 0:
		sprite.visible = false
		return
	var tile_idx: int = int(facing["tile"])
	var flip_h: bool = bool(facing.get("flip", false))
	var tile_w: int = int(range_data[2])
	var tile_h: int = int(range_data[3])
	var row_index: int = int(selected["row_index"])
	var src_x: int
	var src_y: int
	if bool(entry.get("extendX", false)):
		src_x = int(range_data[0]) + tile_w * row_index
		src_y = int(range_data[1]) + tile_h * tile_idx
	else:
		src_x = int(range_data[0]) + tile_w * tile_idx
		src_y = int(range_data[1]) + tile_h * row_index

	var billboard: Dictionary = gfx.get("shape", {}).get("billboard", {})
	var pivot_half_x: int = int(round(float(tile_w) * 2.0 * float(billboard.get("pivotX", 0.5))))
	var pivot_half_y: int = int(round(float(tile_h) * 2.0 * float(billboard.get("pivotY", 0.5))))
	if bool(billboard.get("halfX", false)):
		pivot_half_x -= 1
	if flip_h:
		pivot_half_x += int(entry.get("flipShift", 0)) * 2
	if bool(_figure.get("halfPixelShift", false)):
		pivot_half_x += 1

	var gfx_world: Vector3 = _gfx_world_pos(node_name, _vec3_from_array(gfx.get("pos", [0.0, 0.0, 0.0])))
	var gfx_screen: Vector2 = _project_world(gfx_world)
	var region := Rect2(float(src_x), float(src_y), float(tile_w), float(tile_h))
	var pivot_px := Vector2(float(pivot_half_x) * 0.5, float(pivot_half_y) * 0.5)
	var scale2 := Vector2.ONE
	var rotation: float = 0.0
	var rot_mode: int = _rot_mode(String(row.get("texRotate", "NONE")))
	var skip_rotation: bool = bool(entry.get("rotDefOff", false))
	if bool(state.get("rot_toggle", false)):
		skip_rotation = not skip_rotation
	if rot_mode != ROT_NONE and not skip_rotation:
		var xfm: Dictionary = _billboard_xfm(node_name, state, gfx_world, gfx_screen, billboard, row, rot_mode, tile_idx, tile_w, tile_h, pivot_px, region)
		rotation = float(xfm.get("rotation", 0.0))
		region = xfm.get("region", region)
		pivot_px = xfm.get("pivot", pivot_px)
		scale2 = xfm.get("scale", Vector2.ONE)

	sprite.region_rect = region
	sprite.flip_h = flip_h
	sprite.flip_v = false
	sprite.position = gfx_screen
	sprite.rotation = rotation
	sprite.scale = scale2
	sprite.visible = region.size.x > 0.0 and region.size.y > 0.0
	var effective_pivot_x: float = region.size.x - pivot_px.x if flip_h else pivot_px.x
	sprite.offset = Vector2(region.size.x * 0.5 - effective_pivot_x, region.size.y * 0.5 - pivot_px.y)

	var z_offset: int = int(row.get("zOff", entry.get("zOff", 0)))
	var z_frames = row.get("zFrames", entry.get("zFrames", null))
	if z_frames is Array and tile_idx < z_frames.size():
		z_offset += int(z_frames[tile_idx])
	else:
		var side_back: int = int(facing.get("side", 0))
		if side_back == 1:
			z_offset += int(row.get("zSide", entry.get("zSide", 0)))
		elif side_back == 2:
			z_offset += int(row.get("zBack", entry.get("zBack", 0)))
	var z_order: int = int(_figure.get("globalZOrder", 0)) + int(billboard.get("zOrder", 0)) + z_offset
	sprite.z_index = clampi(z_order * 16, -4096, 4096)


func _select_texture(tex: Dictionary, state: Dictionary) -> Dictionary:
	if tex.has("simple"):
		return {"entry": tex["simple"], "row": {}, "row_index": 0}
	if not tex.has("multi"):
		return {}
	var multi: Dictionary = tex["multi"]
	var entries: Dictionary = multi.get("entries", {})
	var frame_key: int = int(state.get("frame_key", 0))
	var pitch: int = int(state.get("pitch", 4))
	var result: Dictionary = _find_texture_row(entries, frame_key, pitch)
	if result.is_empty() and frame_key != 0 and String(multi.get("onMissingFrame", "USE_DEFAULT")) == "USE_DEFAULT":
		result = _find_texture_row(entries, 0, pitch)
	return result


func _find_texture_row(entries: Dictionary, frame_key: int, pitch: int) -> Dictionary:
	var best: Dictionary = {}
	var best_size: int = 999
	for entry_name_variant in entries.keys():
		var entry: Dictionary = entries[entry_name_variant]
		var variants: Array = entry.get("variants", [])
		if not variants.is_empty():
			continue
		var rows: Array = entry.get("rows", [])
		for row_index in range(rows.size()):
			var row: Dictionary = rows[row_index]
			var keys: Array = row.get("frameKeys", [])
			var frame_match: bool
			if keys.is_empty():
				frame_match = frame_key == 0
			else:
				frame_match = keys.has(frame_key)
			if not frame_match:
				continue
			var bounds: Vector2i = _pitch_bounds(String(row.get("pitchRange", "ALL")))
			if pitch < bounds.x or pitch > bounds.y:
				continue
			var range_size: int = bounds.y - bounds.x
			if best.is_empty() or range_size < best_size:
				best = {"entry": entry, "row": row, "row_index": row_index}
				best_size = range_size
	return best


func _billboard_xfm(node_name: String, state: Dictionary, gfx_world: Vector3, gfx_screen: Vector2, billboard: Dictionary, row: Dictionary, rot_mode: int, tile_idx: int, tile_w: int, tile_h: int, pivot_px: Vector2, region: Rect2) -> Dictionary:
	var result: Dictionary = {"rotation": 0.0, "region": region, "pivot": pivot_px, "scale": Vector2.ONE}
	var ref_angle: float = 0.0
	var refs: Array = row.get("refAngles", [])
	if tile_idx >= 0 and tile_idx < refs.size() and refs[tile_idx] != null:
		ref_angle = deg_to_rad(float(refs[tile_idx]))
	var cut_meta: Dictionary = _cut_meta(ref_angle, tile_w, tile_h, billboard)
	var angle: float = 0.0
	var use_length: bool = (rot_mode & (ROT_CUT | ROT_SCALE)) != 0
	var length_px: float = 0.0
	if use_length:
		var second_world: Vector3
		if (rot_mode & ROT_PARENT) != 0:
			second_world = state.get("parent_global", state.get("g_origin", Vector3.ZERO))
		else:
			second_world = state.get("g_self", Vector3.ZERO)
		var factor: float = float(billboard.get("parentPosFactor", 0.0))
		if factor != 0.0:
			second_world += (second_world - gfx_world) * factor
		var delta: Vector2 = _project_world(second_world) - gfx_screen
		angle = _clock_angle(delta)
		length_px = delta.length() * float(cut_meta.get("factor", 1.0)) + float(billboard.get("parentPixelOff", 0.0))
	else:
		angle = _screen_rotation(state)
		if rot_mode == (ROT_ROTATE | ROT_PARENT):
			angle += PI

	var flip_ref: bool = false
	var facing_mode: String = ""
	if _nodes.has(node_name):
		facing_mode = String(_nodes[node_name].get("facing", ""))
	# The demo mirrors rotRef when the selected texture is mirrored. Sprite2D
	# applies mirroring separately, so the caller's facing flip is folded into
	# this using the selected source reference where possible.
	if flip_ref:
		ref_angle = TAU - ref_angle
	result["rotation"] = angle - ref_angle

	if use_length:
		var cut_dir: int = int(cut_meta.get("dir", 0))
		var cut_inverse: bool = bool(billboard.get("cutInverse", false))
		var rect: Rect2 = region
		var pivot: Vector2 = pivot_px
		var scale: Vector2 = Vector2.ONE
		if cut_dir == 0:
			var gfx_len_top: float = pivot.y
			if (rot_mode & ROT_CUT) != 0:
				var overflow_top: int = int(round(gfx_len_top - length_px))
				if overflow_top > 0:
					rect.size.y = maxf(0.0, rect.size.y - overflow_top)
					if not cut_inverse:
						rect.position.y += overflow_top
					pivot.y -= overflow_top
			elif (rot_mode & ROT_SCALE) != 0 and gfx_len_top > 0.0001:
				scale.y *= maxf(4.0, length_px) / gfx_len_top
		elif cut_dir == 2:
			var gfx_len_bottom: float = rect.size.y - pivot.y
			if (rot_mode & ROT_CUT) != 0:
				var overflow_bottom: int = int(round(gfx_len_bottom - length_px))
				if overflow_bottom > 0:
					rect.size.y = maxf(0.0, rect.size.y - overflow_bottom)
					if cut_inverse:
						rect.position.y += overflow_bottom
			elif (rot_mode & ROT_SCALE) != 0 and gfx_len_bottom > 0.0001:
				scale.y *= maxf(4.0, length_px) / gfx_len_bottom
		elif cut_dir == 3:
			var gfx_len_left: float = pivot.x
			if (rot_mode & ROT_CUT) != 0:
				var overflow_left: int = int(round(gfx_len_left - length_px))
				if overflow_left > 0:
					rect.size.x = maxf(0.0, rect.size.x - overflow_left)
					if not cut_inverse:
						rect.position.x += overflow_left
					pivot.x -= overflow_left
			elif (rot_mode & ROT_SCALE) != 0 and gfx_len_left > 0.0001:
				scale.x *= maxf(4.0, length_px) / gfx_len_left
		else:
			var gfx_len_right: float = rect.size.x - pivot.x
			if (rot_mode & ROT_CUT) != 0:
				var overflow_right: int = int(round(gfx_len_right - length_px))
				if overflow_right > 0:
					rect.size.x = maxf(0.0, rect.size.x - overflow_right)
					if cut_inverse:
						rect.position.x += overflow_right
			elif (rot_mode & ROT_SCALE) != 0 and gfx_len_right > 0.0001:
				scale.x *= maxf(4.0, length_px) / gfx_len_right
		result["region"] = rect
		result["pivot"] = pivot
		result["scale"] = scale
	return result


func _screen_rotation(state: Dictionary) -> float:
	var parent_screen: Vector2 = _project_world(state.get("parent_global", state.get("g_origin", Vector3.ZERO)))
	var self_screen: Vector2 = _project_world(state.get("g_self", Vector3.ZERO))
	return _clock_angle(self_screen - parent_screen)


func _cut_meta(ref_angle: float, tile_w: int, tile_h: int, billboard: Dictionary) -> Dictionary:
	var pivot_x: float = float(billboard.get("pivotX", 0.5)) * tile_w + (0.5 if bool(_figure.get("halfPixelShift", false)) else 0.0)
	var pivot_y: float = float(billboard.get("pivotY", 0.5)) * tile_h
	var dir: Vector2 = Vector2(0.0, -1.0).rotated(-ref_angle)
	var vx: float = dir.x
	var vy: float = dir.y
	var x_t: float = 10000000.0
	var y_t: float = 10000000.0
	var x_dir: int = 1
	var y_dir: int = 0
	if absf(vx) > 0.000001:
		if vx > 0.0:
			x_t = (tile_w - pivot_x) / vx
			x_dir = 1
		else:
			x_t = -pivot_x / vx
			x_dir = 3
	if absf(vy) > 0.000001:
		if vy > 0.0:
			y_t = (tile_h - pivot_y) / vy
			y_dir = 2
		else:
			y_t = -pivot_y / vy
			y_dir = 0
	if x_t < y_t:
		return {"dir": x_dir, "factor": absf(vx)}
	return {"dir": y_dir, "factor": absf(vy)}


func _select_facing_source(mode: String, angle: float, flip_roll: bool) -> Dictionary:
	var selected_mode: String = mode
	var selected_angle: float = _normalize_degrees(angle)
	if flip_roll:
		selected_mode = _flipped_facing_mode(mode)
		selected_angle = _normalize_degrees(selected_angle + 180.0)
	var table: Dictionary = _facing_table(selected_mode)
	if table.is_empty():
		return {"tile": 0, "flip": false, "side": 0, "yaw_index": 0}
	var thresholds: Array = table["angles"]
	var yaw_index: int = 0
	var found: bool = false
	for i in range(thresholds.size()):
		if float(thresholds[i]) >= selected_angle:
			yaw_index = i
			found = true
			break
	if not found:
		yaw_index = 0
	var tiles: Array = table["tiles"]
	var flips: Array = table["flips"]
	var sides: Array = table["sides"]
	return {
		"tile": int(tiles[yaw_index]),
		"flip": int(flips[yaw_index]) == 1,
		"side": int(sides[yaw_index]),
		"yaw_index": yaw_index,
	}


func _facing_table(mode: String) -> Dictionary:
	var a8 := [25.0, 70.0, 115.0, 160.0, 200.0, 245.0, 290.0, 335.0]
	var s8 := [2, 2, 1, 0, 0, 0, 1, 2]
	var a16 := [11.25, 33.75, 56.25, 78.75, 101.25, 123.75, 146.25, 168.75, 191.25, 213.75, 236.25, 258.75, 281.25, 303.75, 326.25, 348.75]
	var s16 := [2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2]
	match mode:
		"FACE_1": return {"angles": [360.0], "tiles": [0], "flips": [0], "sides": [0]}
		"FACE_1_FLIP": return {"angles": [360.0], "tiles": [0], "flips": [1], "sides": [0]}
		"FACE_2_FRONT_BACK": return {"angles": [120.0, 240.0], "tiles": [0, 1], "flips": [0, 0], "sides": [0, 2]}
		"FACE_2_FLIP_FB": return {"angles": [120.0, 240.0], "tiles": [0, 1], "flips": [1, 1], "sides": [0, 2]}
		"FACE_4": return {"angles": [40.0, 140.0, 220.0, 320.0], "tiles": [2, 1, 0, 3], "flips": [0, 0, 0, 0], "sides": [2, 1, 0, 1]}
		"FACE_4_FLIP": return {"angles": [40.0, 140.0, 220.0, 320.0], "tiles": [2, 3, 0, 1], "flips": [1, 1, 1, 1], "sides": [2, 1, 0, 1]}
		"FACE_4_MIRR": return {"angles": [40.0, 140.0, 220.0, 320.0], "tiles": [2, 1, 0, 1], "flips": [0, 0, 0, 1], "sides": [2, 1, 0, 1]}
		"FACE_4_MIRR_FLIP": return {"angles": [40.0, 140.0, 220.0, 320.0], "tiles": [2, 1, 0, 1], "flips": [1, 0, 1, 1], "sides": [2, 1, 0, 1]}
		"FACE_8": return {"angles": a8, "tiles": [4, 3, 2, 1, 0, 7, 6, 5], "flips": [0, 0, 0, 0, 0, 0, 0, 0], "sides": s8}
		"FACE_8_FLIP": return {"angles": a8, "tiles": [4, 5, 6, 7, 0, 1, 2, 3], "flips": [1, 1, 1, 1, 1, 1, 1, 1], "sides": s8}
		"FACE_8_MIRR": return {"angles": a8, "tiles": [4, 3, 2, 1, 0, 1, 2, 3], "flips": [0, 0, 0, 0, 0, 1, 1, 1], "sides": s8}
		"FACE_8_MIRR_FLIP": return {"angles": a8, "tiles": [4, 3, 2, 1, 0, 1, 2, 3], "flips": [1, 0, 0, 0, 1, 1, 1, 1], "sides": s8}
		"FACE_8_FRONT_ONLY": return {"angles": a8, "tiles": [-1, -1, 2, 1, 0, 4, 3, -1], "flips": [0, 0, 0, 0, 0, 0, 0, 0], "sides": s8}
		"FACE_16": return {"angles": a16, "tiles": [8, 7, 6, 5, 4, 3, 2, 1, 0, 15, 14, 13, 12, 11, 10, 9], "flips": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "sides": s16}
		"FACE_16_FLIP": return {"angles": a16, "tiles": [8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7], "flips": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], "sides": s16}
		"FACE_16_MIRR": return {"angles": a16, "tiles": [8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7], "flips": [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1], "sides": s16}
		"FACE_16_MIRR_FLIP": return {"angles": a16, "tiles": [8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7], "flips": [1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1], "sides": s16}
		"FACE_16_FRONT_ONLY": return {"angles": a16, "tiles": [-1, -1, -1, -1, 4, 3, 2, 1, 0, 8, 7, 6, 5, -1, -1, -1], "flips": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "sides": s16}
		"FACE_16_FLIP_FO": return {"angles": a16, "tiles": [-1, -1, -1, -1, 5, 6, 7, 8, 0, 1, 2, 3, 4, -1, -1, -1], "flips": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], "sides": s16}
		"FACE_16_MIRR_FO": return {"angles": a16, "tiles": [-1, -1, -1, -1, 4, 3, 2, 1, 0, 1, 2, 3, 4, -1, -1, -1], "flips": [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1], "sides": s16}
		_:
			return {}


func _flipped_facing_mode(mode: String) -> String:
	match mode:
		"FACE_1": return "FACE_1_FLIP"
		"FACE_1_FLIP": return "FACE_1"
		"FACE_4": return "FACE_4_FLIP"
		"FACE_4_FLIP": return "FACE_4"
		"FACE_8": return "FACE_8_FLIP"
		"FACE_8_FLIP": return "FACE_8"
		"FACE_8_MIRR": return "FACE_8_MIRR_FLIP"
		"FACE_8_MIRR_FLIP": return "FACE_8_MIRR"
		"FACE_16": return "FACE_16_FLIP"
		"FACE_16_FLIP": return "FACE_16"
		"FACE_16_MIRR": return "FACE_16_MIRR_FLIP"
		"FACE_16_MIRR_FLIP": return "FACE_16_MIRR"
		_:
			return mode


func _pitch_slot(pitch: float) -> int:
	var value: float = pitch
	if value < -135.0:
		value += 360.0
	var slots := [-105.0, -75.0, -45.0, -15.0, 15.0, 45.0, 75.0, 105.0, 135.0, 165.0, 195.0]
	for i in range(slots.size()):
		if value < float(slots[i]):
			return i
	return 11


func _pitch_bounds(name: String) -> Vector2i:
	match name:
		"NORM": return Vector2i(4, 4)
		"NORM_W": return Vector2i(3, 5)
		"UP1": return Vector2i(5, 5)
		"UP1+": return Vector2i(5, 11)
		"UP2": return Vector2i(6, 6)
		"UP2+": return Vector2i(6, 11)
		"UP3": return Vector2i(7, 7)
		"UP3+": return Vector2i(7, 11)
		"UP4": return Vector2i(8, 8)
		"UP4+": return Vector2i(8, 11)
		"UP5": return Vector2i(9, 9)
		"UP5+": return Vector2i(9, 11)
		"BACK": return Vector2i(10, 10)
		"BACK+": return Vector2i(10, 11)
		"DOWN1": return Vector2i(3, 3)
		"DOWN1+": return Vector2i(0, 3)
		"DOWN2": return Vector2i(2, 2)
		"DOWN2+": return Vector2i(0, 2)
		"DOWN3": return Vector2i(1, 1)
		"DOWN3+": return Vector2i(0, 1)
		"DOWN4": return Vector2i(0, 0)
		"DOWN5": return Vector2i(11, 11)
		_:
			return Vector2i(0, 11)


func _rot_mode(name: String) -> int:
	match name:
		"ROTATE": return ROT_ROTATE
		"ROTATE_CUT": return ROT_ROTATE | ROT_CUT
		"ROTATE_SCALE": return ROT_ROTATE | ROT_SCALE
		"PARENT_ROTATE": return ROT_ROTATE | ROT_PARENT
		"PARENT_ROTATE_CUT": return ROT_ROTATE | ROT_PARENT | ROT_CUT
		"PARENT_ROTATE_SCALE": return ROT_ROTATE | ROT_PARENT | ROT_SCALE
		_:
			return ROT_NONE


func _source_quat(angles: Vector3) -> Quaternion:
	# bundle Quaternion.setAngles(yaw,pitch,roll) calls glMatrix.fromEuler
	# with (pitch, roll, yaw).
	var x: float = deg_to_rad(angles.y) * 0.5
	var y: float = deg_to_rad(angles.z) * 0.5
	var z: float = deg_to_rad(angles.x) * 0.5
	var sx: float = sin(x)
	var cx: float = cos(x)
	var sy: float = sin(y)
	var cy: float = cos(y)
	var sz: float = sin(z)
	var cz: float = cos(z)
	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	).normalized()


func _yaw_pitch(q: Quaternion) -> Vector2:
	var yaw: float = rad_to_deg(atan2(2.0 * (q.x * q.y + q.z * q.w), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)))
	var pitch: float = rad_to_deg(atan2(2.0 * (q.x * q.w + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)))
	return Vector2(yaw, pitch)


func _source_scale(value) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value
		if not array_value.is_empty():
			return float(array_value[0])
	return 1.0


func _round_root_face(angle: float, mode: String) -> float:
	var step: float = 22.5
	var offset: float = 0.0
	match mode:
		"FACE_1": step = 360.0; offset = 180.0
		"FACE_2": step = 180.0; offset = 90.0
		"FACE_4": step = 90.0
		"FACE_4_DIAG": step = 90.0; offset = 45.0
		"FACE_6": step = 60.0; offset = 30.0
		"FACE_8": step = 45.0
		"FACE_16": step = 22.5
		"FACE_48": step = 7.5
		"FACE_72": step = 5.0
		"FACE_360": step = 1.0
	var rounded: float = round((angle - offset) / step) * step + offset
	return _normalize_degrees(rounded)


func _project_world(world: Vector3) -> Vector2:
	# Source perspective camera, returned in source-screen pixels relative to center.
	var x: float = world.x * (TILE_W / TILE_H)
	var y: float = -world.y + CAMERA_SKEW * world.z
	var z: float = world.z
	var c: float = cos(CAMERA_X_ROT)
	var s: float = sin(CAMERA_X_ROT)
	var view_y: float = y * c - z * s
	var view_z: float = y * s + z * c - CAMERA_Z
	var w: float = maxf(-view_z, 0.001)
	var f: float = 1.0 / tan(deg_to_rad(FOV_DEG) * 0.5)
	var aspect: float = SCREEN_W / SCREEN_H
	var ndc_x: float = (f / aspect) * x / w
	var ndc_y: float = f * view_y / w
	return Vector2(SCREEN_W * 0.5 * ndc_x, -SCREEN_H * 0.5 * ndc_y)


func _clock_angle(value: Vector2) -> float:
	var length: float = value.length()
	if length <= 0.000001:
		return 0.0
	var angle: float = acos(clampf(-value.y / length, -1.0, 1.0))
	if value.x < 0.0:
		angle = TAU - angle
	return angle


func _draw() -> void:
	if not debug_enabled:
		return
	for node_name_variant in _nodes.keys():
		var node_name: String = String(node_name_variant)
		var state: Dictionary = _states.get(node_name, {})
		if state.is_empty():
			continue
		var p: Vector2 = _project_world(state.get("g_self", Vector3.ZERO))
		var parent_name: String = String(state.get("parent", ""))
		if not parent_name.is_empty() and _states.has(parent_name):
			var parent_state: Dictionary = _states[parent_name]
			var pp: Vector2 = _project_world(parent_state.get("g_self", Vector3.ZERO))
			draw_line(pp, p, Color(0.25, 0.95, 0.75, 0.9), 0.75)
		draw_circle(p, 1.1, Color(1.0, 0.72, 0.24, 0.95))
