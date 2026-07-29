extends SceneTree

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")
const DOOR_SCENE := preload("res://scenes/buildings/Door.tscn")
const SLIME_SCENE := preload("res://scenes/enemies/Slime.tscn")
const SKELETON_SCENE := preload("res://scenes/enemies/Skeleton.tscn")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_validate_content()
	await _validate_runtime()
	if failures.is_empty():
		print("BUILD_CRAFT_MONSTER_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BUILD_CRAFT_MONSTER_VALIDATION_FAILURE: %s" % failure)
	quit(1)

func _validate_content() -> void:
	var db := root.get_node_or_null("ContentDB")
	if db == null:
		failures.append("ContentDB unavailable")
		return
	for building_id in ["wall", "campfire", "workbench", "door"]:
		if not db.has_building(building_id): failures.append("Missing building %s" % building_id)
	var door: Dictionary = db.get_building("door")
	if str(door.get("scene_path", "")) != "res://scenes/buildings/Door.tscn": failures.append("Door scene not configured")
	var slime: Dictionary = db.get_monster("slime")
	var skel: Dictionary = db.get_monster("skeleton")
	if (slime.get("animations", {}) as Dictionary).size() < 20: failures.append("Slime1 animations incomplete")
	if (skel.get("animations", {}) as Dictionary).size() < 12: failures.append("Skeleton placeholder animations incomplete")
	for monster_data in [slime, skel]:
		var locomotion_value: Variant = (monster_data as Dictionary).get("locomotion", {})
		if not locomotion_value is Dictionary or float((locomotion_value as Dictionary).get("move_speed", 0.0)) <= 0.0:
			failures.append("Monster locomotion.move_speed is missing or invalid")
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorRuntimeTuningSuite.gd")
	for token in ["Movement Speed", "locomotion[\"move_speed\"]", "Attack Contact Frame", "attack_hit_frame", "Saved and applied to the running game"]:
		if not editor_text.contains(token):
			failures.append("Runtime Content Editor monster/live-save contract is missing %s" % token)
	var enhanced_text := FileAccess.get_file_as_string("res://scripts/enemies/EnemyBaseEnhanced.gd")
	for token in ["_refresh_runtime_monster_content", "_monster_locomotion.configure", "EnemyScreenCombatSuite.gd"]:
		if not enhanced_text.contains(token):
			failures.append("Living monsters cannot refresh locomotion/combat after content reload: %s" % token)
	var screen_combat_text := FileAccess.get_file_as_string("res://scripts/enemies/EnemyScreenCombatSuite.gd")
	for token in ["is_visible_for_activation", "_wait_for_attack_contact_frame", "attack_contact_frame - 1", "player_in_contact"]:
		if not screen_combat_text.contains(token):
			failures.append("Monster screen/contact-frame runtime is missing %s" % token)

