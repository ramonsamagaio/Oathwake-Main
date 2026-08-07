extends Node2D

const RigRuntime := preload("res://scripts/labs/alabaster/AlabasterRigRuntime.gd")

const SCREEN_SIZE := Vector2(1600.0, 900.0)
const WALK_SPEED := 150.0
const RUN_SPEED := 240.0

var player: CharacterBody2D
var rig
var status_label: Label
var _debug_enabled := false


func _ready() -> void:
	_build_world()
	_build_player()
	_build_ui()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var running := Input.is_key_pressed(KEY_SHIFT)
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		player.velocity = input_dir * (RUN_SPEED if running else WALK_SPEED)
		player.move_and_slide()
		player.position.x = clampf(player.position.x, 72.0, SCREEN_SIZE.x - 72.0)
		player.position.y = clampf(player.position.y, 92.0, SCREEN_SIZE.y - 72.0)
		rig.set_facing_from_vector(input_dir)
		rig.set_animation("run" if running else "walk")
	else:
		player.velocity = Vector2.ZERO
		rig.set_animation("idle")
	_update_status()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_debug_enabled = not _debug_enabled
		rig.set_debug_enabled(_debug_enabled)
		_update_status()


func _build_world() -> void:
	var floor := ColorRect.new()
	floor.name = "Floor"
	floor.position = Vector2.ZERO
	floor.size = SCREEN_SIZE
	floor.color = Color("#11141b")
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.z_index = -1000
	add_child(floor)


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "AlabasterPlayer"
	player.position = SCREEN_SIZE * 0.5 + Vector2(0.0, 80.0)
	add_child(player)

	rig = RigRuntime.new()
	rig.name = "JunoRig"
	rig.scale = Vector2(2.5, 2.5)
	player.add_child(rig)


func _build_ui() -> void:
	var title := Label.new()
	title.position = Vector2(28.0, 24.0)
	title.text = "ALABASTER MECHANIC LAB"
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	var help := Label.new()
	help.position = Vector2(28.0, 58.0)
	help.text = "WASD mover  •  SHIFT correr  •  F1 mostrar skeleton  •  cena isolada do jogo"
	help.add_theme_font_size_override("font_size", 16)
	help.modulate = Color(0.82, 0.86, 0.94)
	add_child(help)

	status_label = Label.new()
	status_label.position = Vector2(28.0, 86.0)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.modulate = Color(0.60, 0.94, 0.80)
	add_child(status_label)
	_update_status()


func _update_status() -> void:
	if rig == null or status_label == null:
		return
	# `rig` is intentionally dynamic because it is instantiated from a preloaded script.
	# Do not use `:=` here: Godot cannot statically infer the return type of a method
	# called through a Variant, which was preventing this scene from parsing.
	var summary = rig.get_runtime_summary()
	status_label.text = "anim=%s   facing16=%02d   angle=%6.1f°   nodes=%d   sprite pieces=%d   debug=%s" % [
		String(summary.get("animation", "")),
		int(summary.get("facing_index_16", 0)),
		float(summary.get("facing_degrees", 0.0)),
		int(summary.get("node_count", 0)),
		int(summary.get("sprite_piece_count", 0)),
		"ON" if _debug_enabled else "OFF",
	]


func _draw() -> void:
	for x in range(0, int(SCREEN_SIZE.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_SIZE.y), Color(0.18, 0.21, 0.28, 0.55), 1.0)
	for y in range(0, int(SCREEN_SIZE.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(SCREEN_SIZE.x, y), Color(0.18, 0.21, 0.28, 0.55), 1.0)
	draw_line(Vector2(0, SCREEN_SIZE.y * 0.5), Vector2(SCREEN_SIZE.x, SCREEN_SIZE.y * 0.5), Color(0.28, 0.33, 0.42, 0.65), 1.0)
	draw_line(Vector2(SCREEN_SIZE.x * 0.5, 0), Vector2(SCREEN_SIZE.x * 0.5, SCREEN_SIZE.y), Color(0.28, 0.33, 0.42, 0.65), 1.0)
