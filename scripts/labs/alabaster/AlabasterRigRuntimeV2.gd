extends "res://scripts/labs/alabaster/AlabasterRigRuntime.gd"

# Second-pass reconstruction based on the recorded lab behavior plus the
# semantics exposed by juno.json / juno-rd.json.
#
# The first pass proved atlas decoding and root-facing selection, but it was
# still treating every node as a conventional local Euler bone and it always
# selected the first texture row. That is not what the source data describes.
#
# This pass adds the high-confidence missing semantics:
# - globalRot nodes keep an actor/global orientation while their origin still
#   follows the parent attachment point;
# - node scale is sampled from animation transforms;
# - animation node frame IDs select authored frame-key rows/entries;
# - pitchRange participates in texture-row selection instead of blindly using
#   row zero;
# - USE_DEFAULT / HIDE behavior is respected when a frame-key is absent.

var _source_frame: float = 0.0


func _sample_animation(animation_name: String) -> Dictionary:
	if not _anims.has(animation_name):
		_source_frame = 0.0
		return {}

	var anim: Dictionary = _anims[animation_name]
	var frame_count: float = maxf(float(anim.get("frameCnt", 1)), 1.0)
	var frame_repeat: float = maxf(float(anim.get("frameRepeat", 1)), 1.0)
	var anim_start: float = clampf(float(anim.get("animStart", 0)), 0.0, frame_count)
	var loop_start: float = clampf(float(anim.get("loopStart", anim_start)), 0.0, frame_count)
	var repeats: bool = bool(anim.get("repeat", true))

	_source_frame = anim_start + animation_time * SOURCE_TICK_RATE / frame_repeat
	if repeats and _source_frame > frame_count:
		var loop_span: float = maxf(frame_count - loop_start, 1.0)
		_source_frame = loop_start + fmod(_source_frame - frame_count, loop_span)
	elif not repeats:
		_source_frame = minf(_source_frame, frame_count)

	var tracks: Dictionary = _get_tracks(animation_name)
	var sampled: Dictionary = {}
	for node_name_variant in _nodes.keys():
		var node_name: String = String(node_name_variant)
		var track: Array = tracks.get(node_name, [])
		sampled[node_name] = _sample_track(track, _source_frame, frame_count, repeats)
	return sampled


func _get_tracks(animation_name: String) -> Dictionary:
	if _track_cache.has(animation_name):
		return _track_cache[animation_name]

	var anim: Dictionary = _anims.get(animation_name, {})
	var tracks: Dictionary = {}
	for node_name_variant in _nodes.keys():
		tracks[String(node_name_variant)] = []

	var transforms: Array = anim.get("transforms", [])
	for key_variant in transforms:
		var key: Dictionary = key_variant
		var frame: float = float(key.get("frame", 0))
		var spline: String = String(key.get("spline", "LINEAR"))
		var node_xfm: Dictionary = key.get("nodeXfm", {})
		for node_name_variant in node_xfm.keys():
			var node_name: String = String(node_name_variant)
			if not tracks.has(node_name):
				tracks[node_name] = []
			var xfm: Dictionary = node_xfm[node_name_variant]
			tracks[node_name].append({
				"frame": frame,
				"rot": _vec3_from_array(xfm.get("rot", [0.0, 0.0, 0.0])),
				"trans": _vec3_from_array(xfm.get("trans", [0.0, 0.0, 0.0])),
				"scale": _uniform_scale_from_value(xfm.get("scale", 1.0)),
				"spline": spline,
			})

	for node_name_variant in tracks.keys():
		var node_track: Array = tracks[node_name_variant]
		node_track.sort_custom(func(a, b): return float(a["frame"]) < float(b["frame"]))

	_track_cache[animation_name] = tracks
	return tracks


