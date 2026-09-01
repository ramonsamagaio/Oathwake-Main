extends StaticBody2D

const BuildingPlaceholderVisualScript = preload("res://scripts/buildings/BuildingPlaceholderVisual.gd")

@export var building_id: String = "wall"
@export var display_name: String = ""
@export var interaction_range: float = 56.0

var building_data := {}
var workstation_id := ""
var content_sprite: Sprite2D
var fallback_visual: Node2D
var collision_shape: CollisionShape2D


func _ready() -> void:
	add_to_group("building")
	_load_building_data()
	_apply_groups()
	_apply_visuals()
	_apply_collision()
	_connect_content_reload()


func setup(new_building_id: String, new_data: Dictionary = {}) -> void:
	building_id = new_building_id
	building_data = new_data.duplicate(true)
	if is_inside_tree():
		_apply_groups()
		_apply_visuals()
		_apply_collision()


func get_building_id() -> String:
	return building_id


func set_building_id(new_building_id: String) -> void:
	building_id = new_building_id
	_load_building_data()
	_apply_groups()
	_apply_visuals()
	_apply_collision()


func get_display_name() -> String:
	return display_name


func set_display_name(new_display_name: String) -> void:
	display_name = new_display_name


func get_workstation_id() -> String:
	return workstation_id


func try_interact_with_player(player: Node2D) -> bool:
	if player == null or workstation_id.is_empty():
		return false
	if global_position.distance_to(player.global_position) > interaction_range:
		return false

	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	if crafting_system != null and crafting_system.has_method("try_open_workstation"):
		return bool(crafting_system.try_open_workstation(workstation_id, self))

	return false


func _load_building_data() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_building") and content_db.has_building(building_id):
		building_data = content_db.get_building(building_id)

	display_name = str(building_data.get("display_name", building_id.capitalize()))
	workstation_id = str(building_data.get("workstation_id", ""))


func _apply_groups() -> void:
	if not is_in_group("building"):
		add_to_group("building")
	if not workstation_id.is_empty() and not is_in_group("workstation"):
		add_to_group("workstation")


func _apply_visuals() -> void:
	var sprite_id := str(building_data.get("sprite_id", ""))
	if sprite_id.is_empty():
		_apply_fallback_visual()
		return

	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_sprite") or not content_db.has_sprite(sprite_id):
		_apply_fallback_visual()
		return

	var sprite_data: Dictionary = content_db.get_sprite(sprite_id)
	var texture_path := str(sprite_data.get("texture_path", ""))
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		_apply_fallback_visual()
		return

	var texture = load(texture_path)
	if not texture is Texture2D:
		_apply_fallback_visual()
		return

	if content_sprite == null:
		content_sprite = get_node_or_null("ContentSprite") as Sprite2D
	if content_sprite == null:
		content_sprite = Sprite2D.new()
		content_sprite.name = "ContentSprite"
		add_child(content_sprite)
		move_child(content_sprite, 0)

	content_sprite.texture = texture
	content_sprite.centered = true
	content_sprite.visible = true
	_apply_sprite_region(content_sprite, sprite_data)
	_apply_sprite_anchor(content_sprite, sprite_data)
	if fallback_visual != null:
		fallback_visual.visible = false


func _apply_fallback_visual() -> void:
	if content_sprite != null:
		content_sprite.visible = false
	if fallback_visual == null:
		fallback_visual = get_node_or_null("FallbackVisual") as Node2D
	if fallback_visual == null:
		fallback_visual = BuildingPlaceholderVisualScript.new()
		fallback_visual.name = "FallbackVisual"
		add_child(fallback_visual)
		move_child(fallback_visual, 0)

	if fallback_visual.has_method("configure"):
		fallback_visual.call("configure", building_id, building_data)
	fallback_visual.visible = true


func _apply_collision() -> void:
	var collision = building_data.get("collision", {})
	var enabled := true
	var size := Vector2(28, 24)
	var offset := Vector2.ZERO
	if collision is Dictionary:
		enabled = bool(collision.get("enabled", true))
		var size_data = collision.get("size", {})
		if size_data is Dictionary:
			size = Vector2(
				float(size_data.get("w", size.x)),
				float(size_data.get("h", size.y))
			)
		var offset_data = collision.get("offset", {})
		if offset_data is Dictionary:
			offset = Vector2(
				float(offset_data.get("x", 0.0)),
				float(offset_data.get("y", 0.0))
			)

	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		add_child(collision_shape)

	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision_shape.shape = rectangle
	collision_shape.position = offset
	collision_shape.disabled = not enabled


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "_on_content_reloaded")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _on_content_reloaded() -> void:
	_load_building_data()
	_apply_visuals()
	_apply_collision()


func _apply_sprite_region(sprite: Sprite2D, sprite_data: Dictionary) -> void:
	sprite.region_enabled = bool(sprite_data.get("region_enabled", false))
	if not sprite.region_enabled:
		return

	var region = sprite_data.get("region", {})
	if not region is Dictionary:
		return

	sprite.region_rect = Rect2(
		float(region.get("x", 0.0)),
		float(region.get("y", 0.0)),
		float(region.get("w", 32.0)),
		float(region.get("h", 32.0))
	)


func _apply_sprite_anchor(sprite: Sprite2D, sprite_data: Dictionary) -> void:
	var visual_size := _get_sprite_visual_size(sprite, sprite_data)
	var anchor = sprite_data.get("anchor", {})
	var anchor_position := Vector2(visual_size.x * 0.5, visual_size.y)
	if anchor is Dictionary:
		anchor_position = Vector2(
			float(anchor.get("x", anchor_position.x)),
			float(anchor.get("y", anchor_position.y))
		)

	sprite.offset = Vector2(
		(visual_size.x * 0.5) - anchor_position.x,
		(visual_size.y * 0.5) - anchor_position.y
	)


func _get_sprite_visual_size(sprite: Sprite2D, sprite_data: Dictionary) -> Vector2:
	if sprite.region_enabled:
		return sprite.region_rect.size
	var frame_size = sprite_data.get("frame_size", {})
	if frame_size is Dictionary:
		return Vector2(
			float(frame_size.get("w", sprite.texture.get_width())),
			float(frame_size.get("h", sprite.texture.get_height()))
		)
	if sprite.texture != null:
		return sprite.texture.get_size()
	return Vector2(32, 32)
