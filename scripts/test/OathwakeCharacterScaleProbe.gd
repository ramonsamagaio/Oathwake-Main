extends SceneTree

const JunoRig := preload("res://scripts/systems/bones/BonesSystem.gd")
const ANIMATION_NAME := "idle"
const TICK_RATE := 60.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rig := JunoRig.new() as Node2D
	if rig == null:
		printerr("OATHWAKE_CHARACTER_SCALE_PROBE_FAIL could_not_create_juno")
		quit(1)
		return
	root.add_child(rig)
	await process_frame
	await process_frame
	rig.set_process(false)

	var animation_value: Variant = rig.call("get_animation_data", ANIMATION_NAME)
	if not animation_value is Dictionary:
		printerr("OATHWAKE_CHARACTER_SCALE_PROBE_FAIL idle_missing")
		quit(1)
		return
	var animation := animation_value as Dictionary
	var start_frame := int(animation.get("animStart", 0))
	var frame_count := maxi(int(animation.get("frameCnt", start_frame + 1)), start_frame + 1)
	var frame_repeat := maxf(float(animation.get("frameRepeat", 1.0)), 1.0)

	var overall := Rect2()
	var has_overall := false
	var south := Rect2()
	var has_south := false
	var max_width := 0.0
	var max_height := 0.0
	var min_width := INF
	var min_height := INF
	var samples := 0

	for facing_index in range(16):
		var radians := deg_to_rad(float(facing_index) * 22.5)
		var direction := Vector2(sin(radians), -cos(radians))
		rig.call("set_facing_from_vector", direction)
		for frame in range(start_frame, frame_count):
			var time := float(frame - start_frame) * frame_repeat / TICK_RATE
			rig.set("current_animation", ANIMATION_NAME)
			rig.set("animation_time", time)
			rig.call("_apply_pose")
			var bounds := _visible_bounds(rig)
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				continue
			if not has_overall:
				overall = bounds
				has_overall = true
			else:
				overall = overall.merge(bounds)
			if facing_index == 8:
				if not has_south:
					south = bounds
					has_south = true
				else:
					south = south.merge(bounds)
			max_width = maxf(max_width, bounds.size.x)
			max_height = maxf(max_height, bounds.size.y)
			min_width = minf(min_width, bounds.size.x)
			min_height = minf(min_height, bounds.size.y)
			samples += 1

	if not has_overall or samples == 0:
		printerr("OATHWAKE_CHARACTER_SCALE_PROBE_FAIL no_visible_idle_samples")
		quit(1)
		return

	print("OATHWAKE_CHARACTER_SCALE_PROBE_OK animation=idle samples=%d overall=%.1fx%.1f max_pose=%.1fx%.1f min_pose=%.1fx%.1f south=%.1fx%.1f player_collision=24 visual_scale=1.0" % [
		samples,
		overall.size.x, overall.size.y,
		max_width, max_height,
		min_width, min_height,
		south.size.x if has_south else 0.0,
		south.size.y if has_south else 0.0,
	])
	rig.queue_free()
	await process_frame
	quit(0)


func _visible_bounds(rig: Node2D) -> Rect2:
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return Rect2()
	var merged := Rect2()
	var has_bounds := false
	for record_value in records_value as Array:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var rect := sprite.get_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var xf := sprite.global_transform
		var p0 := xf * rect.position
		var p1 := xf * Vector2(rect.end.x, rect.position.y)
		var p2 := xf * rect.end
		var p3 := xf * Vector2(rect.position.x, rect.end.y)
		var min_x := minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
		var min_y := minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
		var max_x := maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
		var max_y := maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
		var transformed := Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		if not has_bounds:
			merged = transformed
			has_bounds = true
		else:
			merged = merged.merge(transformed)
	return merged if has_bounds else Rect2()