func _sample_track(track: Array, frame: float, frame_count: float, repeat: bool) -> Dictionary:
	if track.is_empty():
		return {"rot": Vector3.ZERO, "trans": Vector3.ZERO, "scale": 1.0}
	if track.size() == 1:
		return {
			"rot": track[0].get("rot", Vector3.ZERO),
			"trans": track[0].get("trans", Vector3.ZERO),
			"scale": float(track[0].get("scale", 1.0)),
		}

	var prev: Dictionary = track[0]
	var next: Dictionary = track[track.size() - 1]
	var prev_frame: float = float(prev["frame"])
	var next_frame: float = float(next["frame"])
	var sample_frame: float = frame
	var found: bool = false

	for i in range(track.size() - 1):
		var a: Dictionary = track[i]
		var b: Dictionary = track[i + 1]
		if frame >= float(a["frame"]) and frame <= float(b["frame"]):
			prev = a
			next = b
			prev_frame = float(a["frame"])
			next_frame = float(b["frame"])
			found = true
			break

	if not found:
		if repeat:
			prev = track[track.size() - 1]
			next = track[0]
			prev_frame = float(prev["frame"])
			next_frame = float(next["frame"]) + frame_count
			if sample_frame < float(track[0]["frame"]):
				sample_frame += frame_count
		else:
			prev = track[track.size() - 1]
			next = prev
			prev_frame = float(prev["frame"])
			next_frame = prev_frame

	var t: float = 0.0
	if next_frame > prev_frame + 0.000001:
		t = clampf((sample_frame - prev_frame) / (next_frame - prev_frame), 0.0, 1.0)
	t = _apply_spline(t, String(prev.get("spline", "LINEAR")))

	var prev_trans: Vector3 = prev.get("trans", Vector3.ZERO)
	var next_trans: Vector3 = next.get("trans", Vector3.ZERO)
	return {
		"rot": _lerp_euler_degrees(prev.get("rot", Vector3.ZERO), next.get("rot", Vector3.ZERO), t),
		"trans": prev_trans.lerp(next_trans, t),
		"scale": lerpf(float(prev.get("scale", 1.0)), float(next.get("scale", 1.0)), t),
	}


func _get_world_transform(node_name: String, sampled: Dictionary) -> Transform3D:
	if _world_transforms.has(node_name):
		return _world_transforms[node_name]

	var node_def: Dictionary = _nodes.get(node_name, {})
	var base_pos: Vector3 = _vec3_from_array(node_def.get("pos", [0.0, 0.0, 0.0]))
	var base_rot: Vector3 = _vec3_from_array(node_def.get("dir", [0.0, 0.0, 0.0]))
	var anim_xfm: Dictionary = sampled.get(node_name, {})
	var anim_trans: Vector3 = anim_xfm.get("trans", Vector3.ZERO)
	var anim_rot: Vector3 = anim_xfm.get("rot", Vector3.ZERO)
	var anim_scale: float = float(anim_xfm.get("scale", 1.0))
	var local_pos: Vector3 = base_pos + anim_trans
	var local_basis: Basis = _basis_from_degrees(base_rot) * _basis_from_degrees(anim_rot)
	local_basis = local_basis.scaled(Vector3.ONE * anim_scale)

	var facing_basis: Basis = Basis(Vector3(0.0, 0.0, 1.0), -deg_to_rad(facing_degrees))
	var parent_name: String = String(node_def.get("parent", ""))
	var world_origin: Vector3
	var world_basis: Basis

	if parent_name.is_empty() or not _nodes.has(parent_name):
		world_origin = facing_basis * local_pos
		world_basis = facing_basis * local_basis
	else:
		var parent_world: Transform3D = _get_world_transform(parent_name, sampled)
		world_origin = parent_world * local_pos
		if bool(node_def.get("globalRot", false)):
			# The source explicitly marks these nodes as globally oriented. Their
			# attachment point follows the parent, but their basis must not receive
			# the parent's rotation a second time. Juno's arm dir values already
			# contain the shoulder-space orientation, unlike the non-global Bob rig.
			world_basis = facing_basis * local_basis
		else:
			world_basis = parent_world.basis * local_basis

	var world: Transform3D = Transform3D(world_basis, world_origin)
	_world_transforms[node_name] = world
	return world


