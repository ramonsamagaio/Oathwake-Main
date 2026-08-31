extends "res://scripts/test/AlabasterJunoBaseIntegrationValidator.gd"

# The first validator deliberately treated every visible Sprite2D region as
# requiring opaque pixels. Juno itself uses a few intentionally blank regions,
# so the real invariant is stronger and simpler: every region used by a core
# pose must be pixel-identical to the full Juno atlas.


func _validate_juno_base_runtime() -> bool:
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
	if not bool(summary.get("core_atlas_active", false)):
		_fail("JunoBase did not load the generated core atlas")
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
	var core_atlas_value: Variant = base.get("_atlas")
	if not source_atlas_value is Texture2D or not core_atlas_value is Texture2D:
		_fail("Juno/JunoBase atlas texture unavailable")
		return false
	var source_image := (source_atlas_value as Texture2D).get_image()
	var core_image := (core_atlas_value as Texture2D).get_image()
	if source_image == null or source_image.is_empty() or core_image == null or core_image.is_empty():
		_fail("Juno/JunoBase atlas image unavailable")
		return false
	source_image.convert(Image.FORMAT_RGBA8)
	core_image.convert(Image.FORMAT_RGBA8)
	if source_image.get_size() != core_image.get_size():
		_fail("JunoBase atlas dimensions differ from Juno")
		return false

	var region_cache: Dictionary = {}
	var sampled_frames := 0
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
				if _visible_region_signature(juno) != _visible_region_signature(base):
					_fail("JunoBase visual mapping diverged from Juno at %s frame=%d facing=%d" % [animation_name, frame, facing_index])
					return false
				var mismatch := _first_active_pixel_mismatch(base, source_image, core_image, region_cache)
				if not mismatch.is_empty():
					_fail("JunoBase atlas differs from Juno at %s frame=%d facing=%d region=%s" % [animation_name, frame, facing_index, mismatch])
					return false
				sampled_frames += 1

	print("ALABASTER_JUNO_BASE_RUNTIME_OK animations=16 sampled_pose_frames=%d verified_regions=%d pixel_exact=true" % [sampled_frames, region_cache.size()])
	juno.queue_free()
	base.queue_free()
	await process_frame
	return true


func _first_active_pixel_mismatch(rig: Node2D, source_image: Image, core_image: Image, cache: Dictionary) -> String:
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return "missing_sprite_records"
	for record_value in records_value as Array:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		var rect := Rect2i(roundi(region.position.x), roundi(region.position.y), roundi(region.size.x), roundi(region.size.y))
		var key := "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		if cache.has(key):
			if not bool(cache[key]):
				return key
			continue
		var matches := _rect_pixels_match(source_image, core_image, rect)
		cache[key] = matches
		if not matches:
			return key
	return ""


func _rect_pixels_match(a: Image, b: Image, rect: Rect2i) -> bool:
	var bounds := Rect2i(Vector2i.ZERO, a.get_size())
	var clipped := rect.intersection(bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return false
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true
