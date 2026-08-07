extends Node2D
class_name AlabasterRigRuntime

const DATA_PATH := "res://data/labs/alabaster/juno_runtime.json.gz.b64"
const AtlasFactory := preload("res://scripts/labs/alabaster/AlabasterJunoAtlas.gd")

const PIXELS_PER_UNIT := 16.0
const DEPTH_SHEAR := 0.5
const SOURCE_TICK_RATE := 60.0
const HALF_PIXEL := 0.5

const BODY_FACING_NODES := {
	"root": true,
	"gRoot": true,
	"top": true,
	"head": true,
	"headGear": true,
	"eyes": true,
	"bottom": true,
	"weaponBelt": true,
}

var _atlas: Texture2D
var _figure: Dictionary = {}
var _nodes: Dictionary = {}
var _anims: Dictionary = {}
var _sprite_records: Array = []
var _track_cache: Dictionary = {}
var _world_transforms: Dictionary = {}

var facing_degrees := 0.0
var current_animation := "idle"
var animation_time := 0.0
var debug_enabled := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_data()
	if _figure.is_empty():
		return
	_atlas = AtlasFactory.create_texture()
	if _atlas == null:
		return
	_build_sprite_records()
	_apply_pose()
	set_process(true)


func _process(delta: float) -> void:
	animation_time += delta
	_apply_pose()


func set_animation(animation_name: String) -> void:
	if not _anims.has(animation_name):
		return
	if current_animation == animation_name:
		return
	current_animation = animation_name
	animation_time = 0.0
	_track_cache.clear()


func set_facing_from_vector(direction: Vector2) -> void:
	if direction.length_squared() < 0.000001:
		return
	facing_degrees = _normalize_degrees(rad_to_deg(atan2(direction.x, direction.y)))


func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	queue_redraw()


func get_facing_index_16() -> int:
	return int(round(_normalize_degrees(facing_degrees) / 22.5)) % 16


