extends "res://scripts/test/AlabasterJunoBaseIntegrationValidator.gd"

# Compact JunoBase contract:
# - the skeleton, animation data and rendered pose stay identical to Juno;
# - every visible source region is translated into the deterministic packed atlas;
# - dimensions and pixels remain exactly 1:1, including cut/rotating sub-regions.

const COMPACT_MAP_PATH := "res://data/labs/alabaster/juno_base_compact_map.json"
const SOURCE_ATLAS_SIZE := Vector2i(672, 240)


func _validate_juno_base_runtime() -> bool:
	var compact_data := _load_compact_contract()
	if compact_data.is_empty():
		return false
	var compact_entries := compact_data.get("entries", []) as Array
	var packed_size := compact_data.get("packed_size", Vector2i.ZERO) as Vector2i
	var area_ratio := float(compact_data.get("area_ratio", 1.0))

	var juno := JunoRigScript.new() as Node2D
	var base := JunoBaseRigScript.new() as Node2D
	if juno == null or base == null:
		_fail("could not instantiate Juno/JunoBase runtimes")
		return false
	root.add_child(juno)
	root.add_child(base)
	await process_frame
	await process_frame
	juno.set_process(false)
	base.set_process(false)

	var summary_value: Variant = base.call("get_juno_base_profile_summary")
	if not summary_value is Dictionary:
		_fail("JunoBase exposes no profile summary")
		return false
	var summary := summary_value as Dictionary
	if not bool(summary.get("compact_atlas_active", false)):
		_fail("JunoBase did not load the compact atlas")
		return false
	if int(summary.get("compact_mapping_count", 0)) != 286:
		_fail("JunoBase runtime compact mapping count is not 286")
		return false
	if summary.get("compact_packed_size", Vector2i.ZERO) != packed_size:
		_fail("JunoBase runtime packed size disagrees with compact map")
		return false

	var builtin := Library.load_builtin_animations("juno_base")
	if builtin.size() != 16:
		_fail("JunoBase library expected 16 builtin clips, got %d" % builtin.size())
		return false
	for animation_name in JunoBaseProfile.core_animation_names():
		if not builtin.has(animation_name) or not bool(base.call("has_animation", animation_name)):
			_fail("JunoBase core animation missing: %s" % animation_name)
			return false

	var juno_bones_value: Variant = juno.call("get_bone_names")
	var base_bones_value: Variant = base.call("get_bone_names")
	if not juno_bones_value is Array or not base_bones_value is Array or juno_bones_value != base_bones_value:
		_fail("JunoBase skeleton bone names differ from Juno")
		return false
	var juno_rest_value: Variant = juno.call("get_bone_rest_local_positions")
	var base_rest_value: Variant = base.call("get_bone_rest_local_positions")
	if not juno_rest_value is Dictionary or not base_rest_value is Dictionary or not _vector_dictionary_matches(juno_rest_value as Dictionary, base_rest_value as Dictionary):
		_fail("JunoBase authored REST positions differ from Juno")
		return false

	var source_atlas_value: Variant = juno.get("_atlas")
	var compact_atlas_value: Variant = base.get("_atlas")
	if not source_atlas_value is Texture2D or not compact_atlas_value is Texture2D:
		_fail("Juno/JunoBase atlas texture unavailable")
		return false
	var source_image := (source_atlas_value as Texture2D).get_image()
	var compact_image := (compact_atlas_value as Texture2D).get_image()
	if source_image == null or source_image.is_empty() or compact_image == null or compact_image.is_empty():
		_fail("Juno/JunoBase atlas image unavailable")
		return false
	source_image.convert(Image.FORMAT_RGBA8)
	compact_image.convert(Image.FORMAT_RGBA8)
	if source_image.get_size() != SOURCE_ATLAS_SIZE:
		_fail("unexpected Juno source atlas size: %s" % str(source_image.get_size()))
		return false
	if compact_image.get_size() != packed_size:
		_fail("compact PNG size disagrees with map: png=%s map=%s" % [str(compact_image.get_size()), str(packed_size)])
		return false
	if compact_image.get_width() >= source_image.get_width() and compact_image.get_height() >= source_image.get_height():
		_fail("compact atlas did not reduce physical atlas dimensions")
		return false

	var exact_map: Dictionary = {}
	for entry_value in compact_entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var source := entry.get("source", Rect2i()) as Rect2i
		var packed := entry.get("packed", Rect2i()) as Rect2i
		exact_map[_rect_key(source)] = packed

	var pixel_cache: Dictionary = {}
	var sampled_frames := 0
	var visible_samples := 0
	for animation_name in JunoBaseProfile.core_animation_names():
		var animation_value: Variant = base.call("get_animation_data", animation_name)
		if not animation_value is Dictionary:
			_fail("cannot read JunoBase animation data: %s" % animation_name)
			return false
		var animation := animation_value as Dictionary
		var start_frame := int(animation.get("animStart", 0))
		var frame_count := maxi(int(animation.get("frameCnt", start_frame + 1)), start_frame + 1)
		var frame_repeat := maxf(float(animation.get("frameRepeat", 1.0)), 1.0)
		for facing_index in range(16):
			var radians := deg_to_rad(float(facing_index) * 22.5)
			var direction := Vector2(sin(radians), -cos(radians))
			juno.call("set_facing_from_vector", direction)
			base.call("set_facing_from_vector", direction)
			for frame in range(start_frame, frame_count):
				var time := float(frame - start_frame) * frame_repeat / TICK_RATE
				_set_pose_frame(juno, animation_name, time)
				_set_pose_frame(base, animation_name, time)
				var pose_result := _compare_compact_pose(juno, base, source_image, compact_image, compact_entries, exact_map, pixel_cache)
				if not bool(pose_result.get("ok", false)):
					_fail("JunoBase compact mapping diverged at %s frame=%d facing=%d: %s" % [
						animation_name, frame, facing_index, str(pose_result.get("error", "unknown"))
					])
					return false
				visible_samples += int(pose_result.get("visible", 0))
				sampled_frames += 1

	print("ALABASTER_JUNO_BASE_RUNTIME_OK animations=16 sampled_pose_frames=%d visible_samples=%d mapped_regions=%d packed=%dx%d area_ratio=%.4f pixel_scale=1.0 pixel_exact=true" % [
		sampled_frames, visible_samples, pixel_cache.size(), packed_size.x, packed_size.y, area_ratio,
	])
	juno.queue_free()
	base.queue_free()
	await process_frame
	return true


