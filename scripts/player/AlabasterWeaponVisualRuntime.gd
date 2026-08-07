extends RefCounted
class_name AlabasterWeaponVisualRuntime

const SourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")
const MODE_ATTACK_ONLY := "attack_only"
const MODE_ALWAYS_WHEN_SUPPORTED := "always_when_supported"

var rig: Node2D
var visual_root: Node2D
var fallback_sprite: Sprite2D
var item_id := ""
var weapon_data: Dictionary = {}
var visibility_mode := MODE_ATTACK_ONLY
var attacking := false
var _source_payload: Dictionary = {}
var _source_records: Array[Dictionary] = []
var _active_source_figure := ""
var _fallback_texture_cache: Dictionary = {}


func configure(target_rig: Node2D) -> void:
	dispose()
	rig = target_rig
	if rig == null:
		return
	visual_root = Node2D.new()
	visual_root.name = "AlabasterEquippedWeaponFigure"
	visual_root.z_as_relative = true
	rig.add_child(visual_root)
	fallback_sprite = Sprite2D.new()
	fallback_sprite.name = "FallbackWeapon"
	fallback_sprite.centered = true
	fallback_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fallback_sprite.z_as_relative = true
	fallback_sprite.z_index = 6
	fallback_sprite.visible = false
	visual_root.add_child(fallback_sprite)
	_source_payload = SourceAssets.load_player_weapon_source()


func dispose() -> void:
	_clear_source_records()
	if visual_root != null and is_instance_valid(visual_root):
		visual_root.queue_free()
	visual_root = null
	fallback_sprite = null
	rig = null
	item_id = ""
	weapon_data = {}
	attacking = false
	_source_payload = {}
	_active_source_figure = ""


func set_visibility_mode(mode: String) -> void:
	visibility_mode = MODE_ALWAYS_WHEN_SUPPORTED if mode == MODE_ALWAYS_WHEN_SUPPORTED else MODE_ATTACK_ONLY
	_update_visibility()


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	item_id = new_item_id
	weapon_data = {}
	var value: Variant = item_record.get("alabaster_weapon", {})
	if value is Dictionary:
		weapon_data = (value as Dictionary).duplicate(true)
	_active_source_figure = ""
	_clear_source_records()
	_refresh_fallback_texture(item_record)
	_update_visibility()


func set_attacking(value: bool) -> void:
	if attacking == value:
		return
	attacking = value
	_active_source_figure = ""
	_update_visibility()


func get_attack_animation() -> String:
	return str(weapon_data.get("attack_animation", "")).strip_edges()


func has_weapon() -> bool:
	return not item_id.is_empty() and not weapon_data.is_empty()


func supports_always_visible() -> bool:
	return bool(weapon_data.get("supports_always_visible", false))


func update() -> void:
	if rig == null or visual_root == null or not has_weapon():
		_update_visibility()
		return
	var visible_now := _should_be_visible()
	if not visible_now:
		_update_visibility()
		return
	var use_rest := _use_rest_figure()
	var source_figure := str(weapon_data.get("rest_source_figure" if use_rest else "source_figure", "")).strip_edges()
	if not source_figure.is_empty() and _has_source_figure(source_figure):
		if source_figure != _active_source_figure:
			_build_source_figure(source_figure)
		_update_source_figure(use_rest)
		if fallback_sprite != null:
			fallback_sprite.visible = false
	else:
		_update_fallback(use_rest)
	_update_visibility()


func _should_be_visible() -> bool:
	if not has_weapon():
		return false
	if attacking:
		return true
	return visibility_mode == MODE_ALWAYS_WHEN_SUPPORTED and supports_always_visible()


func _use_rest_figure() -> bool:
	return not attacking and visibility_mode == MODE_ALWAYS_WHEN_SUPPORTED and supports_always_visible()


func _has_source_figure(figure_name: String) -> bool:
	var figures_value: Variant = _source_payload.get("figures", {})
	return figures_value is Dictionary and (figures_value as Dictionary).has(figure_name)


