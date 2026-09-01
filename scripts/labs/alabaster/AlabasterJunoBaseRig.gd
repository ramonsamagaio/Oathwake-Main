extends "res://scripts/systems/bones/BonesSystem.gd"
class_name AlabasterJunoBaseRig

const Profile := preload("res://scripts/labs/alabaster/AlabasterJunoBaseProfile.gd")
const CORE_ATLAS_PATH := "res://data/labs/alabaster/juno_base_core_atlas.png"
const COMPACT_ATLAS_PATH := "res://assets/sprites/characters/JUNOBASE.png"
const COMPACT_MAP_PATH := "res://data/labs/alabaster/juno_base_compact_map.json"

var _juno_base_core_atlas_active := false
var _juno_base_compact_atlas_active := false
var _compact_region_entries: Array[Dictionary] = []
var _compact_region_exact: Dictionary = {}
var _compact_region_cache: Dictionary = {}
var _compact_packed_size := Vector2i.ZERO
var _compact_missing_region_warnings: Dictionary = {}


func _ready() -> void:
	# Start from the exact production Juno runtime, skeleton, authored positions and
	# rotation semantics. JunoBase then owns an independent core animation bank.
	# Its visuals are repacked pixel-for-pixel into a compact atlas at scale 1:1.
	super._ready()
	_filter_to_core_animation_bank()
	_install_compact_atlas_if_available()
	if _anims.has("idle"):
		current_animation = "idle"
		animation_time = 0.0
	_apply_pose()


func _apply_pose() -> void:
	# Every inherited pose pass reconstructs source-atlas region coordinates from
	# the authored Alabaster metadata. Remap those final regions only after the
	# complete production pose/layer pipeline has finished, so animation semantics
	# stay untouched and only the texture address changes.
	super._apply_pose()
	if _juno_base_compact_atlas_active:
		_remap_visible_regions_to_compact()


func _filter_to_core_animation_bank() -> void:
	var filtered := Profile.filter_animation_bank(_anims)
	if filtered.is_empty():
		push_warning("JunoBase: core animation filter returned no clips; preserving Juno bank as safety fallback.")
		return
	_anims = filtered
	_figure["anims"] = _anims
	_track_cache.clear()
	invalidate_animation_bank_cache()
	prewarm_animations(Profile.core_animation_names())


func _install_compact_atlas_if_available() -> void:
	_compact_region_entries.clear()
	_compact_region_exact.clear()
	_compact_region_cache.clear()
	_compact_packed_size = Vector2i.ZERO
	_juno_base_core_atlas_active = false
	_juno_base_compact_atlas_active = false

	if not _load_compact_map():
		push_warning("JunoBase: compact atlas map is unavailable; using full Juno atlas for this session.")
		return
	var texture := _load_png_texture(COMPACT_ATLAS_PATH)
	if texture == null:
		push_warning("JunoBase: compact atlas PNG is unavailable; using full Juno atlas for this session.")
		return
	_atlas = texture
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite != null:
			sprite.texture = _atlas
	_juno_base_core_atlas_active = true
	_juno_base_compact_atlas_active = true


