extends "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspaceBankRefresh.gd"

const JunoBaseRigScript := preload("res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd")
const PROFILE_JUNO_BASE := "juno_base"
const JUNO_BASE_LABEL := "JUNO BASE"
const ACTIVE_GREEN := Color(0.08, 1.0, 0.22, 0.24)
const SELECTED_GREEN := Color(0.08, 1.0, 0.22, 0.62)


func setup(owner: Control) -> void:
	super.setup(owner)
	_remove_male_controls()
	_install_juno_base_controls()
	_rebuild_animation_records()
	_update_target_buttons()
	_refresh_live_inspection(true)


func _remove_male_controls() -> void:
	var male_value: Variant = target_buttons.get(PROFILE_MALE, null)
	if male_value is Button:
		var button := male_value as Button
		if button.get_parent() != null:
			button.get_parent().remove_child(button)
		button.queue_free()
	target_buttons.erase(PROFILE_MALE)

	if filter_option != null:
		for index in range(filter_option.item_count - 1, -1, -1):
			if str(filter_option.get_item_metadata(index)) == "MALE":
				filter_option.remove_item(index)


func _install_juno_base_controls() -> void:
	if target_buttons.has(PROFILE_JUNO_BASE):
		return
	var juno_value: Variant = target_buttons.get(PROFILE_JUNO, null)
	if not juno_value is Button:
		return
	var juno_button := juno_value as Button
	var row := juno_button.get_parent()
	if row == null:
		return
	var button := Button.new()
	button.text = JUNO_BASE_LABEL
	button.toggle_mode = true
	button.button_group = juno_button.button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(118.0, 34.0)
	button.tooltip_text = "JunoBase: production Juno skeleton/runtime with the audited core player sprite sheet and an independent tuning namespace."
	button.pressed.connect(_on_target_pressed.bind(PROFILE_JUNO_BASE))
	row.add_child(button)
	row.move_child(button, mini(juno_button.get_index() + 1, row.get_child_count() - 1))
	target_buttons[PROFILE_JUNO_BASE] = button

	if filter_option != null:
		filter_option.add_item(JUNO_BASE_LABEL)
		filter_option.set_item_metadata(filter_option.item_count - 1, JUNO_BASE_LABEL)


func _replace_host_rig(profile_id: String) -> bool:
	if profile_id != PROFILE_JUNO_BASE:
		return super._replace_host_rig(profile_id)
	if host == null:
		return false
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return false
	var preview_world := preview_world_value as Node2D
	var old_rig_value: Variant = host.get("rig")
	if old_rig_value is Node and is_instance_valid(old_rig_value):
		var old_rig := old_rig_value as Node
		if old_rig.get_parent() != null:
			old_rig.get_parent().remove_child(old_rig)
		old_rig.queue_free()

	var new_rig := JunoBaseRigScript.new() as Node2D
	if new_rig == null:
		return false
	new_rig.name = "JunoBaseBoneStudioSharedRig"
	preview_world.add_child(new_rig)
	host.set("rig", new_rig)
	new_rig.scale = Vector2.ONE * PREVIEW_BASE_SCALE * _preview_zoom
	if new_rig.has_method("set_sprite_opacity") and opacity_slider != null:
		new_rig.call("set_sprite_opacity", opacity_slider.value)
	if new_rig.has_method("set_selection_green_intensity") and green_slider != null:
		new_rig.call("set_selection_green_intensity", green_slider.value)
	if new_rig.has_method("set_debug_enabled"):
		var bones_value: Variant = host.get("bone_visibility_check")
		var debug_enabled := true
		if bones_value is CheckBox:
			debug_enabled = (bones_value as CheckBox).button_pressed
		new_rig.call("set_debug_enabled", debug_enabled)
	if new_rig.has_method("set_facing_from_vector"):
		new_rig.call("set_facing_from_vector", Vector2.DOWN)
	if new_rig.has_method("set_editor_animation_paused"):
		new_rig.call("set_editor_animation_paused", false)

	host.call_deferred("_populate_manual_bones")
	host.call_deferred("_rebuild_mapping_table")
	_atlas_signature = ""
	_layers_signature = ""
	return true