func _update_sprite_record(record: Dictionary, sampled: Dictionary) -> void:
	var sprite: Sprite2D = record["sprite"]
	var node_name: String = String(record["node"])
	var gfx: Dictionary = record["gfx"]
	var node_world: Transform3D = _world_transforms.get(node_name, Transform3D.IDENTITY)
	var entry_info: Dictionary = _resolve_texture_for_pose(node_name, gfx.get("tex", {}), node_world)
	if entry_info.is_empty():
		sprite.visible = false
		return

	var entry: Dictionary = entry_info["entry"]
	var row: Dictionary = entry_info["row"]
	var row_index: int = int(entry_info["row_index"])
	var range_data: Array = entry.get("range", [])
	if range_data.size() < 4:
		sprite.visible = false
		return

	var node_def: Dictionary = _nodes.get(node_name, {})
	var parent_name: String = String(node_def.get("parent", ""))
	var parent_world: Transform3D = Transform3D.IDENTITY
	if not parent_name.is_empty() and _world_transforms.has(parent_name):
		parent_world = _world_transforms[parent_name]

	var billboard: Dictionary = gfx.get("shape", {}).get("billboard", {})
	var gfx_pos: Vector3 = _vec3_from_array(gfx.get("pos", [0.0, 0.0, 0.0]))
	var world_pos: Vector3 = node_world * gfx_pos
	var parent_factor: float = float(billboard.get("parentPosFactor", 0.0))
	if parent_factor > 0.0 and not parent_name.is_empty():
		world_pos = world_pos.lerp(parent_world.origin, clampf(parent_factor, 0.0, 1.0))

	var facing_mode: String = String(entry.get("facing", "FACE_1"))
	var actual_angle: float = _get_record_angle(node_name, node_world)
	var facing: Dictionary = _select_facing(facing_mode, actual_angle)
	if not bool(facing.get("visible", true)):
		sprite.visible = false
		return

	var source_index: int = int(facing.get("source_index", 0))
	var flip_h: bool = bool(facing.get("flip_h", false))
	var x: int = int(range_data[0])
	var y: int = int(range_data[1])
	var w: int = int(range_data[2])
	var h: int = int(range_data[3])
	sprite.region_rect = Rect2(x + source_index * w, y + row_index * h, w, h)
	sprite.flip_h = flip_h
	sprite.flip_v = false
	sprite.visible = true

	var pivot_x: float = float(billboard.get("pivotX", 0.5))
	var pivot_y: float = float(billboard.get("pivotY", 0.5))
	if flip_h:
		pivot_x = 1.0 - pivot_x
	sprite.offset = Vector2((0.5 - pivot_x) * w, (0.5 - pivot_y) * h)

	var screen_pos: Vector2 = _project(world_pos) * PIXELS_PER_UNIT
	var parent_pixel_off: float = float(billboard.get("parentPixelOff", 0.0))
	if parent_pixel_off != 0.0 and not parent_name.is_empty():
		var parent_screen: Vector2 = _project(parent_world.origin) * PIXELS_PER_UNIT
		var toward_parent: Vector2 = parent_screen - screen_pos
		if toward_parent.length_squared() > 0.00001:
			screen_pos += toward_parent.normalized() * parent_pixel_off
	if bool(_figure.get("halfPixelShift", false)):
		screen_pos = _snap_half_pixel(screen_pos)
	else:
		screen_pos = screen_pos.round()
	sprite.position = screen_pos

	var tex_rotate: String = String(row.get("texRotate", "NONE"))
	var rotation_source_name: String = node_name
	if tex_rotate.begins_with("PARENT_") and not parent_name.is_empty():
		rotation_source_name = parent_name
	var rotation_angle: float = actual_angle
	if _world_transforms.has(rotation_source_name):
		rotation_angle = _get_record_angle(rotation_source_name, _world_transforms[rotation_source_name])

	var correction: float = 0.0
	if tex_rotate != "NONE":
		var ref_angles: Array = row.get("refAngles", [])
		if source_index < ref_angles.size() and ref_angles[source_index] != null:
			correction = _shortest_degrees(rotation_angle - float(ref_angles[source_index]))
		elif tex_rotate.contains("ROTATE"):
			correction = _shortest_degrees(rotation_angle - _quantized_reference_angle(facing_mode, int(facing.get("logical_index", 0))))
	sprite.rotation = deg_to_rad(correction)

	var scale_value: Vector2 = Vector2.ONE
	if tex_rotate.ends_with("_SCALE"):
		var source_world: Transform3D = node_world
		if tex_rotate.begins_with("PARENT_") and not parent_name.is_empty():
			source_world = parent_world
		var projected_axis: Vector2 = _project_vector(source_world.basis.orthonormalized() * Vector3(0.0, 0.0, 1.0))
		var stretch: float = clampf(projected_axis.length(), 0.72, 1.28)
		scale_value.y = stretch
	sprite.scale = scale_value

	var z_order: int = int(billboard.get("zOrder", 0))
	var z_back: int = int(entry.get("zBack", 0))
	if _is_back_facing(int(facing.get("logical_index", 0)), _facing_count(facing_mode)):
		z_order += z_back
	sprite.z_index = clampi(100 + z_order * 8 + int(round(world_pos.y * 2.0)), -4096, 4096)