func _build_source_figure(figure_name: String) -> void:
	_clear_source_records()
	_active_source_figure = figure_name
	var figures: Dictionary = _source_payload.get("figures", {})
	var figure_value: Variant = figures.get(figure_name, {})
	if not figure_value is Dictionary:
		return
	var figure: Dictionary = figure_value
	var nodes_value: Variant = figure.get("nodes", {})
	if not nodes_value is Dictionary:
		return
	var nodes: Dictionary = nodes_value
	var half_shift := bool(figure.get("halfPixelShift", false))
	var figure_global_z := int(figure.get("globalZOrder", 0))
	for node_name_value in nodes.keys():
		var source_node := str(node_name_value)
		var node_value: Variant = nodes[source_node]
		if not node_value is Dictionary:
			continue
		var gfx_value: Variant = (node_value as Dictionary).get("gfx", [])
		if not gfx_value is Array:
			continue
		for gfx_value_item in gfx_value as Array:
			if not gfx_value_item is Dictionary:
				continue
			var gfx: Dictionary = (gfx_value_item as Dictionary).duplicate(true)
			if bool(gfx.get("hidden", false)):
				continue
			var sprite := Sprite2D.new()
			sprite.name = "Weapon_%s_%d" % [source_node, _source_records.size()]
			sprite.centered = false
			sprite.region_enabled = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_as_relative = true
			sprite.visible = false
			visual_root.add_child(sprite)
			_source_records.append({
				"source_node": source_node,
				"gfx": gfx,
				"sprite": sprite,
				"half_shift": half_shift,
				"figure_global_z": figure_global_z,
			})


func _clear_source_records() -> void:
	for record in _source_records:
		var sprite: Sprite2D = record.get("sprite") as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_source_records.clear()


func _update_source_figure(resting: bool) -> void:
	var any_visible := false
	for record in _source_records:
		var source_node := str(record.get("source_node", "weaponR"))
		var target_node := _target_node_for_source(source_node, resting)
		var state := _get_target_state(target_node)
		var sprite: Sprite2D = record.get("sprite") as Sprite2D
		if sprite == null:
			continue
		if state.is_empty():
			sprite.visible = false
			continue
		var gfx: Dictionary = record.get("gfx", {})
		var resolved := _resolve_gfx_visual(gfx, state)
		if resolved.is_empty():
			sprite.visible = false
			continue
		var texture: Texture2D = resolved.get("texture") as Texture2D
		if texture == null:
			sprite.visible = false
			continue
		sprite.texture = texture
		sprite.region_rect = resolved.get("region", Rect2())
		sprite.offset = -resolved.get("pivot", Vector2.ZERO)
		sprite.flip_h = bool(resolved.get("flip_h", false))
		sprite.flip_v = bool(resolved.get("flip_v", false))
		sprite.position = _gfx_screen_position(gfx, state)
		sprite.rotation = _gfx_screen_rotation(resolved, state)
		sprite.scale = Vector2.ONE
		var billboard: Dictionary = resolved.get("billboard", {})
		var logical_z := int(record.get("figure_global_z", 0)) + int(billboard.get("zOrder", 0))
		if resting:
			logical_z -= 8
		sprite.z_index = clampi(logical_z, -32, 32)
		sprite.visible = _should_be_visible()
		any_visible = any_visible or sprite.visible
	if fallback_sprite != null:
		fallback_sprite.visible = _should_be_visible() and not any_visible


func _target_node_for_source(source_node: String, resting: bool) -> String:
	if resting:
		return str(weapon_data.get("rest_socket", "weaponBelt"))
	if source_node == "weaponL" or source_node == "rootL":
		return str(weapon_data.get("secondary_socket", "weaponL"))
	if source_node == "fingerR" or source_node == "handR":
		return source_node
	return str(weapon_data.get("socket", "weaponR"))


func _get_target_state(target_node: String) -> Dictionary:
	if rig.has_method("get_bone_visual_state"):
		var result: Variant = rig.call("get_bone_visual_state", target_node)
		if result is Dictionary:
			return result as Dictionary
	if rig.has_method("get_bone_screen_pose"):
		var pose: Variant = rig.call("get_bone_screen_pose", target_node)
		if pose is Dictionary:
			var fallback: Dictionary = (pose as Dictionary).duplicate(true)
			fallback["frame_key"] = 0
			fallback["pitch"] = 4
			fallback["facing_yaw"] = 0.0
			fallback["yaw_flipped"] = false
			return fallback
	return {}


