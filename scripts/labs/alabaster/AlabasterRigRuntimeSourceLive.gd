extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSource.gd"

# Live correction layer over the source-derived runtime plus the complete
# animation catalog used by the isolated animation playground.

const AnimationBank := preload("res://scripts/labs/alabaster/AlabasterAnimationBank.gd")
const SourceImporter := preload("res://scripts/labs/alabaster/AlabasterSourceImporter.gd")

const ANIMATION_CATEGORY_ORDER := {
	"DEFAULT": 0,
	"COMBAT": 1,
	"PUZZLE": 2,
	"OTHER": 3,
	"CUTSCENE": 4,
}

const FULL_RUNTIME_MAX_BYTES := 8 * 1024 * 1024
const PLAYER_ANIMATION_BANK_PATH := "res://data/labs/alabaster/juno_player_anims.json.gz.b64"
const PLAYER_ANIMATION_MAX_BYTES := 512 * 1024
const LAYER_NO_OVERRIDE := 999999

var _active_record: Dictionary = {}
var _animation_bank_loaded := false
var _animation_bank_source := "FALLBACK"
var _embedded_world_mode := false
var animation_speed_scale := 1.0
var sprite_opacity := 1.0


func _process(delta: float) -> void:
	animation_time += delta * maxf(animation_speed_scale, 0.001)
	_apply_pose()


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("AlabasterRigRuntime: missing %s" % DATA_PATH)
		return
	var encoded := FileAccess.get_file_as_string(DATA_PATH).strip_edges()
	var compressed := Marshalls.base64_to_raw(encoded)
	var raw := compressed.decompress_dynamic(FULL_RUNTIME_MAX_BYTES, FileAccess.COMPRESSION_GZIP)
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
		return

	var full_anims: Dictionary = SourceImporter.load_juno_animations()
	if full_anims.size() == SourceImporter.EXPECTED_ANIMATIONS:
		_install_animation_catalog(full_anims, "SOURCE_JSON")
	else:
		full_anims = AnimationBank.load_full_animation_bank()
		if full_anims.size() == AnimationBank.EXPECTED_ANIMATIONS:
			_install_animation_catalog(full_anims, "PACKED")
		else:
			_animation_bank_loaded = false
			_animation_bank_source = "FALLBACK"
			push_warning("AlabasterRigRuntime: full animation catalog unavailable; using runtime subset (%d animations)" % _anims.size())

	_merge_player_animation_bank()

	if not _anims.has("idle") or not _anims.has("walk") or not _anims.has("run"):
		push_error("AlabasterRigRuntime: expected idle/walk/run animations")


func load_external_animation_source(source_path: String) -> bool:
	var full_anims: Dictionary = SourceImporter.load_juno_animations_from_path(source_path, true)
	if full_anims.size() != SourceImporter.EXPECTED_ANIMATIONS:
		return false
	_install_animation_catalog(full_anims, "SOURCE_JSON")
	current_animation = "idle"
	animation_time = 0.0
	_apply_pose()
	return true


func _install_animation_catalog(full_anims: Dictionary, source_name: String) -> void:
	_anims = full_anims
	_figure["anims"] = _anims
	_track_cache.clear()
	_animation_bank_loaded = true
	_animation_bank_source = source_name
	print("ALABASTER_ANIMATION_BANK_OK source=%s animations=%d" % [_animation_bank_source, _anims.size()])