func _resolve_texture_for_pose(node_name: String, tex: Dictionary, node_world: Transform3D) -> Dictionary:
	if tex.has("simple"):
		return {"entry": tex["simple"], "row": {}, "row_index": 0}
	if not tex.has("multi"):
		return {}

	var multi: Dictionary = tex["multi"]
	var entries: Dictionary = multi.get("entries", {})
	if entries.is_empty():
		return {}

	var frame_key: int = _active_frame_key(node_name)
	var pitch_degrees: float = _node_pitch_degrees(node_world)

	# First priority: an authored row explicitly keyed to the active node frame.
	if frame_key > 0:
		var keyed: Dictionary = _best_row_candidate(entries, frame_key, pitch_degrees, true)
		if not keyed.is_empty():
			return keyed
		if String(multi.get("onMissingFrame", "USE_DEFAULT")) == "HIDE":
			return {}

	# Second priority: unkeyed/default artwork for this pose.
	var fallback: Dictionary = _best_row_candidate(entries, 0, pitch_degrees, false)
	if not fallback.is_empty():
		return fallback

	if String(multi.get("onMissingFrame", "USE_DEFAULT")) == "HIDE":
		return {}

	# Last-resort compatibility path for sparse data: use the first variant-free
	# entry/row instead of making the whole body part disappear.
	for entry_name_variant in entries.keys():
		var entry: Dictionary = entries[entry_name_variant]
		if not _entry_is_base_variant(entry):
			continue
		var rows: Array = entry.get("rows", [])
		if rows.is_empty():
			return {"entry": entry, "row": {}, "row_index": 0}
		return {"entry": entry, "row": rows[0], "row_index": 0}
	return {}