func _load_compact_map() -> bool:
	if not FileAccess.file_exists(COMPACT_MAP_PATH):
		return false
	var file := FileAccess.open(COMPACT_MAP_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var data := parsed as Dictionary
	if int(data.get("cell_count", 0)) <= 0 or not is_equal_approx(float(data.get("pixel_scale", 0.0)), 1.0):
		return false
	var size_value: Variant = data.get("packed_size", [])
	if size_value is Array and (size_value as Array).size() >= 2:
		_compact_packed_size = Vector2i(int((size_value as Array)[0]), int((size_value as Array)[1]))
	var entries_value: Variant = data.get("entries", [])
	if not entries_value is Array:
		return false
	for entry_value in entries_value as Array:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var source_value: Variant = entry.get("source", {})
		var packed_value: Variant = entry.get("packed", {})
		if not source_value is Dictionary or not packed_value is Dictionary:
			continue
		var source := _dict_to_rect2i(source_value as Dictionary)
		var packed := _dict_to_rect2i(packed_value as Dictionary)
		if source.size.x <= 0 or source.size.y <= 0 or packed.size != source.size:
			continue
		var normalized := {"source": source, "packed": packed}
		_compact_region_entries.append(normalized)
		_compact_region_exact[_rect_key(source)] = packed
	return not _compact_region_entries.is_empty()


func _load_png_texture(path: String) -> Texture2D:
	# Raw byte decoding avoids dependency on .godot/imported state and makes the
	# generated atlas usable immediately after CI/editor regeneration.
	if not FileAccess.file_exists(path):
		return null
	var png_bytes := FileAccess.get_file_as_bytes(path)
	if png_bytes.is_empty():
		return null
	var image := Image.new()
	var error := image.load_png_from_buffer(png_bytes)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


func _remap_visible_regions_to_compact() -> void:
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite == null or not sprite.visible or not sprite.region_enabled:
			continue
		var source_region := _rect2_to_rect2i(sprite.region_rect)
		if source_region.size.x <= 0 or source_region.size.y <= 0:
			continue
		var mapped := _compact_rect_for_source_region(source_region)
		if mapped.size.x <= 0 or mapped.size.y <= 0:
			var warning_key := _rect_key(source_region)
			if not _compact_missing_region_warnings.has(warning_key):
				_compact_missing_region_warnings[warning_key] = true
				push_warning("JunoBase: visible source region has no compact-atlas mapping: %s" % warning_key)
			sprite.visible = false
			continue
		sprite.region_rect = Rect2(mapped.position, mapped.size)


func _compact_rect_for_source_region(source_region: Rect2i) -> Rect2i:
	var key := _rect_key(source_region)
	if _compact_region_cache.has(key):
		return _compact_region_cache[key] as Rect2i
	if _compact_region_exact.has(key):
		var exact := _compact_region_exact[key] as Rect2i
		_compact_region_cache[key] = exact
		return exact
	# Rotating/cutting Alabaster limbs can expose a sub-rectangle of an authored
	# source cell. Find the retained parent cell, then preserve the exact offset
	# and dimensions inside its packed destination. No pixel is rescaled.
	for entry in _compact_region_entries:
		var source := entry.get("source", Rect2i()) as Rect2i
		if source.encloses(source_region):
			var packed := entry.get("packed", Rect2i()) as Rect2i
			var delta := source_region.position - source.position
			var translated := Rect2i(packed.position + delta, source_region.size)
			_compact_region_cache[key] = translated
			return translated
	_compact_region_cache[key] = Rect2i()
	return Rect2i()


func _dict_to_rect2i(value: Dictionary) -> Rect2i:
	return Rect2i(
		int(value.get("x", 0)), int(value.get("y", 0)),
		int(value.get("w", 0)), int(value.get("h", 0))
	)


func _rect2_to_rect2i(value: Rect2) -> Rect2i:
	return Rect2i(
		int(round(value.position.x)), int(round(value.position.y)),
		int(round(value.size.x)), int(round(value.size.y))
	)


func _rect_key(rect: Rect2i) -> String:
	return "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["profile"] = Profile.PROFILE_ID
	result["profile_label"] = Profile.LABEL
	result["core_animation_count"] = _anims.size()
	# Keep core_atlas_* compatibility for existing tools while exposing that the
	# active sheet is now the physically packed atlas rather than the masked sheet.
	result["core_atlas_active"] = _juno_base_core_atlas_active
	result["core_atlas_path"] = COMPACT_ATLAS_PATH
	result["compact_atlas_active"] = _juno_base_compact_atlas_active
	result["compact_atlas_path"] = COMPACT_ATLAS_PATH
	result["compact_map_path"] = COMPACT_MAP_PATH
	result["compact_packed_size"] = _compact_packed_size
	result["compact_mapping_count"] = _compact_region_entries.size()
	return result


func get_juno_base_profile_summary() -> Dictionary:
	return {
		"profile": Profile.PROFILE_ID,
		"label": Profile.LABEL,
		"core_animations": Profile.core_animation_names(),
		"animation_count": _anims.size(),
		"core_atlas_active": _juno_base_core_atlas_active,
		"core_atlas_path": COMPACT_ATLAS_PATH,
		"compact_atlas_active": _juno_base_compact_atlas_active,
		"compact_atlas_path": COMPACT_ATLAS_PATH,
		"compact_map_path": COMPACT_MAP_PATH,
		"compact_packed_size": _compact_packed_size,
		"compact_mapping_count": _compact_region_entries.size(),
		"bone_count": _nodes.size(),
		"sprite_record_count": _sprite_records.size(),
	}
