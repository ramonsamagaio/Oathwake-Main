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

var _active_record: Dictionary = {}
var _animation_bank_loaded := false
var _animation_bank_source := "FALLBACK"


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

	# Prefer the original demo JSON when it is available locally. It already
	# contains figures.default.anims with all 419 authored animations and avoids
	# transporting a large animation payload through the repository.
	var full_anims: Dictionary = SourceImporter.load_juno_animations()
	if full_anims.size() == SourceImporter.EXPECTED_ANIMATIONS:
		_anims = full_anims
		_figure["anims"] = _anims
		_animation_bank_loaded = true
		_animation_bank_source = "SOURCE_JSON"
		print("ALABASTER_ANIMATION_BANK_OK source=SOURCE_JSON animations=%d" % _anims.size())
	else:
		# Secondary path: self-contained compact bank in the branch.
		full_anims = AnimationBank.load_full_animation_bank()
		if full_anims.size() == AnimationBank.EXPECTED_ANIMATIONS:
			_anims = full_anims
			_figure["anims"] = _anims
			_animation_bank_loaded = true
			_animation_bank_source = "PACKED"
			print("ALABASTER_ANIMATION_BANK_OK source=PACKED animations=%d" % _anims.size())
		else:
			_animation_bank_loaded = false
			_animation_bank_source = "FALLBACK"
			push_warning("AlabasterRigRuntime: full animation catalog unavailable; using runtime subset (%d animations)" % _anims.size())

	if not _anims.has("idle") or not _anims.has("walk") or not _anims.has("run"):
		push_error("AlabasterRigRuntime: expected idle/walk/run animations")


func get_runtime_summary() -> Dictionary:
	var summary: Dictionary = super.get_runtime_summary()
	summary["animation_count"] = _anims.size()
	summary["animation_bank_loaded"] = _animation_bank_loaded
	summary["animation_bank_source"] = _animation_bank_source
	return summary


func has_animation(animation_name: String) -> bool:
	return _anims.has(animation_name)


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
	return animation_time >= get_animation_duration_seconds(current_animation)


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
	# If the selected directional tile is mirrored, mirror its authored
	# reference angle too before applying the residual billboard rotation.
	result["rotation"] = float(result.get("rotation", 0.0)) + 2.0 * deg_to_rad(float(refs[tile_idx]))
	return result
