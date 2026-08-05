extends Node

const LAB_SCENE_PATH := "res://scenes/labs/TerrainAuthoringLab.tscn"
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const PLAYER_NODE_NAME := "AuthoringLabPlayer"
const DEFAULT_SPAWN_POSITION := Vector2.ZERO
const PLAYTEST_CAMERA_ZOOM := Vector2(1.15, 1.15)


func _ready() -> void:
	var tree := get_tree()
	var callback := Callable(self, "_on_current_scene_changed")
	if not tree.current_scene_changed.is_connected(callback):
		tree.current_scene_changed.connect(callback)
	call_deferred("_inject_current_scene")


func _on_current_scene_changed(scene: Node) -> void:
	call_deferred("_inject_into_scene", scene)


func _inject_current_scene() -> void:
	_inject_into_scene(get_tree().current_scene)


func _inject_into_scene(scene: Node) -> void:
	if not _is_authoring_lab_scene(scene):
		return
	_ensure_player(scene)


func _is_authoring_lab_scene(scene: Node) -> bool:
	if scene == null:
		return false
	if scene.scene_file_path == LAB_SCENE_PATH:
		return true
	# Scene-file paths can be empty in isolated smoke tests. Keep the runtime
	# fallback strict enough that another scene cannot accidentally receive a player.
	return String(scene.name) == "TerrainAuthoringLab" and scene.has_node("AuthoredGrassDirtTerrain")


func ensure_player_for_test(scene: Node) -> Node:
	return _ensure_player(scene)


func _ensure_player(scene: Node) -> Node:
	if scene == null:
		return null
	var existing := scene.get_node_or_null(PLAYER_NODE_NAME)
	if existing != null:
		return existing
	var player := PLAYER_SCENE.instantiate()
	player.name = PLAYER_NODE_NAME
	player.position = DEFAULT_SPAWN_POSITION
	player.set_meta("authoring_lab_playtest_player", true)
	scene.add_child(player)
	_configure_playtest_camera(player)
	_install_playtest_instructions(scene)
	return player


func _configure_playtest_camera(player: Node) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.enabled = true
	camera.zoom = PLAYTEST_CAMERA_ZOOM
	camera.position_smoothing_enabled = false
	camera.make_current()
	camera.set_meta("authoring_lab_playtest_camera", true)


func _install_playtest_instructions(scene: Node) -> void:
	var instructions := scene.get_node_or_null("Instructions")
	if instructions == null or instructions.has_node("PlaytestHelp"):
		return
	var label := Label.new()
	label.name = "PlaytestHelp"
	label.position = Vector2(20.0, 48.0)
	label.text = "PLAYTEST DO MAPA  |  WASD / SETAS para andar  |  Shift para correr  |  roda do mouse para zoom"
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1.0, 0.94, 0.78, 0.92)
	instructions.add_child(label)
