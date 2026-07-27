extends RefCounted

const HitImpactScene := preload("res://scenes/effects/HitImpact.tscn")
const FloatingCombatTextScene := preload("res://scenes/ui/FloatingCombatText.tscn")


static func show_damage(amount: int, world_position: Vector2, is_critical := false, target_type := "enemy") -> void:
	if amount <= 0:
		return

	var color := Color(1.0, 0.95, 0.65, 1.0)
	var text := str(amount)
	if target_type == "player":
		color = Color(1.0, 0.35, 0.35, 1.0)
	elif is_critical:
		color = Color(1.0, 0.62, 0.12, 1.0)
		text = "CRIT %d" % amount

	var profile_id := "critical_damage_number" if is_critical else "damage_number"
	_spawn(text, world_position, color, is_critical, profile_id)
	_request_hit_screen_shake(is_critical)


static func show_miss(world_position: Vector2) -> void:
	_spawn("Miss", world_position, Color(0.72, 0.72, 0.72, 1.0), false, "miss_text")


static func show_heal(amount: int, world_position: Vector2) -> void:
	if amount <= 0:
		return
	_spawn("+%d" % amount, world_position, Color(0.45, 1.0, 0.55, 1.0), false, "heal_number")


static func show_text(text: String, world_position: Vector2, color := Color(0.72, 0.72, 0.72, 1.0), is_critical := false, profile_id := "console") -> void:
	if text.is_empty():
		return
	_spawn(text, world_position, color, is_critical, profile_id)


static func show_hit_impact(world_position: Vector2, is_critical := false) -> void:
	_spawn_hit_impact(world_position, is_critical)
	_spawn_pixel_hit_sparks(world_position, is_critical)


static func show_xp(amount: int, world_position: Vector2) -> void:
	if amount <= 0:
		return
	_spawn("+XP %d" % amount, world_position, Color(0.55, 0.9, 1.0, 1.0), false, "xp_number")


static func _spawn(text: String, world_position: Vector2, color: Color, is_critical: bool, profile_id := "") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var floating_text := FloatingCombatTextScene.instantiate()
	floating_text.top_level = true
	floating_text.z_as_relative = false
	floating_text.z_index = 4090
	floating_text.configure_spawn(text, color, is_critical, profile_id, world_position)
	tree.current_scene.add_child(floating_text)


static func _spawn_hit_impact(world_position: Vector2, is_critical: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var hit_impact := HitImpactScene.instantiate()
	hit_impact.top_level = true
	hit_impact.z_as_relative = false
	hit_impact.z_index = 4088
	tree.current_scene.add_child(hit_impact)
	hit_impact.global_position = world_position
	if hit_impact.has_method("setup"):
		hit_impact.call("setup", is_critical)


static func _spawn_pixel_hit_sparks(world_position: Vector2, is_critical: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var pixel_vfx := tree.root.get_node_or_null("PixelVFX")
	if pixel_vfx != null and pixel_vfx.has_method("spawn_world_hit_sparks"):
		pixel_vfx.call("spawn_world_hit_sparks", world_position, is_critical)


static func _request_hit_screen_shake(is_critical: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var camera := tree.get_first_node_in_group("game_camera")
	if camera != null and camera.has_method("request_hit_shake"):
		camera.call("request_hit_shake", is_critical)
		return
	if tree.current_scene != null:
		var fallback_camera := tree.current_scene.find_child("Camera2D", true, false)
		if fallback_camera != null and fallback_camera.has_method("request_hit_shake"):
			fallback_camera.call("request_hit_shake", is_critical)