func _validate_runtime() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	var light := player.get_node_or_null("NightLight")
	if light == null or not bool(light.get("use_point_light")) or float(light.get("point_light_energy")) <= 0.0:
		failures.append("Player small point light is disabled")
	elif not bool(light.get("visual_enabled")):
		failures.append("Player visible aura is disabled")

	var campfire := BUILDING_SCENE.instantiate()
	root.add_child(campfire)
	campfire.call("setup", "campfire", root.get_node("ContentDB").get_building("campfire"))
	await process_frame
	var glow := campfire.get_node_or_null("ContentGlow")
	if glow == null or not glow.visible: failures.append("Built campfire has no active glow")

	var door := DOOR_SCENE.instantiate()
	root.add_child(door)
	door.call("setup", "door", root.get_node("ContentDB").get_building("door"))
	door.call("set_open", true)
	if not bool(door.call("get_open")): failures.append("Door did not open")
	var collision := door.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not collision.disabled: failures.append("Open door collision remains enabled")
	door.call("set_open", false)
	if collision.disabled: failures.append("Closed door collision remains disabled")

	for scene in [SLIME_SCENE, SKELETON_SCENE]:
		var monster: Node = scene.instantiate()
		root.add_child(monster)
		await process_frame
		await process_frame
		var sprite := monster.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null or sprite.sprite_frames.get_animation_names().is_empty():
			failures.append("Monster content animation did not load")
		var locomotion := monster.get_node_or_null("MonsterLocomotion")
		var monster_data: Dictionary = root.get_node("ContentDB").get_monster(str(monster.get("monster_id")))
		var expected_speed := float((monster_data.get("locomotion", {}) as Dictionary).get("move_speed", monster_data.get("move_speed", 0.0)))
		if locomotion == null or not is_equal_approx(float(locomotion.get("move_speed")), expected_speed):
			failures.append("Monster runtime speed does not match ContentDB locomotion.move_speed")
		if not monster.has_method("get_attack_contact_frame") or int(monster.call("get_attack_contact_frame")) < 1:
			failures.append("Monster has no valid authored attack contact frame")
		_validate_monster_shadow_frame(monster, sprite)
		if str(monster.get("monster_id")) == "slime":
			_validate_slime_direction_rows(monster)
			_validate_offscreen_activation(monster, player)
		monster.queue_free()
	player.queue_free(); campfire.queue_free(); door.queue_free()
	await process_frame


func _validate_monster_shadow_frame(monster: Node, sprite: AnimatedSprite2D) -> void:
	var shadow := monster.get_node_or_null("GroundShadow") as Polygon2D
	if shadow == null or sprite == null:
		failures.append("Animated monster has no projected shadow source")
		return
	if int(shadow.get_meta("shadow_bound_source_id", 0)) != sprite.get_instance_id():
		failures.append("Animated monster shadow is not bound to its visible AnimatedSprite2D")
	var source_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if source_texture is AtlasTexture:
		if shadow.texture is AtlasTexture:
			failures.append("Animated monster shadow still samples the complete sprite atlas")
		if not bool(shadow.get_meta("shadow_source_frame_isolated", false)):
			failures.append("Animated monster frame was not isolated before shadow projection")
	if shadow.texture == null or shadow.texture.get_size().x <= 0.0 or shadow.texture.get_size().y <= 0.0:
		failures.append("Animated monster shadow has no valid active-frame texture")


func _validate_offscreen_activation(monster: Node, player: Node2D) -> void:
	monster.set("player", player)
	monster.set("facing_direction", "down")
	monster.global_position = Vector2(100000.0, 100000.0)
	var offscreen_motion := monster.call("_update_movement", 0.1) as Dictionary
	if (offscreen_motion.get("velocity", Vector2.ZERO) as Vector2).length() > 0.001:
		failures.append("Offscreen monster still chases the player across the map")
	monster.global_position = Vector2(180.0, 120.0)
	var onscreen_motion := monster.call("_update_movement", 0.1) as Dictionary
	if (onscreen_motion.get("velocity", Vector2.ZERO) as Vector2).length() <= 0.001:
		failures.append("Visible monster did not reactivate pursuit")


func _validate_slime_direction_rows(slime: Node) -> void:
	if not bool(slime.get_meta("slime_direction_rows_corrected", false)):
		failures.append("Slime runtime did not correct its direction rows")
		return
	var animation_value: Variant = slime.get("animations_data")
	if not (animation_value is Dictionary):
		failures.append("Slime runtime animation data is unavailable")
		return
	var animations := animation_value as Dictionary
	var expected_rows := {"down": 0, "up": 1, "left": 2, "right": 3}
	for state in ["idle", "walk", "run", "attack", "hurt", "death"]:
		for direction in expected_rows.keys():
			var animation_name := "%s_%s" % [state, direction]
			var definition_value: Variant = animations.get(animation_name, {})
			if not (definition_value is Dictionary):
				failures.append("Slime runtime is missing %s" % animation_name)
				continue
			if int((definition_value as Dictionary).get("row", -1)) != int(expected_rows[direction]):
				failures.append("Slime %s uses the wrong facing row" % animation_name)
