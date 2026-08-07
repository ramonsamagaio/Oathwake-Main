extends RefCounted
class_name AlabasterWeaponVisualRuntime

const MODE_ATTACK_ONLY := "attack_only"
const MODE_ALWAYS_WHEN_SUPPORTED := "always_when_supported"

var rig: Node2D
var weapon_sprite: Sprite2D
var item_id := ""
var weapon_data: Dictionary = {}
var visibility_mode := MODE_ATTACK_ONLY
var attacking := false
var _fallback_texture_cache: Dictionary = {}


func configure(target_rig: Node2D) -> void:
	dispose()
	rig = target_rig
	if rig == null:
		return
	weapon_sprite = Sprite2D.new()
	weapon_sprite.name = "AlabasterEquippedWeapon"
	weapon_sprite.centered = true
	weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon_sprite.z_as_relative = true
	weapon_sprite.z_index = 6
	weapon_sprite.visible = false
	rig.add_child(weapon_sprite)


func dispose() -> void:
	if weapon_sprite != null and is_instance_valid(weapon_sprite):
		weapon_sprite.queue_free()
	weapon_sprite = null
	rig = null
	item_id = ""
	weapon_data = {}
	attacking = false


func set_visibility_mode(mode: String) -> void:
	visibility_mode = MODE_ALWAYS_WHEN_SUPPORTED if mode == MODE_ALWAYS_WHEN_SUPPORTED else MODE_ATTACK_ONLY
	_update_visibility()


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	item_id = new_item_id
	weapon_data = {}
	var value: Variant = item_record.get("alabaster_weapon", {})
	if value is Dictionary:
		weapon_data = (value as Dictionary).duplicate(true)
	_refresh_texture(item_record)
	_update_visibility()


func set_attacking(value: bool) -> void:
	attacking = value
	_update_visibility()


func get_attack_animation() -> String:
	return str(weapon_data.get("attack_animation", "")).strip_edges()


func has_weapon() -> bool:
	return not item_id.is_empty() and not weapon_data.is_empty()


func supports_always_visible() -> bool:
	return bool(weapon_data.get("supports_always_visible", false))


func update() -> void:
	if rig == null or weapon_sprite == null or not has_weapon():
		return
	var use_rest := not attacking and visibility_mode == MODE_ALWAYS_WHEN_SUPPORTED and supports_always_visible()
	var socket := str(weapon_data.get("rest_socket" if use_rest else "socket", "weaponR"))
	if not rig.has_method("get_bone_screen_pose"):
		return
	var pose_variant: Variant = rig.call("get_bone_screen_pose", socket)
	if not pose_variant is Dictionary:
		return
	var pose: Dictionary = pose_variant
	if pose.is_empty():
		return
	weapon_sprite.position = pose.get("screen_position", Vector2.ZERO)
	weapon_sprite.rotation = float(pose.get("rotation", 0.0)) + deg_to_rad(_rotation_offset_degrees(use_rest))
	weapon_sprite.scale = Vector2.ONE * _visual_scale()
	weapon_sprite.z_index = -1 if use_rest else 6
	weapon_sprite.flip_h = false
	_update_visibility()


func _update_visibility() -> void:
	if weapon_sprite == null:
		return
	var visible_now := has_weapon() and attacking
	if not visible_now and visibility_mode == MODE_ALWAYS_WHEN_SUPPORTED and supports_always_visible():
		visible_now = true
	weapon_sprite.visible = visible_now


func _refresh_texture(item_record: Dictionary) -> void:
	if weapon_sprite == null:
		return
	var explicit_path := str(weapon_data.get("texture_path", item_record.get("alabaster_weapon_texture_path", ""))).strip_edges()
	if not explicit_path.is_empty() and ResourceLoader.exists(explicit_path):
		var resource := load(explicit_path)
		if resource is Texture2D:
			weapon_sprite.texture = resource as Texture2D
			return
	var kind := str(weapon_data.get("kind", "weapon"))
	weapon_sprite.texture = _fallback_texture(kind)


func _visual_scale() -> float:
	match str(weapon_data.get("kind", "")):
		"spear": return 1.0
		"hammer": return 1.0
		"crossbow": return 0.9
		"bomb": return 0.85
		_: return 1.0


