extends SceneTree

const PLAYER_TUNING_PATH := "res://data/player_tuning.json"
const PLAYER_SCENE_PATH := "res://scenes/Player.tscn"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tuning := _load_default_tuning()
	if failures.is_empty():
		_validate_tuning_values(tuning)
	if failures.is_empty():
		await _validate_player_scene(tuning)

	if failures.is_empty():
		print("PLAYER_VISUAL_TUNING_VALIDATION_PASS")
		quit(0)
		return

	for failure in failures:
		push_error("PLAYER_VISUAL_TUNING_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _load_default_tuning() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_TUNING_PATH):
		failures.append("Missing player tuning file.")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_TUNING_PATH))
	if not (parsed is Dictionary):
		failures.append("Player tuning file is not a JSON object.")
		return {}
	var default_value: Variant = (parsed as Dictionary).get("default", {})
	if not (default_value is Dictionary):
		failures.append("Player tuning default record is missing.")
		return {}
	return default_value as Dictionary


func _validate_tuning_values(tuning: Dictionary) -> void:
	for key in ["visual_scale", "visual_offset_x", "visual_offset_y"]:
		if not tuning.has(key):
			failures.append("Player tuning is missing %s." % key)
	var visual_scale := float(tuning.get("visual_scale", 0.0))
	if visual_scale <= 0.0 or visual_scale > 8.0:
		failures.append("visual_scale must be greater than zero and no larger than 8.0.")
	for key in ["visual_offset_x", "visual_offset_y"]:
		if absf(float(tuning.get(key, 0.0))) > 1024.0:
			failures.append("%s is outside the supported range." % key)
	var light_value: Variant = tuning.get("light", {})
	if not (light_value is Dictionary):
		failures.append("Player tuning light record is missing.")
		return
	var light := light_value as Dictionary
	for key in [
		"enabled",
		"visual_aura_enabled",
		"color",
		"emission",
		"radius_scale",
		"perspective_angle_degrees",
		"ground_ellipse_scale",
		"ground_ellipse_offset",
		"ground_halo_alpha",
		"ground_halo_intensity",
		"ground_halo_texture_scale",
		"ground_halo_blur",
		"day_multiplier",
		"night_multiplier",
		"offset",
	]:
		if not light.has(key):
			failures.append("Player light tuning is missing %s." % key)
	var perspective_angle := float(light.get("perspective_angle_degrees", 0.0))
	if perspective_angle < 15.0 or perspective_angle > 90.0:
		failures.append("Player light perspective angle is outside the supported 15-90 degree range.")
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPlayerLightPerspectiveSuite.gd")
	if not editor_text.contains("Light Perspective Angle") or not editor_text.contains("perspective_angle_degrees"):
		failures.append("Content Editor is missing the player light perspective field.")


func _validate_player_scene(tuning: Dictionary) -> void:
	var packed_scene := load(PLAYER_SCENE_PATH) as PackedScene
	if packed_scene == null:
		failures.append("Player scene could not be loaded.")
		return
	var player := packed_scene.instantiate()
	root.add_child(player)
	await process_frame

	var animated_sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animated_sprite == null:
		failures.append("Player scene has no AnimatedSprite2D.")
		player.queue_free()
		return

	var expected_scale := Vector2.ONE * float(tuning.get("visual_scale", 1.0))
	var expected_offset := Vector2(
		float(tuning.get("visual_offset_x", 0.0)),
		float(tuning.get("visual_offset_y", 0.0))
	)
	if not animated_sprite.scale.is_equal_approx(expected_scale):
		failures.append("AnimatedSprite2D scale is %s; expected %s." % [animated_sprite.scale, expected_scale])
	if not animated_sprite.position.is_equal_approx(expected_offset):
		failures.append("AnimatedSprite2D position is %s; expected %s." % [animated_sprite.position, expected_offset])

	var light_config := tuning.get("light", {}) as Dictionary
	var night_light := player.get_node_or_null("NightLight") as Node2D
	if night_light == null:
		failures.append("Player scene has no NightLight.")
	else:
		if bool(night_light.get("visual_enabled")):
			failures.append("Player compact aura must remain disabled; projected ground light is a separate node.")
		if not is_equal_approx(float(night_light.get("point_light_energy")), float(light_config.get("emission", 0.0))):
			failures.append("Player light emission does not match Player Tuning.")
		if not is_equal_approx(float(night_light.get("point_light_scale")), float(light_config.get("radius_scale", 0.0))):
			failures.append("Player light radius does not match Player Tuning.")
		var projected_ground_light := night_light.get_node_or_null("PlayerGroundLight") as Sprite2D
		var ground_light_enabled := bool(light_config.get("visual_aura_enabled", true))
		if ground_light_enabled and projected_ground_light == null:
			failures.append("Player projected ground light was not created from Player Tuning.")
		elif projected_ground_light != null:
			var expected_texture_scale := float(light_config.get("ground_halo_texture_scale", 0.20))
			var expected_blur := float(light_config.get("ground_halo_blur", 2.0))
			var expected_render_scale := expected_texture_scale * (1.0 + expected_blur * 0.06)
			if not projected_ground_light.scale.is_equal_approx(Vector2.ONE * expected_render_scale):
				failures.append("Player projected ground-light scale does not match Player Tuning.")
			if not is_equal_approx(float(projected_ground_light.get_meta("ground_light_texture_scale", -1.0)), expected_texture_scale):
				failures.append("Player projected ground-light texture scale metadata does not match Player Tuning.")
			if not is_equal_approx(float(projected_ground_light.get_meta("ground_light_blur", -1.0)), expected_blur):
				failures.append("Player projected ground-light blur does not match Player Tuning.")
		var perspective_angle := clampf(float(light_config.get("perspective_angle_degrees", 50.0)), 15.0, 90.0)
		var expected_vertical_projection := clampf(sin(deg_to_rad(perspective_angle)), 0.20, 1.0)
		var ellipse_scale_value: Variant = light_config.get("ground_ellipse_scale", {})
		var ellipse_scale := Vector2.ONE
		if ellipse_scale_value is Dictionary:
			var ellipse_scale_record := ellipse_scale_value as Dictionary
			ellipse_scale = Vector2(
				maxf(float(ellipse_scale_record.get("x", 1.0)), 0.05),
				maxf(float(ellipse_scale_record.get("y", 1.0)), 0.05)
			)
		var expected_light_scale := Vector2(
			ellipse_scale.x,
			ellipse_scale.y * expected_vertical_projection
		)
		if not night_light.scale.is_equal_approx(expected_light_scale):
			failures.append("Player light is not projected to the configured ground ellipse: %s; expected %s." % [night_light.scale, expected_light_scale])
		if perspective_angle < 89.0 and night_light.scale.y >= night_light.scale.x:
			failures.append("Non-zenith player light remains circular instead of elliptical.")
	if not (player as Node2D).scale.is_equal_approx(Vector2.ONE):
		failures.append("Player physics node scale changed; visual tuning must not scale collision or movement.")

	var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		failures.append("Player scene has no CollisionShape2D.")
	elif not collision.scale.is_equal_approx(Vector2.ONE):
		failures.append("CollisionShape2D scale changed; visual tuning must remain presentation-only.")

	player.queue_free()
