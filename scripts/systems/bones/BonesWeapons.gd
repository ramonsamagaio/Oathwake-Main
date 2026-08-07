extends "res://scripts/player/AlabasterWeaponVisualRuntime.gd"
class_name BonesWeapons

# Production weapon attachment layer for bone-driven characters.
# Equip/change may allocate. Attack input may not parse source data, decode PNGs,
# touch FileAccess or create/free Sprite2D nodes.

var _resident_figures: Dictionary = {}
var _frame_socket_states: Dictionary = {}
var _source_sheet_available := false
var _source_sheet_name := ""


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	_source_sheet_available = false
	_source_sheet_name = ""
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

	# Missing optional source art is a normal state, not an error path. Keep the
	# socket-driven procedural placeholder and never ask the asset loader again.
	if not _source_sheet_available:
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

	_source_sheet_name = "ranged" if bool(weapon_data.get("ranged", false)) else "melee"
	_source_sheet_available = SourceAssets.load_player_weapon_sheet(_source_sheet_name) != null
	if not _source_sheet_available:
		_update_visibility()
		return

	var held_figure := str(weapon_data.get("source_figure", "")).strip_edges()
	var rest_figure := str(weapon_data.get("rest_source_figure", "")).strip_edges()
	if not held_figure.is_empty() and _has_source_figure(held_figure):
		_build_source_figure(held_figure)
	if not rest_figure.is_empty() and _has_source_figure(rest_figure):
		_build_source_figure(rest_figure)

	var desired := rest_figure if _use_rest_figure() and not rest_figure.is_empty() else held_figure
	if not desired.is_empty() and _has_source_figure(desired):
		_build_source_figure(desired)
	_update_visibility()


func _build_source_figure(figure_name: String) -> void:
	if not _source_sheet_available:
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
