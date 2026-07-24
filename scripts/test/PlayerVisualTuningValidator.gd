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
	if not (player as Node2D).scale.is_equal_approx(Vector2.ONE):
		failures.append("Player physics node scale changed; visual tuning must not scale collision or movement.")

	var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		failures.append("Player scene has no CollisionShape2D.")
	elif not collision.scale.is_equal_approx(Vector2.ONE):
		failures.append("CollisionShape2D scale changed; visual tuning must remain presentation-only.")

	player.queue_free()
