extends "res://scripts/player/AlabasterWeaponVisualRuntime.gd"
class_name BonesWeapons

# Production weapon attachment layer for bone-driven characters.
# Equip/change may allocate. Attack input may not parse source data, decode PNGs,
# touch FileAccess or create/free Sprite2D nodes.

var _resident_figures: Dictionary = {}
var _frame_socket_states: Dictionary = {}
var _source_assets_available := false
var _required_source_sheets: Array[String] = []


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	_source_assets_available = false
	_required_source_sheets.clear()
	super.set_item(new_item_id, item_record)
	_prewarm_equipped_weapon()


func set_attacking(value: bool) -> void:
	if attacking == value:
		return
	attacking = value
	_update_visibility()


func update() -> void:
	_frame_socket_states.clear()
	if rig == null or visual_root == null or not has_weapon():
		_update_visibility()
		return
	if not _should_be_visible():
		_update_visibility()
		return

	# Source art is resolved once while equipping. Attack/update never decodes,
	# parses or probes files. If an atlas is unavailable, use the known-good
	# socket placeholder without retrying anything in the frame loop.
	if not _source_assets_available:
		_update_fallback(_use_rest_figure())
		_update_visibility()
		return

	super.update()


func _get_target_state(target_node: String) -> Dictionary:
	if _frame_socket_states.has(target_node):
		return _frame_socket_states[target_node]
	var state := super._get_target_state(target_node)
	_frame_socket_states[target_node] = state
	return state


func _prewarm_equipped_weapon() -> void:
	if not has_weapon():
		return

	var attack_animation := get_attack_animation()
	if not attack_animation.is_empty() and rig != null and rig.has_method("prewarm_animation"):
		rig.call("prewarm_animation", attack_animation)

	var held_figure := str(weapon_data.get("source_figure", "")).strip_edges()
	var rest_figure := str(weapon_data.get("rest_source_figure", "")).strip_edges()
	_required_source_sheets = _required_sheets_for_figures([held_figure, rest_figure])
	_source_assets_available = not _required_source_sheets.is_empty()
	for sheet_name in _required_source_sheets:
		if SourceAssets.load_player_weapon_sheet(sheet_name) == null:
			_source_assets_available = false

	if not _source_assets_available:
		_update_visibility()
		return

	if not held_figure.is_empty() and _has_source_figure(held_figure):
		_build_source_figure(held_figure)
	if not rest_figure.is_empty() and _has_source_figure(rest_figure):
		_build_source_figure(rest_figure)

	var desired := rest_figure if _use_rest_figure() and not rest_figure.is_empty() else held_figure
	if not desired.is_empty() and _has_source_figure(desired):
		_build_source_figure(desired)
	_update_visibility()

	print("BONES_WEAPON_READY item=%s figure=%s sheets=%s" % [item_id, held_figure, ",".join(_required_source_sheets)])


func _required_sheets_for_figures(figure_names: Array) -> Array[String]:
	var found := {}
	var figures_value: Variant = _source_payload.get("figures", {})
	if not figures_value is Dictionary:
		return []
	var figures: Dictionary = figures_value
	for figure_name_value in figure_names:
		var figure_name := str(figure_name_value).strip_edges()
		if figure_name.is_empty():
			continue
		var figure_value: Variant = figures.get(figure_name, {})
		_collect_sheet_names(figure_value, found)
	var result: Array[String] = []
	for sheet_name_value in found.keys():
		result.append(str(sheet_name_value))
	result.sort()
	return result


func _collect_sheet_names(value: Variant, output: Dictionary) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if dictionary.has("sheet"):
			var sheet_name := str(dictionary.get("sheet", "")).strip_edges()
			if not sheet_name.is_empty():
				output[sheet_name] = true
		for child in dictionary.values():
			_collect_sheet_names(child, output)
	elif value is Array:
		for child in value as Array:
			_collect_sheet_names(child, output)


func _build_source_figure(figure_name: String) -> void:
	if not _source_assets_available:
		return
	if _resident_figures.has(figure_name):
		_activate_resident_figure(figure_name)
		return

	var figures_value: Variant = _source_payload.get("figures", {})
	if not figures_value is Dictionary:
		return
	var figure_value: Variant = (figures_value as Dictionary).get(figure_name, {})
	if not figure_value is Dictionary:
		return
	var figure: Dictionary = figure_value
	var nodes_value: Variant = figure.get("nodes", {})
	if not nodes_value is Dictionary:
		return

	var records: Array[Dictionary] = []
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
			sprite.name = "BonesWeapon_%s_%s_%d" % [figure_name, source_node, records.size()]
			sprite.centered = true
			sprite.region_enabled = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_as_relative = true
			sprite.visible = false
			visual_root.add_child(sprite)
			records.append({
				"source_node": source_node,
				"gfx": gfx,
				"sprite": sprite,
				"half_shift": half_shift,
				"figure_global_z": figure_global_z,
			})

	_resident_figures[figure_name] = records
	_activate_resident_figure(figure_name)