func _rebuild_animation_records() -> void:
	# Keep the existing global Juno/Dummy/DEFAULT bank, remove Male completely,
	# then surface JunoBase's own CUSTOM copies without duplicating its 16 Juno
	# source clips in the selector. Juno remains the clean immutable source.
	super._rebuild_animation_records()
	var kept: Array = []
	for record_value in animation_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("source_profile", "")) != PROFILE_MALE:
			kept.append(record.duplicate(true))
	animation_records = kept

	var base_records: Array = Library.get_animation_records(PROFILE_JUNO_BASE)
	for record_value in base_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("source", "")) != "custom":
			continue
		var copy := record.duplicate(true)
		copy["source_profile"] = PROFILE_JUNO_BASE
		animation_records.append(copy)
	_rebuild_animation_option()


func _record_passes_filter(source_profile: String, source_kind: String, filter_name: String) -> bool:
	if filter_name == JUNO_BASE_LABEL:
		return source_profile == PROFILE_JUNO_BASE
	if filter_name == "MALE":
		return false
	return super._record_passes_filter(source_profile, source_kind, filter_name)


func _refresh_atlas_inspector(force: bool) -> void:
	# Restore the original diagnostic intent: green means "this atlas cell is used
	# by the character RIGHT NOW". Selection is additive and stronger, never a
	# filter that hides all other active cells.
	if _atlas_texture_rect == null or _atlas_canvas == null or _atlas_highlight_layer == null:
		return
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var atlas_value: Variant = (rig_value as Object).get("_atlas")
	if not atlas_value is Texture2D:
		return
	var atlas := atlas_value as Texture2D
	var unique_regions: Dictionary = {}
	var signature := "%d|selected=%s" % [atlas.get_instance_id(), selected_part]
	for record_value in _sprite_records():
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			continue
		var node_name := str(record.get("node", ""))
		var gfx_index := int(record.get("gfx_index", 0))
		var key := "%d,%d,%d,%d" % [int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)]
		var is_selected := node_name == selected_part
		if not unique_regions.has(key):
			unique_regions[key] = {
				"rect": region,
				"selected": is_selected,
				"owners": ["%s:gfx%d" % [node_name, gfx_index]],
			}
		else:
			var existing := unique_regions[key] as Dictionary
			existing["selected"] = bool(existing.get("selected", false)) or is_selected
			var owners := existing.get("owners", []) as Array
			owners.append("%s:gfx%d" % [node_name, gfx_index])
			existing["owners"] = owners
			unique_regions[key] = existing
		signature += "|%s:%s" % [key, node_name]
	if not force and signature == _atlas_signature:
		return
	_atlas_signature = signature

	_atlas_texture_rect.texture = atlas
	var atlas_size := Vector2(float(atlas.get_width()), float(atlas.get_height()))
	_atlas_canvas.custom_minimum_size = atlas_size
	_atlas_canvas.size = atlas_size
	_atlas_texture_rect.custom_minimum_size = atlas_size
	_atlas_texture_rect.size = atlas_size
	_atlas_highlight_layer.size = atlas_size
	for child_value in _atlas_highlight_layer.get_children():
		(child_value as Node).queue_free()

	var selected_count := 0
	for region_value in unique_regions.values():
		var region_record := region_value as Dictionary
		var region := region_record.get("rect", Rect2()) as Rect2
		var is_selected := bool(region_record.get("selected", false))
		var mask := ColorRect.new()
		mask.position = region.position
		mask.size = region.size
		mask.color = SELECTED_GREEN if is_selected else ACTIVE_GREEN
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atlas_highlight_layer.add_child(mask)
		if is_selected:
			selected_count += 1

	if _atlas_info_label != null:
		var selection_text := ""
		if not selected_part.is_empty():
			selection_text = " · %s selected cells=%d" % [selected_part, selected_count]
		_atlas_info_label.text = "Atlas %dx%d · ACTIVE NOW = %d green cells%s" % [
			atlas.get_width(), atlas.get_height(), unique_regions.size(), selection_text,
		]
