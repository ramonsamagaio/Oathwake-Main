class_name CampfireLivePreview
extends SubViewportContainer

const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")

var _viewport: SubViewport
var _world_root: Node2D
var _building: Node
var _pending_data: Dictionary = {}
var _night_strength := 0.65


func _ready() -> void:
	custom_minimum_size = Vector2(360.0, 260.0)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.name = "CampfirePreviewViewport"
	_viewport.size = Vector2i(360, 260)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_viewport)

	var background := ColorRect.new()
	background.name = "PreviewBackground"
	background.position = Vector2.ZERO
	background.size = Vector2(360.0, 260.0)
	background.color = Color(0.045, 0.052, 0.045, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(background)

	var ground := Polygon2D.new()
	ground.name = "PreviewGround"
	ground.polygon = PackedVector2Array([
		Vector2(0.0, 150.0),
		Vector2(360.0, 150.0),
		Vector2(360.0, 260.0),
		Vector2(0.0, 260.0),
	])
	ground.color = Color(0.11, 0.125, 0.09, 1.0)
	_viewport.add_child(ground)

	_world_root = Node2D.new()
	_world_root.name = "PreviewWorld"
	_world_root.position = Vector2(180.0, 184.0)
	_world_root.scale = Vector2(4.0, 4.0)
	_viewport.add_child(_world_root)

	_building = BUILDING_SCENE.instantiate()
	_building.name = "CampfirePreviewBuilding"
	_world_root.add_child(_building)
	_apply_pending_data()


func set_building_data(data: Dictionary) -> void:
	_pending_data = data.duplicate(true)
	_apply_pending_data()


func set_night_strength(value: float) -> void:
	_night_strength = clampf(value, 0.0, 1.0)
	_apply_night_strength()


func _apply_pending_data() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	var preview_data := _pending_data.duplicate(true)
	preview_data["id"] = "campfire"
	preview_data["sprite_id"] = str(preview_data.get("sprite_id", "campfire"))
	if _building.has_method("setup"):
		_building.call("setup", "campfire", preview_data)
	call_deferred("_apply_night_strength")


func _apply_night_strength() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	var glow := _building.get_node_or_null("ContentGlow")
	if glow != null and glow.has_method("set_day_night_strength"):
		glow.call("set_day_night_strength", _night_strength)