# Source weapon figures use the exact same billboard operations as the body.
# In particular Sword/Spear/Tonfa rely on PARENT_ROTATE_SCALE. The old weapon
# path only rotated a Sprite2D around the socket, so blade and hilt could drift
# apart. This override delegates position/rotation/cut/scale to BonesSystem's
# source-derived billboard transform instead of maintaining parallel math.
func _update_source_figure(resting: bool) -> bool:
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
		var resolved := _resolve_gfx_visual(gfx, state, bool(record.get("half_shift", false)))
		if resolved.is_empty():
			sprite.visible = false
			continue
		var texture: Texture2D = resolved.get("texture") as Texture2D
		if texture == null:
			sprite.visible = false
			continue

		var region: Rect2 = resolved.get("region", Rect2())
		var pivot: Vector2 = resolved.get("pivot", Vector2.ZERO)
		var flip_h := bool(resolved.get("flip_h", false))
		var billboard: Dictionary = resolved.get("billboard", {})
		var entry: Dictionary = resolved.get("entry", {})
		var row: Dictionary = resolved.get("row", {})
		var tile_idx := int(resolved.get("tile_idx", 0))
		var local_gfx_pos := _vec3_from_source_value(gfx.get("pos", [0.0, 0.0, 0.0]))
		var tex_rotate := str(row.get("texRotate", "NONE"))
		var skip_rotation := bool(entry.get("rotDefOff", false))
		if bool(state.get("rot_toggle", false)):
			skip_rotation = not skip_rotation
		if skip_rotation:
			tex_rotate = "NONE"

		var source_xfm := {}
		if rig != null and rig.has_method("resolve_external_billboard_transform"):
			var xfm_value: Variant = rig.call(
				"resolve_external_billboard_transform",
				target_node,
				local_gfx_pos,
				billboard,
				row,
				tex_rotate,
				tile_idx,
				int(region.size.x),
				int(region.size.y),
				pivot,
				region,
				flip_h
			)
			if xfm_value is Dictionary:
				source_xfm = xfm_value as Dictionary

		if source_xfm.is_empty():
			sprite.position = _gfx_screen_position(target_node, gfx, state)
			sprite.rotation = _gfx_screen_rotation(resolved, state) if not skip_rotation else 0.0
			sprite.scale = Vector2.ONE
		else:
			sprite.position = source_xfm.get("screen_position", state.get("screen_position", Vector2.ZERO))
			sprite.rotation = float(source_xfm.get("rotation", 0.0))
			sprite.scale = source_xfm.get("scale", Vector2.ONE)
			region = source_xfm.get("region", region)
			pivot = source_xfm.get("pivot", pivot)

		sprite.texture = texture
		sprite.region_rect = region
		sprite.flip_h = flip_h
		sprite.flip_v = bool(resolved.get("flip_v", false))
		var effective_pivot_x: float = region.size.x - pivot.x if flip_h else pivot.x
		sprite.offset = Vector2(region.size.x * 0.5 - effective_pivot_x, region.size.y * 0.5 - pivot.y)

		var facing: Dictionary = resolved.get("facing", {})
		var logical_z := int(record.get("figure_global_z", 0)) + int(billboard.get("zOrder", 0))
		var z_offset := int(row.get("zOff", entry.get("zOff", 0)))
		var z_frames: Variant = row.get("zFrames", entry.get("zFrames", null))
		if z_frames is Array and tile_idx >= 0 and tile_idx < (z_frames as Array).size():
			z_offset += int((z_frames as Array)[tile_idx])
		else:
			var side_back := int(facing.get("side", 0))
			if side_back == 1:
				z_offset += int(row.get("zSide", entry.get("zSide", 0)))
			elif side_back == 2:
				z_offset += int(row.get("zBack", entry.get("zBack", 0)))
		logical_z += z_offset
		if resting:
			logical_z -= 8
		sprite.z_index = clampi(logical_z, -32, 32)
		sprite.visible = _should_be_visible() and region.size.x > 0.0 and region.size.y > 0.0
		any_visible = any_visible or sprite.visible

	return any_visible


func _vec3_from_source_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		var values := value as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO


func _activate_resident_figure(figure_name: String) -> void:
	_hide_all_resident_figures()
	_source_records.clear()
	var records_value: Variant = _resident_figures.get(figure_name, [])
	if records_value is Array:
		for record_value in records_value as Array:
			if record_value is Dictionary:
				_source_records.append(record_value as Dictionary)
	_active_source_figure = figure_name


func _hide_all_resident_figures() -> void:
	for records_value in _resident_figures.values():
		if not records_value is Array:
			continue
		for record_value in records_value as Array:
			if not record_value is Dictionary:
				continue
			var sprite: Sprite2D = (record_value as Dictionary).get("sprite") as Sprite2D
			if sprite != null and is_instance_valid(sprite):
				sprite.visible = false


func _clear_source_records() -> void:
	_frame_socket_states.clear()
	var freed_ids: Dictionary = {}
	for records_value in _resident_figures.values():
		if not records_value is Array:
			continue
		for record_value in records_value as Array:
			if not record_value is Dictionary:
				continue
			var sprite: Sprite2D = (record_value as Dictionary).get("sprite") as Sprite2D
			if sprite == null or not is_instance_valid(sprite):
				continue
			var instance_id := sprite.get_instance_id()
			if freed_ids.has(instance_id):
				continue
			freed_ids[instance_id] = true
			sprite.queue_free()

	for record in _source_records:
		var sprite: Sprite2D = record.get("sprite") as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		var instance_id := sprite.get_instance_id()
		if freed_ids.has(instance_id):
			continue
		freed_ids[instance_id] = true
		sprite.queue_free()

	_source_records.clear()
	_resident_figures.clear()
	_active_source_figure = ""