func _resolve_gfx_visual(gfx: Dictionary, state: Dictionary) -> Dictionary:
	var tex_value: Variant = gfx.get("tex", {})
	if not tex_value is Dictionary:
		return {}
	var tex: Dictionary = tex_value
	var selected := {}
	if tex.has("simple"):
		var simple_value: Variant = tex.get("simple", {})
		if not simple_value is Dictionary:
			return {}
		var simple: Dictionary = simple_value
		selected = {"entry": simple, "row": {"refAngles": [0], "texRotate": "NONE"}, "row_index": 0, "tile_idx": 0, "flip_h": bool(simple.get("flipX", false)), "flip_v": bool(simple.get("flipY", false))}
	elif tex.has("multi"):
		var multi_value: Variant = tex.get("multi", {})
		if not multi_value is Dictionary:
			return {}
		var entries_value: Variant = (multi_value as Dictionary).get("entries", {})
		if not entries_value is Dictionary:
			return {}
		var entries: Dictionary = entries_value
		var frame_key := int(state.get("frame_key", 0))
		var pitch := int(state.get("pitch", 4))
		var row_match := {}
		if rig.has_method("resolve_external_texture_row"):
			var row_value: Variant = rig.call("resolve_external_texture_row", entries, frame_key, pitch)
			if row_value is Dictionary:
				row_match = row_value as Dictionary
		if row_match.is_empty():
			row_match = _fallback_texture_row(entries, frame_key)
		if row_match.is_empty():
			return {}
		var entry: Dictionary = row_match.get("entry", {})
		var facing_mode := str(entry.get("facing", "FACE_1"))
		var flip_ref := bool(state.get("yaw_flipped", false)) and bool(entry.get("flipRoll", false))
		var facing := {"tile_idx": 0, "flip_h": false}
		if rig.has_method("resolve_external_facing"):
			var facing_value: Variant = rig.call("resolve_external_facing", facing_mode, float(state.get("facing_yaw", 0.0)), flip_ref)
			if facing_value is Dictionary:
				facing = facing_value as Dictionary
		selected = row_match.duplicate(true)
		selected["tile_idx"] = int(facing.get("tile_idx", 0))
		selected["flip_h"] = bool(facing.get("flip_h", false))
		selected["flip_v"] = false
	else:
		return {}

	var entry: Dictionary = selected.get("entry", {})
	var sheet_name := str(entry.get("sheet", ""))
	var texture := SourceAssets.load_player_weapon_sheet(sheet_name)
	if texture == null:
		return {}
	var range_value: Variant = entry.get("range", [])
	if not range_value is Array or (range_value as Array).size() < 4:
		return {}
	var range: Array = range_value
	var tile_w := int(range[2])
	var tile_h := int(range[3])
	var row_index := int(selected.get("row_index", 0))
	var tile_idx := int(selected.get("tile_idx", 0)) + int(entry.get("flipShift", 0))
	var src_x := int(range[0]) + tile_idx * tile_w
	var src_y := int(range[1]) + row_index * tile_h
	var region := Rect2(src_x, src_y, tile_w, tile_h)
	var shape_value: Variant = gfx.get("shape", {})
	var billboard := {}
	if shape_value is Dictionary:
		var billboard_value: Variant = (shape_value as Dictionary).get("billboard", {})
		if billboard_value is Dictionary:
			billboard = billboard_value as Dictionary
	var pivot := Vector2(float(billboard.get("pivotX", 0.5)) * tile_w, float(billboard.get("pivotY", 0.5)) * tile_h)
	if bool(selected.get("flip_h", false)):
		pivot.x = tile_w - pivot.x
	return {
		"texture": texture,
		"region": region,
		"pivot": pivot,
		"flip_h": bool(selected.get("flip_h", false)),
		"flip_v": bool(selected.get("flip_v", false)),
		"row": selected.get("row", {}),
		"tile_idx": tile_idx,
		"billboard": billboard,
	}


func _fallback_texture_row(entries: Dictionary, frame_key: int) -> Dictionary:
	var fallback_name := "default"
	for entry_name_value in entries.keys():
		var entry_name := str(entry_name_value)
		var entry_value: Variant = entries[entry_name]
		if not entry_value is Dictionary:
			continue
		var rows_value: Variant = (entry_value as Dictionary).get("rows", [])
		if not rows_value is Array:
			continue
		var rows: Array = rows_value
		for row_index in range(rows.size()):
			var row_value: Variant = rows[row_index]
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			var keys_value: Variant = row.get("frameKeys", [])
			var keys: Array = keys_value as Array if keys_value is Array else []
			if (frame_key == 0 and keys.is_empty()) or keys.has(frame_key):
				return {"entry": entry_value as Dictionary, "row": row, "row_index": row_index}
	if entries.has(fallback_name):
		var default_entry: Dictionary = entries[fallback_name]
		var default_rows: Array = default_entry.get("rows", [])
		if not default_rows.is_empty() and default_rows[0] is Dictionary:
			return {"entry": default_entry, "row": default_rows[0], "row_index": 0}
	return {}


