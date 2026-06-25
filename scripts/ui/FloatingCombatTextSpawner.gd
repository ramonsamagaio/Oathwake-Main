extends RefCounted

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

	_spawn(text, world_position, color, is_critical)


static func show_miss(world_position: Vector2) -> void:
	_spawn("Miss", world_position, Color(0.72, 0.72, 0.72, 1.0), false)


static func show_heal(amount: int, world_position: Vector2) -> void:
	if amount <= 0:
		return

	_spawn("+%d" % amount, world_position, Color(0.45, 1.0, 0.55, 1.0), false)


static func show_text(text: String, world_position: Vector2, color := Color(0.72, 0.72, 0.72, 1.0), is_critical := false) -> void:
	if text.is_empty():
		return

	_spawn(text, world_position, color, is_critical)


static func _spawn(text: String, world_position: Vector2, color: Color, is_critical: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var floating_text := FloatingCombatTextScene.instantiate()
	tree.current_scene.add_child(floating_text)
	floating_text.global_position = world_position
	floating_text.setup(text, color, is_critical)