func get_runtime_summary() -> Dictionary:
	return {
		"animation": current_animation,
		"facing_degrees": facing_degrees,
		"facing_index_16": get_facing_index_16(),
		"node_count": _nodes.size(),
		"sprite_piece_count": _sprite_records.size(),
	}


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("AlabasterRigRuntime: missing %s" % DATA_PATH)
		return
	var encoded := FileAccess.get_file_as_string(DATA_PATH).strip_edges()
	var compressed := Marshalls.base64_to_raw(encoded)
	var raw := compressed.decompress_dynamic(1024 * 1024, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		push_error("AlabasterRigRuntime: failed to decompress Juno runtime data")
		return
	var source_json := raw.get_string_from_utf8()
	var parsed = JSON.parse_string(source_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AlabasterRigRuntime: invalid runtime JSON")
		return
	var root_data: Dictionary = parsed
	_figure = root_data.get("figure", {})
	_nodes = _figure.get("nodes", {})
	_anims = _figure.get("anims", {})
	if _nodes.is_empty():
		push_error("AlabasterRigRuntime: source figure has no nodes")
	if not _anims.has("idle") or not _anims.has("walk") or not _anims.has("run"):
		push_error("AlabasterRigRuntime: expected idle/walk/run animations")


func _build_sprite_records() -> void:
	for node_name_variant in _nodes.keys():
		var node_name := String(node_name_variant)
		var node_def: Dictionary = _nodes[node_name]
		var gfx_list: Array = node_def.get("gfx", [])
		for gfx_index in range(gfx_list.size()):
			var gfx: Dictionary = gfx_list[gfx_index]
			if bool(gfx.get("hidden", false)):
				continue
			if not gfx.has("tex"):
				continue
			var sprite := Sprite2D.new()
			sprite.name = "%s_gfx_%d" % [node_name, gfx_index]
			sprite.texture = _atlas
			sprite.region_enabled = true
			sprite.centered = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_as_relative = false
			add_child(sprite)
			_sprite_records.append({
				"node": node_name,
				"gfx_index": gfx_index,
				"gfx": gfx,
				"sprite": sprite,
			})


func _apply_pose() -> void:
	if _nodes.is_empty() or _atlas == null:
		return
	var sampled := _sample_animation(current_animation)
	_world_transforms.clear()
	for node_name_variant in _nodes.keys():
		_get_world_transform(String(node_name_variant), sampled)
	for record_variant in _sprite_records:
		_update_sprite_record(record_variant, sampled)
	if debug_enabled:
		queue_redraw()


func _sample_animation(animation_name: String) -> Dictionary:
	if not _anims.has(animation_name):
		return {}
	var anim: Dictionary = _anims[animation_name]
	var frame_count := maxf(float(anim.get("frameCnt", 1)), 1.0)
	var frame_repeat := maxf(float(anim.get("frameRepeat", 1)), 1.0)
	var source_frame := fmod(animation_time * SOURCE_TICK_RATE / frame_repeat, frame_count)
	if not bool(anim.get("repeat", true)):
		source_frame = minf(source_frame, frame_count)
	var tracks := _get_tracks(animation_name)
	var sampled: Dictionary = {}
	for node_name_variant in _nodes.keys():
		var node_name := String(node_name_variant)
		var track: Array = tracks.get(node_name, [])
		sampled[node_name] = _sample_track(track, source_frame, frame_count, bool(anim.get("repeat", true)))
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
		var frame := float(key.get("frame", 0))
		var spline := String(key.get("spline", "LINEAR"))
		var node_xfm: Dictionary = key.get("nodeXfm", {})
		for node_name_variant in node_xfm.keys():
			var node_name := String(node_name_variant)
			if not tracks.has(node_name):
				tracks[node_name] = []
			var xfm: Dictionary = node_xfm[node_name_variant]
			var rot := _vec3_from_array(xfm.get("rot", [0.0, 0.0, 0.0]))
			var trans := _vec3_from_array(xfm.get("trans", [0.0, 0.0, 0.0]))
			tracks[node_name].append({
				"frame": frame,
				"rot": rot,
				"trans": trans,
				"spline": spline,
			})
	for node_name_variant in tracks.keys():
		var node_track: Array = tracks[node_name_variant]
		node_track.sort_custom(func(a, b): return float(a["frame"]) < float(b["frame"]))
	_track_cache[animation_name] = tracks
	return tracks


func _sample_track(track: Array, frame: float, frame_count: float, repeat: bool) -> Dictionary:
	if track.is_empty():
		return {"rot": Vector3.ZERO, "trans": Vector3.ZERO}
	if track.size() == 1:
		return {"rot": track[0]["rot"], "trans": track[0]["trans"]}
	var prev: Dictionary = track[0]
	var next: Dictionary = track[track.size() - 1]
	var prev_frame := float(prev["frame"])
	var next_frame := float(next["frame"])
	var sample_frame := frame

	var found := false
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
			next = track[track.size() - 1]
			prev = next
			prev_frame = float(prev["frame"])
			next_frame = prev_frame

	var t := 0.0
	if next_frame > prev_frame + 0.000001:
		t = clampf((sample_frame - prev_frame) / (next_frame - prev_frame), 0.0, 1.0)
	t = _apply_spline(t, String(prev.get("spline", "LINEAR")))
	var prev_trans: Vector3 = prev["trans"]
	var next_trans: Vector3 = next["trans"]
	return {
		"rot": _lerp_euler_degrees(prev["rot"], next["rot"], t),
		"trans": prev_trans.lerp(next_trans, t),
	}


func _apply_spline(t: float, spline: String) -> float:
	match spline:
		"EASE_IN":
			return t * t
		"EASE_OUT":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"EASE_IN_STRONG":
			return t * t * t
		"EASE_OUT_STRONG":
			var inv := 1.0 - t
			return 1.0 - inv * inv * inv
		_:
			return t


func _lerp_euler_degrees(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(
		rad_to_deg(lerp_angle(deg_to_rad(a.x), deg_to_rad(b.x), t)),
		rad_to_deg(lerp_angle(deg_to_rad(a.y), deg_to_rad(b.y), t)),
		rad_to_deg(lerp_angle(deg_to_rad(a.z), deg_to_rad(b.z), t))
	)


func _get_world_transform(node_name: String, sampled: Dictionary) -> Transform3D:
	if _world_transforms.has(node_name):
		return _world_transforms[node_name]
	var node_def: Dictionary = _nodes.get(node_name, {})
	var base_pos := _vec3_from_array(node_def.get("pos", [0.0, 0.0, 0.0]))
	var base_rot := _vec3_from_array(node_def.get("dir", [0.0, 0.0, 0.0]))
	var anim_xfm: Dictionary = sampled.get(node_name, {})
	var anim_trans: Vector3 = anim_xfm.get("trans", Vector3.ZERO)
	var local_pos := base_pos + anim_trans
	var anim_rot: Vector3 = anim_xfm.get("rot", Vector3.ZERO)
	var local_basis := _basis_from_degrees(base_rot) * _basis_from_degrees(anim_rot)
	var local := Transform3D(local_basis, local_pos)

	var parent_name := String(node_def.get("parent", ""))
	var world: Transform3D
	if parent_name.is_empty() or not _nodes.has(parent_name):
		var facing_basis := Basis(Vector3(0.0, 0.0, 1.0), -deg_to_rad(facing_degrees))
		world = Transform3D(facing_basis, Vector3.ZERO) * local
	else:
		var parent_world := _get_world_transform(parent_name, sampled)
		world = parent_world * local
	_world_transforms[node_name] = world
	return world


func _basis_from_degrees(rot: Vector3) -> Basis:
	var rx := Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(rot.x))
	var ry := Basis(Vector3(0.0, 1.0, 0.0), deg_to_rad(rot.y))
	var rz := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(rot.z))
	return rz * ry * rx


func _update_sprite_record(record: Dictionary, sampled: Dictionary) -> void:
	var sprite: Sprite2D = record["sprite"]
	var node_name := String(record["node"])
	var gfx: Dictionary = record["gfx"]
	var entry_info := _resolve_texture_entry(gfx.get("tex", {}))
	if entry_info.is_empty():
		sprite.visible = false
		return
	var entry: Dictionary = entry_info["entry"]
	var range_data: Array = entry.get("range", [])
	if range_data.size() < 4:
		sprite.visible = false
		return

	var node_world: Transform3D = _world_transforms.get(node_name, Transform3D.IDENTITY)
	var node_def: Dictionary = _nodes.get(node_name, {})
	var parent_name := String(node_def.get("parent", ""))
	var parent_world := Transform3D.IDENTITY
	if not parent_name.is_empty() and _world_transforms.has(parent_name):
		parent_world = _world_transforms[parent_name]

	var billboard: Dictionary = gfx.get("shape", {}).get("billboard", {})
	var gfx_pos := _vec3_from_array(gfx.get("pos", [0.0, 0.0, 0.0]))
	var world_pos: Vector3 = node_world * gfx_pos
	var parent_factor := float(billboard.get("parentPosFactor", 0.0))
	if parent_factor > 0.0 and not parent_name.is_empty():
		world_pos = world_pos.lerp(parent_world.origin, clampf(parent_factor, 0.0, 1.0))

	var facing_mode := String(entry.get("facing", "FACE_1"))
	var actual_angle := _get_record_angle(node_name, node_world)
	var facing := _select_facing(facing_mode, actual_angle)
	if not bool(facing.get("visible", true)):
		sprite.visible = false
		return

	var source_index := int(facing.get("source_index", 0))
	var flip_h := bool(facing.get("flip_h", false))
	var rows: Array = entry.get("rows", [])
	var row_index := _select_unkeyed_row(rows)
	if row_index < 0:
		if String(entry_info.get("on_missing", "USE_DEFAULT")) == "HIDE":
			sprite.visible = false
			return
		row_index = 0
	var row: Dictionary = {}
	if not rows.is_empty():
		row = rows[row_index]

	var x := int(range_data[0])
	var y := int(range_data[1])
	var w := int(range_data[2])
	var h := int(range_data[3])
	sprite.region_rect = Rect2(x + source_index * w, y + row_index * h, w, h)
	sprite.flip_h = flip_h
	sprite.flip_v = false
	sprite.visible = true

	var pivot_x := float(billboard.get("pivotX", 0.5))
	var pivot_y := float(billboard.get("pivotY", 0.5))
	if flip_h:
		pivot_x = 1.0 - pivot_x
	sprite.offset = Vector2((0.5 - pivot_x) * w, (0.5 - pivot_y) * h)

	var screen_pos := _project(world_pos) * PIXELS_PER_UNIT
	var parent_pixel_off := float(billboard.get("parentPixelOff", 0.0))
	if parent_pixel_off != 0.0 and not parent_name.is_empty():
		var parent_screen := _project(parent_world.origin) * PIXELS_PER_UNIT
		var toward_parent := parent_screen - screen_pos
		if toward_parent.length_squared() > 0.00001:
			screen_pos += toward_parent.normalized() * parent_pixel_off
	if bool(_figure.get("halfPixelShift", false)):
		screen_pos = _snap_half_pixel(screen_pos)
	else:
		screen_pos = screen_pos.round()
	sprite.position = screen_pos

	var tex_rotate := String(row.get("texRotate", "NONE"))
	var rotation_source_name := node_name
	if tex_rotate.begins_with("PARENT_") and not parent_name.is_empty():
		rotation_source_name = parent_name
	var rotation_angle := actual_angle
	if _world_transforms.has(rotation_source_name):
		rotation_angle = _get_record_angle(rotation_source_name, _world_transforms[rotation_source_name])
	var correction := 0.0
	if tex_rotate != "NONE":
		var ref_angles: Array = row.get("refAngles", [])
		if source_index < ref_angles.size() and ref_angles[source_index] != null:
			correction = _shortest_degrees(rotation_angle - float(ref_angles[source_index]))
		elif tex_rotate.contains("ROTATE"):
			correction = _shortest_degrees(rotation_angle - _quantized_reference_angle(facing_mode, int(facing.get("logical_index", 0))))
	sprite.rotation = deg_to_rad(correction)

	var scale_value := Vector2.ONE
	if tex_rotate.ends_with("_SCALE"):
		var source_world := node_world
		if tex_rotate.begins_with("PARENT_") and not parent_name.is_empty():
			source_world = parent_world
		var projected_axis := _project_vector(source_world.basis * Vector3(0.0, 0.0, 1.0))
		var stretch := clampf(projected_axis.length(), 0.72, 1.28)
		scale_value.y = stretch
	sprite.scale = scale_value

	var z_order := int(billboard.get("zOrder", 0))
	var z_back := int(entry.get("zBack", 0))
	if _is_back_facing(int(facing.get("logical_index", 0)), _facing_count(facing_mode)):
		z_order += z_back
	sprite.z_index = clampi(100 + z_order * 8 + int(round(world_pos.y * 2.0)), -4096, 4096)


func _resolve_texture_entry(tex: Dictionary) -> Dictionary:
	if tex.has("simple"):
		return {"entry": tex["simple"], "name": "simple", "on_missing": "USE_DEFAULT"}
	if not tex.has("multi"):
		return {}
	var multi: Dictionary = tex["multi"]
	var entries: Dictionary = multi.get("entries", {})
	if entries.is_empty():
		return {}
	var on_missing := String(multi.get("onMissingFrame", "USE_DEFAULT"))
	if entries.has("default"):
		return {"entry": entries["default"], "name": "default", "on_missing": on_missing}
	if current_animation == "idle" and entries.has("Idle"):
		return {"entry": entries["Idle"], "name": "Idle", "on_missing": on_missing}
	if entries.has(current_animation):
		return {"entry": entries[current_animation], "name": current_animation, "on_missing": on_missing}
	var first_key = entries.keys()[0]
	return {"entry": entries[first_key], "name": String(first_key), "on_missing": on_missing}


func _select_unkeyed_row(rows: Array) -> int:
	if rows.is_empty():
		return 0
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var frame_keys: Array = row.get("frameKeys", [])
		if frame_keys.is_empty():
			return i
	return -1


func _get_record_angle(node_name: String, world: Transform3D) -> float:
	if BODY_FACING_NODES.has(node_name):
		return _normalize_degrees(facing_degrees)
	var projected_axis := _project_vector(world.basis * Vector3(0.0, 0.0, 1.0))
	if projected_axis.length_squared() < 0.000001:
		return _normalize_degrees(facing_degrees)
	return _normalize_degrees(rad_to_deg(atan2(projected_axis.x, projected_axis.y)))


func _select_facing(mode: String, angle_deg: float) -> Dictionary:
	var count := _facing_count(mode)
	var step := 360.0 / float(maxi(count, 1))
	var logical := int(round(_normalize_degrees(angle_deg) / step)) % maxi(count, 1)
	var source := logical
	var flip_h := false
	var visible := true

	if mode.contains("FRONT_ONLY") or mode.ends_with("_FO"):
		var quarter := maxi(1, int(count / 4))
		visible = logical <= quarter or logical >= count - quarter

	if mode.contains("MIRR"):
		var half := int(count / 2)
		if logical > half:
			source = count - logical
			flip_h = true

	if mode.contains("MIRR_FLIP"):
		flip_h = not flip_h
	elif mode.ends_with("_FLIP") or mode.contains("_FLIP_"):
		flip_h = not flip_h

	if mode.contains("FACE_2_FRONT_BACK"):
		source = 0 if logical == 0 else 1
	if mode.contains("FACE_2_FLIP_FB"):
		source = 0 if logical == 0 else 1
		flip_h = logical != 0

	return {
		"logical_index": logical,
		"source_index": source,
		"flip_h": flip_h,
		"visible": visible,
	}


func _facing_count(mode: String) -> int:
	if mode.contains("FACE_16"):
		return 16
	if mode.contains("FACE_8"):
		return 8
	if mode.contains("FACE_4"):
		return 4
	if mode.contains("FACE_2"):
		return 2
	return 1


func _quantized_reference_angle(mode: String, logical_index: int) -> float:
	var count := _facing_count(mode)
	return float(logical_index) * 360.0 / float(maxi(count, 1))


func _is_back_facing(logical_index: int, count: int) -> bool:
	if count <= 1:
		return false
	var half := int(count / 2)
	var quarter := maxi(1, int(count / 4))
	return logical_index >= quarter and logical_index <= half + quarter


func _project(world_pos: Vector3) -> Vector2:
	return Vector2(world_pos.x, -world_pos.z + world_pos.y * DEPTH_SHEAR)


func _project_vector(world_vector: Vector3) -> Vector2:
	return Vector2(world_vector.x, -world_vector.z + world_vector.y * DEPTH_SHEAR)


func _snap_half_pixel(value: Vector2) -> Vector2:
	return Vector2(round(value.x / HALF_PIXEL) * HALF_PIXEL, round(value.y / HALF_PIXEL) * HALF_PIXEL)


func _vec3_from_array(value) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _normalize_degrees(value: float) -> float:
	return fposmod(value, 360.0)


func _shortest_degrees(value: float) -> float:
	return fposmod(value + 180.0, 360.0) - 180.0


func _draw() -> void:
	if not debug_enabled:
		return
	for node_name_variant in _nodes.keys():
		var node_name := String(node_name_variant)
		var node_def: Dictionary = _nodes[node_name]
		var parent_name := String(node_def.get("parent", ""))
		if parent_name.is_empty() or not _world_transforms.has(node_name) or not _world_transforms.has(parent_name):
			continue
		var parent_world: Transform3D = _world_transforms[parent_name]
		var node_world: Transform3D = _world_transforms[node_name]
		var a := _snap_half_pixel(_project(parent_world.origin) * PIXELS_PER_UNIT)
		var b := _snap_half_pixel(_project(node_world.origin) * PIXELS_PER_UNIT)
		draw_line(a, b, Color(0.25, 0.95, 0.75, 0.9), 0.75)
		draw_circle(b, 1.1, Color(1.0, 0.72, 0.24, 0.95))