func _load_compact_contract() -> Dictionary:
	if not FileAccess.file_exists(COMPACT_MAP_PATH):
		_fail("JunoBase compact map is missing")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMPACT_MAP_PATH))
	if not parsed is Dictionary:
		_fail("JunoBase compact map is invalid JSON")
		return {}
	var data := parsed as Dictionary
	if int(data.get("cell_count", 0)) != 286:
		_fail("compact map expected 286 source cells")
		return {}
	if not is_equal_approx(float(data.get("pixel_scale", 0.0)), 1.0):
		_fail("compact map pixel_scale must remain exactly 1.0")
		return {}
	var size_value: Variant = data.get("packed_size", [])
	if not size_value is Array or (size_value as Array).size() < 2:
		_fail("compact map packed_size is missing")
		return {}
	var packed_size := Vector2i(int((size_value as Array)[0]), int((size_value as Array)[1]))
	if packed_size.x <= 0 or packed_size.y <= 0:
		_fail("compact map packed_size is invalid")
		return {}
	var source_area := SOURCE_ATLAS_SIZE.x * SOURCE_ATLAS_SIZE.y
	var packed_area := packed_size.x * packed_size.y
	if packed_area >= source_area:
		_fail("compact atlas area was not reduced")
		return {}
	var entries_value: Variant = data.get("entries", [])
	if not entries_value is Array or (entries_value as Array).size() != 286:
		_fail("compact map entry count is not 286")
		return {}
	var entries: Array[Dictionary] = []
	var source_keys: Dictionary = {}
	for entry_value in entries_value as Array:
		if not entry_value is Dictionary:
			_fail("compact map contains a non-dictionary entry")
			return {}
		var raw := entry_value as Dictionary
		var source_value: Variant = raw.get("source", {})
		var packed_value: Variant = raw.get("packed", {})
		if not source_value is Dictionary or not packed_value is Dictionary:
			_fail("compact map entry has invalid rectangles")
			return {}
		var source := _dict_rect(source_value as Dictionary)
		var packed := _dict_rect(packed_value as Dictionary)
		if source.size.x <= 0 or source.size.y <= 0 or source.size != packed.size:
			_fail("compact mapping changed source pixel dimensions")
			return {}
		if not Rect2i(Vector2i.ZERO, SOURCE_ATLAS_SIZE).encloses(source):
			_fail("compact source rectangle is outside source atlas: %s" % _rect_key(source))
			return {}
		if not Rect2i(Vector2i.ZERO, packed_size).encloses(packed):
			_fail("compact destination is outside packed atlas: %s" % _rect_key(packed))
			return {}
		var source_key := _rect_key(source)
		if source_keys.has(source_key):
			_fail("compact map duplicates source cell: %s" % source_key)
			return {}
		source_keys[source_key] = true
		for existing in entries:
			var existing_packed := existing.get("packed", Rect2i()) as Rect2i
			if existing_packed.intersects(packed):
				_fail("compact destination rectangles overlap")
				return {}
		entries.append({"source": source, "packed": packed})
	return {
		"entries": entries,
		"packed_size": packed_size,
		"area_ratio": float(packed_area) / float(source_area),
	}