func _rotation_offset_degrees(resting: bool) -> float:
	if resting:
		match str(weapon_data.get("kind", "")):
			"hammer": return -20.0
			"spear": return -12.0
			_: return 0.0
	match str(weapon_data.get("kind", "")):
		"sword": return 0.0
		"hammer": return 0.0
		"spear": return 0.0
		"tonfa": return 90.0
		"crossbow": return 90.0
		"chakram": return 0.0
		"kama": return 15.0
		"bomb": return 0.0
		_: return 0.0


func _fallback_texture(kind: String) -> Texture2D:
	if _fallback_texture_cache.has(kind):
		return _fallback_texture_cache[kind]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var dark := Color("#302A36")
	var metal := Color("#C8CDD7")
	var light := Color("#F1E3BF")
	var accent := Color("#9B6B54")
	match kind:
		"sword":
			_draw_line(image, Vector2i(7, 25), Vector2i(23, 7), 2, metal)
			_draw_line(image, Vector2i(10, 23), Vector2i(7, 26), 3, accent)
			_draw_line(image, Vector2i(8, 21), Vector2i(13, 26), 1, light)
		"hammer":
			_draw_line(image, Vector2i(15, 27), Vector2i(17, 9), 3, accent)
			_fill_rect(image, Rect2i(8, 5, 17, 8), dark)
			_fill_rect(image, Rect2i(10, 6, 13, 5), metal)
		"spear":
			_draw_line(image, Vector2i(5, 27), Vector2i(25, 7), 2, accent)
			_fill_rect(image, Rect2i(23, 4, 4, 7), metal)
		"tonfa":
			_draw_line(image, Vector2i(8, 22), Vector2i(24, 14), 3, dark)
			_draw_line(image, Vector2i(15, 18), Vector2i(13, 10), 2, accent)
		"crossbow":
			_draw_line(image, Vector2i(6, 16), Vector2i(26, 16), 2, accent)
			_draw_line(image, Vector2i(10, 10), Vector2i(22, 22), 1, metal)
			_draw_line(image, Vector2i(22, 10), Vector2i(10, 22), 1, metal)
		"chakram":
			_draw_ring(image, Vector2i(16, 16), 9, 6, metal)
		"kama":
			_draw_line(image, Vector2i(14, 27), Vector2i(16, 12), 2, accent)
			_draw_arc_pixels(image, Vector2i(17, 12), 8, metal)
		"bomb":
			_draw_ring(image, Vector2i(16, 18), 8, 0, dark)
			_fill_rect(image, Rect2i(14, 7, 4, 5), accent)
			_draw_line(image, Vector2i(17, 7), Vector2i(21, 4), 1, light)
		_:
			_fill_rect(image, Rect2i(12, 6, 8, 20), metal)
	var texture := ImageTexture.create_from_image(image)
	_fallback_texture_cache[kind] = texture
	return texture


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, image.get_height())):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, image.get_width())):
			image.set_pixel(x, y, color)


func _draw_line(image: Image, from: Vector2i, to: Vector2i, width: int, color: Color) -> void:
	var delta := to - from
	var steps := maxi(abs(delta.x), abs(delta.y))
	if steps <= 0:
		_fill_rect(image, Rect2i(from - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)
		return
	for i in range(steps + 1):
		var p := Vector2(from).lerp(Vector2(to), float(i) / float(steps))
		_fill_rect(image, Rect2i(Vector2i(roundi(p.x), roundi(p.y)) - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)


func _draw_ring(image: Image, center: Vector2i, outer_radius: int, inner_radius: int, color: Color) -> void:
	for y in range(center.y - outer_radius, center.y + outer_radius + 1):
		for x in range(center.x - outer_radius, center.x + outer_radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var d := Vector2(x - center.x, y - center.y).length()
			if d <= outer_radius and (inner_radius <= 0 or d >= inner_radius):
				image.set_pixel(x, y, color)


func _draw_arc_pixels(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for degree in range(-90, 55, 8):
		var angle := deg_to_rad(float(degree))
		var p := center + Vector2i(roundi(cos(angle) * radius), roundi(sin(angle) * radius))
		_fill_rect(image, Rect2i(p, Vector2i(2, 2)), color)