func _gfx_screen_position(gfx: Dictionary, state: Dictionary) -> Vector2:
	var base_screen: Vector2 = state.get("screen_position", Vector2.ZERO)
	var pos_value: Variant = gfx.get("pos", [])
	if not pos_value is Array or (pos_value as Array).size() < 3:
		return base_screen
	if rig.has_method("project_external_world") and state.has("g_self") and state.has("g_rot"):
		var pos: Array = pos_value
		var local := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var rotation: Quaternion = state.get("g_rot", Quaternion.IDENTITY)
		var scale_value: Variant = state.get("g_scale", 1.0)
		var scale := float(scale_value) if scale_value is float or scale_value is int else 1.0
		var world: Vector3 = state.get("g_self", Vector3.ZERO) + rotation * (local * scale)
		var projected: Variant = rig.call("project_external_world", world)
		if projected is Vector2:
			return projected as Vector2
	return base_screen


func _gfx_screen_rotation(resolved: Dictionary, state: Dictionary) -> float:
	var row: Dictionary = resolved.get("row", {})
	var mode := str(row.get("texRotate", "NONE"))
	if mode == "NONE":
		return 0.0
	var angle := float(state.get("screen_rotation", 0.0))
	var refs_value: Variant = row.get("refAngles", [])
	if refs_value is Array:
		var refs: Array = refs_value
		var tile_idx := int(resolved.get("tile_idx", 0))
		if tile_idx >= 0 and tile_idx < refs.size() and refs[tile_idx] != null:
			var ref_angle := deg_to_rad(float(refs[tile_idx]))
			if bool(resolved.get("flip_h", false)):
				ref_angle = TAU - ref_angle
			angle -= ref_angle
	return angle


func _update_visibility() -> void:
	var visible_now := _should_be_visible()
	if visual_root != null:
		visual_root.visible = visible_now
	if not visible_now:
		for record in _source_records:
			var sprite: Sprite2D = record.get("sprite") as Sprite2D
			if sprite != null:
				sprite.visible = false
		if fallback_sprite != null:
			fallback_sprite.visible = false


func _update_fallback(resting: bool) -> void:
	if fallback_sprite == null or not rig.has_method("get_bone_screen_pose"):
		return
	var socket := str(weapon_data.get("rest_socket" if resting else "socket", "weaponR"))
	var pose_variant: Variant = rig.call("get_bone_screen_pose", socket)
	if not pose_variant is Dictionary:
		fallback_sprite.visible = false
		return
	var pose: Dictionary = pose_variant
	if pose.is_empty():
		fallback_sprite.visible = false
		return
	fallback_sprite.position = pose.get("screen_position", Vector2.ZERO)
	fallback_sprite.rotation = float(pose.get("rotation", 0.0)) + deg_to_rad(_rotation_offset_degrees(resting))
	fallback_sprite.scale = Vector2.ONE * _visual_scale()
	fallback_sprite.z_index = -1 if resting else 6
	fallback_sprite.flip_h = false
	fallback_sprite.visible = _should_be_visible()


func _refresh_fallback_texture(item_record: Dictionary) -> void:
	if fallback_sprite == null:
		return
	var explicit_path := str(weapon_data.get("texture_path", item_record.get("alabaster_weapon_texture_path", ""))).strip_edges()
	if not explicit_path.is_empty() and ResourceLoader.exists(explicit_path):
		var resource := load(explicit_path)
		if resource is Texture2D:
			fallback_sprite.texture = resource as Texture2D
			return
	fallback_sprite.texture = _fallback_texture(str(weapon_data.get("kind", "weapon")))


func _visual_scale() -> float:
	match str(weapon_data.get("kind", "")):
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
		"tonfa": return 90.0
		"crossbow": return 90.0
		"kama": return 15.0
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
		"sword", "broadsword":
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