func _best_row_candidate(entries: Dictionary, frame_key: int, pitch_degrees: float, require_key: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF

	var ordered_names: Array = entries.keys()
	# For generic fallback, the explicit `default` entry is authoritative when it
	# exists. Frame-key searches still inspect every base-variant entry so tail
	# states such as subtle/wave/swing can win.
	if not require_key and entries.has("default"):
		ordered_names.erase("default")
		ordered_names.push_front("default")
	elif not require_key and current_animation == "idle" and entries.has("Idle"):
		ordered_names.erase("Idle")
		ordered_names.push_front("Idle")

	for entry_order in range(ordered_names.size()):
		var entry_name = ordered_names[entry_order]
		var entry: Dictionary = entries[entry_name]
		if not _entry_is_base_variant(entry):
			continue
		var rows: Array = entry.get("rows", [])
		if rows.is_empty():
			if not require_key and frame_key == 0:
				var empty_score: float = float(entry_order) * 0.01
				if empty_score < best_score:
					best_score = empty_score
					best = {"entry": entry, "row": {}, "row_index": 0}
			continue

		for row_index in range(rows.size()):
			var row: Dictionary = rows[row_index]
			var frame_keys: Array = row.get("frameKeys", [])
			var key_matches: bool = frame_keys.has(frame_key) if require_key else frame_keys.is_empty()
			if not key_matches:
				continue
			var pitch_score: float = _pitch_range_score(String(row.get("pitchRange", "ALL")), pitch_degrees)
			if pitch_score >= 10000.0:
				continue
			var score: float = pitch_score + float(entry_order) * 0.01 + float(row_index) * 0.0001
			if score < best_score:
				best_score = score
				best = {"entry": entry, "row": row, "row_index": row_index}

	return best


func _entry_is_base_variant(entry: Dictionary) -> bool:
	var variants: Array = entry.get("variants", [])
	return variants.is_empty()


func _active_frame_key(node_name: String) -> int:
	var anim: Dictionary = _anims.get(current_animation, {})
	var node_anims: Dictionary = anim.get("nodes", {})
	if not node_anims.has(node_name):
		return 0
	var node_anim: Dictionary = node_anims[node_name]
	var frames: Array = node_anim.get("frames", [])
	if frames.is_empty():
		return 0
	var repeat_count: int = maxi(int(node_anim.get("frameRepeat", 1)), 1)
	var index: int = int(floor(_source_frame / float(repeat_count)))
	index = posmod(index, frames.size())
	return int(frames[index])


func _node_pitch_degrees(world: Transform3D) -> float:
	var axis: Vector3 = world.basis.orthonormalized() * Vector3(0.0, 0.0, 1.0)
	return rad_to_deg(asin(clampf(axis.z, -1.0, 1.0)))


func _pitch_range_score(pitch_range: String, pitch_degrees: float) -> float:
	# The files expose named pitch bands but not the engine's numeric thresholds.
	# 22.5-degree half-sectors match the facing quantization and give stable,
	# deterministic selection while keeping ALL as the safe authored fallback.
	var p: float = pitch_degrees
	match pitch_range:
		"ALL":
			return 100.0
		"NORM":
			return absf(p) if absf(p) < 11.25 else 10000.0
		"DOWN1":
			return absf(p + 22.5) if p <= -11.25 and p > -33.75 else 10000.0
		"DOWN1+":
			return 30.0 + absf(p + 22.5) if p <= -11.25 else 10000.0
		"DOWN2":
			return absf(p + 45.0) if p <= -33.75 and p > -56.25 else 10000.0
		"DOWN2+":
			return 20.0 + absf(p + 45.0) if p <= -33.75 else 10000.0
		"DOWN3":
			return absf(p + 67.5) if p <= -56.25 else 10000.0
		"DOWN3+":
			return 10.0 + absf(p + 67.5) if p <= -56.25 else 10000.0
		"UP1":
			return absf(p - 22.5) if p >= 11.25 and p < 33.75 else 10000.0
		"UP1+":
			return 30.0 + absf(p - 22.5) if p >= 11.25 else 10000.0
		"UP2":
			return absf(p - 45.0) if p >= 33.75 and p < 56.25 else 10000.0
		"UP2+":
			return 20.0 + absf(p - 45.0) if p >= 33.75 else 10000.0
		"UP3", "UP3+":
			return 10.0 + absf(p - 67.5) if p >= 56.25 else 10000.0
		_:
			return 100.0


func _uniform_scale_from_value(value) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_ARRAY and value.size() > 0:
		return float(value[0])
	return 1.0