func _compare_compact_pose(
	juno: Node2D,
	base: Node2D,
	source_image: Image,
	compact_image: Image,
	entries: Array,
	exact_map: Dictionary,
	pixel_cache: Dictionary
) -> Dictionary:
	var juno_records_value: Variant = juno.get("_sprite_records")
	var base_records_value: Variant = base.get("_sprite_records")
	if not juno_records_value is Array or not base_records_value is Array:
		return {"ok": false, "error": "sprite records unavailable"}
	var juno_records := juno_records_value as Array
	var base_records := base_records_value as Array
	if juno_records.size() != base_records.size():
		return {"ok": false, "error": "sprite record counts differ"}
	var visible := 0
	for index in range(juno_records.size()):
		if not juno_records[index] is Dictionary or not base_records[index] is Dictionary:
			continue
		var source_sprite := (juno_records[index] as Dictionary).get("sprite") as Sprite2D
		var compact_sprite := (base_records[index] as Dictionary).get("sprite") as Sprite2D
		if source_sprite == null or compact_sprite == null:
			continue
		if source_sprite.visible != compact_sprite.visible:
			return {"ok": false, "error": "visibility differs for record %d" % index}
		if not source_sprite.visible:
			continue
		visible += 1
		if source_sprite.flip_h != compact_sprite.flip_h or source_sprite.flip_v != compact_sprite.flip_v:
			return {"ok": false, "error": "sprite flip differs for record %d" % index}
		if not source_sprite.position.is_equal_approx(compact_sprite.position):
			return {"ok": false, "error": "sprite position differs for record %d" % index}
		if not source_sprite.scale.is_equal_approx(compact_sprite.scale):
			return {"ok": false, "error": "sprite scale differs for record %d" % index}
		if not is_equal_approx(source_sprite.rotation, compact_sprite.rotation):
			return {"ok": false, "error": "sprite rotation differs for record %d" % index}
		if not source_sprite.offset.is_equal_approx(compact_sprite.offset):
			return {"ok": false, "error": "sprite pivot/offset differs for record %d" % index}
		var source_rect := _sprite_rect(source_sprite)
		var expected := _mapped_rect(source_rect, entries, exact_map)
		if expected.size.x <= 0 or expected.size.y <= 0:
			return {"ok": false, "error": "no compact mapping for source region %s" % _rect_key(source_rect)}
		var actual := _sprite_rect(compact_sprite)
		if actual != expected:
			return {"ok": false, "error": "region %s expected %s got %s" % [_rect_key(source_rect), _rect_key(expected), _rect_key(actual)]}
		var pixel_key := "%s>%s" % [_rect_key(source_rect), _rect_key(actual)]
		if not pixel_cache.has(pixel_key):
			pixel_cache[pixel_key] = _rect_pixels_match_translated(source_image, compact_image, source_rect, actual)
		if not bool(pixel_cache[pixel_key]):
			return {"ok": false, "error": "pixel mismatch %s" % pixel_key}
	return {"ok": true, "visible": visible}


func _mapped_rect(source_region: Rect2i, entries: Array, exact_map: Dictionary) -> Rect2i:
	var key := _rect_key(source_region)
	if exact_map.has(key):
		return exact_map[key] as Rect2i
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var source := entry.get("source", Rect2i()) as Rect2i
		if source.encloses(source_region):
			var packed := entry.get("packed", Rect2i()) as Rect2i
			return Rect2i(packed.position + (source_region.position - source.position), source_region.size)
	return Rect2i()


func _rect_pixels_match_translated(source_image: Image, packed_image: Image, source: Rect2i, packed: Rect2i) -> bool:
	if source.size != packed.size:
		return false
	var source_bounds := Rect2i(Vector2i.ZERO, source_image.get_size())
	var packed_bounds := Rect2i(Vector2i.ZERO, packed_image.get_size())
	if not source_bounds.encloses(source) or not packed_bounds.encloses(packed):
		return false
	for offset_y in range(source.size.y):
		for offset_x in range(source.size.x):
			var a := source_image.get_pixel(source.position.x + offset_x, source.position.y + offset_y)
			var b := packed_image.get_pixel(packed.position.x + offset_x, packed.position.y + offset_y)
			if a != b:
				return false
	return true


func _sprite_rect(sprite: Sprite2D) -> Rect2i:
	var region := sprite.region_rect
	return Rect2i(roundi(region.position.x), roundi(region.position.y), roundi(region.size.x), roundi(region.size.y))


func _dict_rect(value: Dictionary) -> Rect2i:
	return Rect2i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("w", 0)), int(value.get("h", 0)))


func _rect_key(rect: Rect2i) -> String:
	return "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