func _merge_player_animation_bank() -> void:
	if _animation_bank_loaded:
		return
	if not FileAccess.file_exists(PLAYER_ANIMATION_BANK_PATH):
		push_warning("AlabasterRigRuntime: player animation bank missing: %s" % PLAYER_ANIMATION_BANK_PATH)
		return
	var encoded := FileAccess.get_file_as_string(PLAYER_ANIMATION_BANK_PATH).strip_edges()
	if encoded.is_empty():
		push_warning("AlabasterRigRuntime: player animation bank is empty")
		return
	var compressed := Marshalls.base64_to_raw(encoded)
	var raw := compressed.decompress_dynamic(PLAYER_ANIMATION_MAX_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		push_warning("AlabasterRigRuntime: player animation bank could not be decompressed")
		return
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AlabasterRigRuntime: player animation bank is invalid JSON")
		return
	var payload: Dictionary = parsed
	var player_anims_variant: Variant = payload.get("anims", {})
	if typeof(player_anims_variant) != TYPE_DICTIONARY:
		push_warning("AlabasterRigRuntime: player animation bank has no anims dictionary")
		return
	var player_anims: Dictionary = player_anims_variant
	for animation_name_variant in player_anims.keys():
		_anims[animation_name_variant] = player_anims[animation_name_variant]
	_figure["anims"] = _anims
	_track_cache.clear()
	_animation_bank_source = "PLAYER_PACK"
	print("ALABASTER_PLAYER_BANK_OK gameplay=%d total=%d" % [player_anims.size(), _anims.size()])


func set_embedded_world_mode(enabled: bool) -> void:
	if _embedded_world_mode == enabled:
		return
	_embedded_world_mode = enabled
	_apply_pose()


func set_animation_speed_scale(value: float) -> void:
	animation_speed_scale = maxf(value, 0.001)


func set_sprite_opacity(value: float) -> void:
	sprite_opacity = clampf(value, 0.0, 1.0)
	for record_variant in _sprite_records:
		var record: Dictionary = record_variant
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null:
			sprite.self_modulate.a = sprite_opacity


func get_sprite_opacity() -> float:
	return sprite_opacity


func get_bone_names() -> Array[String]:
	var names: Array[String] = []
	for node_name_variant in _nodes.keys():
		names.append(String(node_name_variant))
	names.sort()
	return names


func get_bone_parent_map() -> Dictionary:
	var result := {}
	for node_name_variant in _nodes.keys():
		var node_name := String(node_name_variant)
		var node_def: Dictionary = _nodes[node_name]
		result[node_name] = String(node_def.get("parent", ""))
	return result


func get_bone_screen_pose(node_name: String) -> Dictionary:
	if not _states.has(node_name):
		return {}
	var state: Dictionary = _states[node_name]
	var screen := _project_world(state.get("g_self", Vector3.ZERO))
	var origin := _project_world(state.get("g_origin", Vector3.ZERO))
	return {
		"name": node_name,
		"screen_position": screen,
		"screen_origin": origin,
		"rotation": _screen_rotation(state),
		"scale": float(state.get("scale", 1.0)),
		"pitch": int(state.get("pitch", 4)),
		"facing_yaw": float(state.get("facing_yaw", facing_degrees)),
		"world_position": state.get("g_self", Vector3.ZERO),
	}


func get_all_bone_screen_poses() -> Dictionary:
	var result := {}
	for node_name in get_bone_names():
		result[node_name] = get_bone_screen_pose(node_name)
	return result


func get_runtime_summary() -> Dictionary:
	var summary: Dictionary = super.get_runtime_summary()
	summary["animation_count"] = _anims.size()
	summary["animation_bank_loaded"] = _animation_bank_loaded
	summary["animation_bank_source"] = _animation_bank_source
	summary["embedded_world_mode"] = _embedded_world_mode
	summary["animation_speed_scale"] = animation_speed_scale
	summary["sprite_opacity"] = sprite_opacity
	return summary


func has_animation(animation_name: String) -> bool:
	return _anims.has(animation_name)


func get_animation_data(animation_name: String) -> Dictionary:
	return (_anims.get(animation_name, {}) as Dictionary).duplicate(true) if _anims.get(animation_name, {}) is Dictionary else {}


func install_runtime_animation(animation_name: String, animation_data: Dictionary) -> bool:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty() or animation_data.is_empty():
		return false
	if not animation_data.has("frameCnt") or not animation_data.has("transforms"):
		return false
	_anims[clean_name] = animation_data.duplicate(true)
	_figure["anims"] = _anims
	_track_cache.clear()
	return true


func get_animation_duration_seconds(animation_name: String) -> float:
	if not _anims.has(animation_name):
		return 0.0
	var anim: Dictionary = _anims[animation_name]
	var frame_count: float = maxf(float(anim.get("frameCnt", 1.0)), 1.0)
	var start_frame: float = clampf(float(anim.get("animStart", 0.0)), 0.0, frame_count)
	var frame_repeat: float = maxf(float(anim.get("frameRepeat", 1.0)), 1.0)
	return maxf((frame_count - start_frame) * frame_repeat / 60.0, 1.0 / 60.0)


func is_current_animation_finished() -> bool:
	if not _anims.has(current_animation):
		return true
	var anim: Dictionary = _anims[current_animation]
	if bool(anim.get("repeat", true)):
		return false
	return animation_time >= get_animation_duration_seconds(current_animation) / maxf(animation_speed_scale, 0.001)


func get_animation_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for animation_name_variant in _anims.keys():
		var animation_name := String(animation_name_variant)
		var anim: Dictionary = _anims[animation_name_variant]
		result.append({
			"name": animation_name,
			"category": String(anim.get("category", "DEFAULT")),
			"frame_count": int(anim.get("frameCnt", 1)),
			"frame_repeat": int(anim.get("frameRepeat", 1)),
			"repeat": bool(anim.get("repeat", true)),
			"duration": get_animation_duration_seconds(animation_name),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_a := String(a.get("category", "DEFAULT"))
		var category_b := String(b.get("category", "DEFAULT"))
		var order_a := int(ANIMATION_CATEGORY_ORDER.get(category_a, 99))
		var order_b := int(ANIMATION_CATEGORY_ORDER.get(category_b, 99))
		if order_a != order_b:
			return order_a < order_b
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	return result


func _update_sprite_source(record: Dictionary) -> void:
	var sprite: Sprite2D = record.get("sprite")
	if sprite == null:
		return
	if not _node_is_visible_for_animation(String(record.get("node", ""))):
		sprite.visible = false
		return
	_active_record = record
	super._update_sprite_source(record)
	_active_record = {}
	sprite.self_modulate.a = sprite_opacity
	_apply_embedded_layer_mode(sprite)
	_apply_directional_layer_override(record, sprite)


func _apply_embedded_layer_mode(sprite: Sprite2D) -> void:
	if not _embedded_world_mode:
		sprite.z_as_relative = false
		return
	var figure_global_z := int(_figure.get("globalZOrder", 0))
	var authored_absolute_layer := roundi(float(sprite.z_index) / 16.0)
	sprite.z_as_relative = true
	sprite.z_index = clampi(authored_absolute_layer - figure_global_z, -32, 32)


func _apply_directional_layer_override(record: Dictionary, sprite: Sprite2D) -> void:
	var node_name := String(record.get("node", ""))
	var logical_layer := LAYER_NO_OVERRIDE

	# The floating ornament belongs visually above the skull in the two cardinal
	# front/back views. Keep diagonal/profile ordering authored by the source.
	if node_name == "headGear":
		var south_distance := _angular_distance(facing_degrees, 180.0)
		var north_distance := _angular_distance(facing_degrees, 0.0)
		if south_distance <= 11.26 or north_distance <= 11.26:
			logical_layer = 3

	elif node_name == "tailEnd":
		var north_distance := _angular_distance(facing_degrees, 0.0)
		if north_distance <= 67.5:
			logical_layer = 3
		elif north_distance <= 112.5:
			logical_layer = 1

	if logical_layer == LAYER_NO_OVERRIDE:
		return
	if _embedded_world_mode:
		sprite.z_as_relative = true
		sprite.z_index = logical_layer
	else:
		sprite.z_as_relative = false
		var figure_global_z := int(_figure.get("globalZOrder", 0))
		sprite.z_index = clampi((figure_global_z + logical_layer) * 16, -4096, 4096)
	sprite.set_meta("alabaster_layer_override", logical_layer)


func _angular_distance(a: float, b: float) -> float:
	var delta := absf(_normalize_degrees(a) - _normalize_degrees(b))
	return minf(delta, 360.0 - delta)


func _node_is_visible_for_animation(node_name: String) -> bool:
	if node_name.is_empty() or not _nodes.has(node_name):
		return false
	var node_def: Dictionary = _nodes[node_name]
	var visible := not bool(node_def.get("hidden", false))
	if _anims.has(current_animation):
		var anim: Dictionary = _anims[current_animation]
		var animated_nodes: Dictionary = anim.get("nodes", {})
		if animated_nodes.has(node_name):
			var node_anim: Dictionary = animated_nodes[node_name]
			if node_anim.has("visible"):
				visible = bool(node_anim.get("visible", visible))
	return visible


func _billboard_xfm(node_name: String, state: Dictionary, gfx_world: Vector3, gfx_screen: Vector2, billboard: Dictionary, row: Dictionary, rot_mode: int, tile_idx: int, tile_w: int, tile_h: int, pivot_px: Vector2, region: Rect2) -> Dictionary:
	var result: Dictionary = super._billboard_xfm(node_name, state, gfx_world, gfx_screen, billboard, row, rot_mode, tile_idx, tile_w, tile_h, pivot_px, region)
	if _active_record.is_empty():
		return result
	var gfx: Dictionary = _active_record.get("gfx", {})
	var selected: Dictionary = _select_texture(gfx.get("tex", {}), state)
	if selected.is_empty():
		return result
	var entry: Dictionary = selected.get("entry", {})
	var facing: Dictionary = _select_facing_source(
		String(entry.get("facing", "FACE_1")),
		float(state.get("facing_yaw", 180.0)),
		bool(state.get("yaw_flipped", false)) and bool(entry.get("flipRoll", false))
	)
	if not bool(facing.get("flip", false)):
		return result
	var refs: Array = row.get("refAngles", [])
	if tile_idx < 0 or tile_idx >= refs.size() or refs[tile_idx] == null:
		return result
	result["rotation"] = float(result.get("rotation", 0.0)) + 2.0 * deg_to_rad(float(refs[tile_idx]))
	return result
