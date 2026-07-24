extends SceneTree

const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	await physics_frame

	var sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		failures.append("Player has no runtime AnimatedSprite2D for life animation validation.")
		await _finish(player)
		return

	_validate_registered_animation(sprite, "hurt")
	_validate_registered_animation(sprite, "death")
	await _validate_hurt_flow(player, sprite)
	await _validate_death_flow(player, sprite)
	await _finish(player)


func _validate_registered_animation(sprite: AnimatedSprite2D, animation_name: String) -> void:
	if not sprite.sprite_frames.has_animation(animation_name):
		failures.append("Player is missing registered animation %s." % animation_name)
		return
	if sprite.sprite_frames.get_frame_count(animation_name) <= 0:
		failures.append("Player animation %s has no frames." % animation_name)


func _validate_hurt_flow(player: CharacterBody2D, sprite: AnimatedSprite2D) -> void:
	var health_before := int(player.get("health"))
	player.call("take_damage", 1)
	await process_frame
	if int(player.get("health")) != health_before - 1:
		failures.append("Nonfatal damage did not reduce player health exactly once.")
	if not bool(player.call("is_hurt_animation_active")):
		failures.append("Nonfatal damage did not activate the hurt state.")
	if str(sprite.animation) != "hurt":
		failures.append("Nonfatal damage played %s instead of hurt." % sprite.animation)

	var duration := _get_animation_duration(sprite, "hurt")
	await create_timer(duration + 0.12).timeout
	await process_frame
	if bool(player.call("is_hurt_animation_active")):
		failures.append("Hurt state did not release after the native animation duration.")
	if not str(sprite.animation).begins_with("idle_"):
		failures.append("Player did not return to idle after hurt; current animation is %s." % sprite.animation)


func _validate_death_flow(player: CharacterBody2D, sprite: AnimatedSprite2D) -> void:
	player.set("invulnerability_time_left", 0.0)
	var respawn_position := Vector2(36.0, 52.0)
	var death_position := Vector2(180.0, 220.0)
	player.call("set_respawn_point", respawn_position)
	player.global_position = death_position
	var lethal_damage := int(player.get("health"))
	player.call("take_damage", lethal_damage)
	await process_frame

	if int(player.get("health")) != 0:
		failures.append("Lethal damage respawned immediately instead of holding health at zero during death.")
	if not bool(player.call("is_death_animation_active")):
		failures.append("Lethal damage did not activate the death state.")
	if str(sprite.animation) != "death":
		failures.append("Lethal damage played %s instead of death." % sprite.animation)
	if player.global_position.distance_to(death_position) > 0.01:
		failures.append("Player moved to the respawn point before the death animation finished.")

	var duration := _get_animation_duration(sprite, "death")
	await create_timer(duration + 0.30).timeout
	await process_frame
	if bool(player.call("is_death_animation_active")):
		failures.append("Death state did not release after the death animation and hold time.")
	if int(player.get("health")) != int(player.get("max_health")):
		failures.append("Player health was not restored after death animation completed.")
	if player.global_position.distance_to(respawn_position) > 0.01:
		failures.append("Player did not respawn at the configured respawn point after death.")
	if not str(sprite.animation).begins_with("idle_"):
		failures.append("Player did not return to idle after respawn; current animation is %s." % sprite.animation)


func _get_animation_duration(sprite: AnimatedSprite2D, animation_name: String) -> float:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation_name):
		return 0.1
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	var fps := sprite.sprite_frames.get_animation_speed(animation_name)
	if frame_count <= 0 or fps <= 0.0:
		return 0.1
	return float(frame_count) / fps


func _finish(player: Node) -> void:
	if player != null:
		player.queue_free()
	await process_frame
	if failures.is_empty():
		print("PLAYER_LIFE_ANIMATION_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYER_LIFE_ANIMATION_VALIDATION_FAILURE: %s" % failure)
	quit(1)
