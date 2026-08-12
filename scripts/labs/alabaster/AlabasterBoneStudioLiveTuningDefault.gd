extends "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningPanelFixed.gd"

const DefaultSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterDefaultPlayableSkinRig.gd")
const PROFILE_DEFAULT := "default"
const DEFAULT_LABEL := "DEFAULT"
const PREVIEW_BASE_SCALE := 3.2
const PREVIEW_ZOOM_MIN := 0.5
const PREVIEW_ZOOM_MAX := 3.0
const PREVIEW_ZOOM_STEP := 0.1
const ATLAS_GREEN := Color(0.08, 1.0, 0.22, 0.36)

var _preview_zoom := 1.0
var _preview_zoom_slider: HSlider = null
var _preview_zoom_value: Label = null
var _atlas_texture_rect: TextureRect = null
var _atlas_canvas: Control = null
var _atlas_highlight_layer: Control = null
var _atlas_info_label: Label = null
var _layer_list: ItemList = null
var _save_current_button: Button = null
var _save_new_button: Button = null
var _atlas_signature := ""
var _layers_signature := ""


func setup(owner: Control) -> void:
	# Build the proven Live Tuning panel first, then compose DEFAULT into it without
	# changing the stable base class/parser chain.
	super.setup(owner)
	_install_default_controls()
	_install_live_inspection_controls()
	target_profile = PROFILE_DEFAULT
	_update_target_buttons()
	if not _replace_host_rig(PROFILE_DEFAULT):
		_set_status("Could not initialize DEFAULT target figure.", true)
		return
	_rebuild_animation_records()
	_rebuild_parts_list()
	_apply_preview_zoom()
	_select_default_idle()
	_refresh_live_inspection(true)
	_refresh_save_buttons()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree():
		return
	_refresh_live_inspection(false)


func _install_default_controls() -> void:
	if target_buttons.has(PROFILE_DEFAULT):
		return
	var template_button: Button = null
	for button_value in target_buttons.values():
		if button_value is Button:
			template_button = button_value as Button
			break
	if template_button != null and template_button.get_parent() != null:
		var row := template_button.get_parent()
		var button := Button.new()
		button.text = DEFAULT_LABEL
		button.toggle_mode = true
		button.button_group = template_button.button_group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110.0, 34.0)
		button.tooltip_text = "Oathwake DEFAULT body. Starts as an independent deep clone of Dummy."
		button.pressed.connect(_on_target_pressed.bind(PROFILE_DEFAULT))
		row.add_child(button)
		row.move_child(button, 0)
		target_buttons[PROFILE_DEFAULT] = button

	if filter_option != null:
		var already_present := false
		for index in range(filter_option.item_count):
			if str(filter_option.get_item_metadata(index)) == DEFAULT_LABEL:
				already_present = true
				break
		if not already_present:
			filter_option.add_item(DEFAULT_LABEL)
			filter_option.set_item_metadata(filter_option.item_count - 1, DEFAULT_LABEL)


func _install_live_inspection_controls() -> void:
	var box := _main_live_box()
	if box == null:
		return

	# Preview zoom lives immediately below animation playback. Scaling only the
	# shared preview rig keeps source pixels/animation data untouched.
	var playback_row := play_button.get_parent() as Control if play_button != null else null
	if playback_row != null:
		var zoom_heading := _make_section_heading("Animation preview")
		var zoom_row := HBoxContainer.new()
		var zoom_label := Label.new()
		zoom_label.text = "Zoom"
		zoom_label.custom_minimum_size = Vector2(145.0, 0.0)
		zoom_row.add_child(zoom_label)
		_preview_zoom_slider = HSlider.new()
		_preview_zoom_slider.min_value = PREVIEW_ZOOM_MIN
		_preview_zoom_slider.max_value = PREVIEW_ZOOM_MAX
		_preview_zoom_slider.step = PREVIEW_ZOOM_STEP
		_preview_zoom_slider.value = _preview_zoom
		_preview_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_preview_zoom_slider.tooltip_text = "Zoom only the Live Tuning character preview. Pixel filtering stays NEAREST."
		_preview_zoom_slider.value_changed.connect(_on_preview_zoom_changed)
		zoom_row.add_child(_preview_zoom_slider)
		_preview_zoom_value = Label.new()
		_preview_zoom_value.custom_minimum_size = Vector2(64.0, 0.0)
		_preview_zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		zoom_row.add_child(_preview_zoom_value)
		var zoom_reset := Button.new()
		zoom_reset.text = "100%"
		zoom_reset.focus_mode = Control.FOCUS_NONE
		zoom_reset.pressed.connect(_reset_preview_zoom)
		zoom_row.add_child(zoom_reset)
		box.add_child(zoom_heading)
		box.add_child(zoom_row)
		var zoom_index := playback_row.get_index() + 1
		box.move_child(zoom_heading, zoom_index)
		box.move_child(zoom_row, zoom_index + 1)
		_update_preview_zoom_label()

		# Native-size atlas viewer. It intentionally scrolls instead of resampling,
		# so every source pixel remains inspectable and the green overlay maps 1:1.
		var atlas_heading := _make_section_heading("Sprite sheet · active figure")
		_atlas_info_label = Label.new()
		_atlas_info_label.text = "Select a visual part/bone to locate its current sprite cell in the atlas."
		_atlas_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var atlas_scroll := ScrollContainer.new()
		atlas_scroll.custom_minimum_size = Vector2(0.0, 154.0)
		atlas_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_atlas_canvas = Control.new()
		_atlas_canvas.custom_minimum_size = Vector2(672.0, 120.0)
		atlas_scroll.add_child(_atlas_canvas)
		_atlas_texture_rect = TextureRect.new()
		_atlas_texture_rect.position = Vector2.ZERO
		_atlas_texture_rect.size = Vector2(672.0, 120.0)
		_atlas_texture_rect.custom_minimum_size = Vector2(672.0, 120.0)
		_atlas_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_atlas_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP
		_atlas_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_atlas_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atlas_canvas.add_child(_atlas_texture_rect)
		_atlas_highlight_layer = Control.new()
		_atlas_highlight_layer.position = Vector2.ZERO
		_atlas_highlight_layer.size = Vector2(672.0, 120.0)
		_atlas_highlight_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atlas_canvas.add_child(_atlas_highlight_layer)
		box.add_child(atlas_heading)
		box.add_child(_atlas_info_label)
		box.add_child(atlas_scroll)
		var atlas_index := zoom_row.get_index() + 1
		box.move_child(atlas_heading, atlas_index)
		box.move_child(_atlas_info_label, atlas_index + 1)
		box.move_child(atlas_scroll, atlas_index + 2)

	# True visual stack: this is sorted from the current highest z_index down and
	# therefore follows directional/animation depth changes live, not a guessed
	# static skeleton order.
	if parts_list != null and parts_list.get_parent() != null:
		var part_split := parts_list.get_parent() as Control
		var layer_heading := _make_section_heading("Visual sprite layer hierarchy")
		var layer_hint := Label.new()
		layer_hint.text = "TOP → BOTTOM. The list refreshes when the animation changes z-order. Clicking a row selects that sprite's owning bone."
		layer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_layer_list = ItemList.new()
		_layer_list.custom_minimum_size = Vector2(0.0, 210.0)
		_layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_layer_list.item_selected.connect(_on_visual_layer_selected)
		box.add_child(layer_heading)
		box.add_child(layer_hint)
		box.add_child(_layer_list)
		var layer_index := part_split.get_index() + 1
		box.move_child(layer_heading, layer_index)
		box.move_child(layer_hint, layer_index + 1)
		box.move_child(_layer_list, layer_index + 2)

	# Existing save remains the create-copy operation, but its intent is now
	# explicit. SAVE CURRENT is enabled only while an existing custom animation of
	# the active target profile is selected, preventing accidental source writes.
	_save_new_button = _find_button_by_text(box, "SAVE CUSTOM TUNING")
	if _save_new_button != null:
		_save_new_button.text = "SAVE NEW"
		_save_new_button.tooltip_text = "Create a new custom animation copy. Existing source clips remain read-only."
		_save_current_button = Button.new()
		_save_current_button.text = "SAVE CURRENT"
		_save_current_button.focus_mode = Control.FOCUS_NONE
		_save_current_button.tooltip_text = "Update the currently selected custom animation. Enabled only for an existing custom animation of this target figure."
		_save_current_button.pressed.connect(_save_current_tuning)
		box.add_child(_save_current_button)
		box.move_child(_save_current_button, _save_new_button.get_index())
	_refresh_save_buttons()


func _main_live_box() -> VBoxContainer:
	if status_label != null and status_label.get_parent() is VBoxContainer:
		return status_label.get_parent() as VBoxContainer
	if save_name != null and save_name.get_parent() != null and save_name.get_parent().get_parent() is VBoxContainer:
		return save_name.get_parent().get_parent() as VBoxContainer
	return null


func _make_section_heading(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 15)
	return label


func _find_button_by_text(node: Node, text_value: String) -> Button:
	for child_value in node.get_children():
		var child := child_value as Node
		if child is Button and (child as Button).text == text_value:
			return child as Button
		var nested := _find_button_by_text(child, text_value)
		if nested != null:
			return nested
	return null


func _replace_host_rig(profile_id: String) -> bool:
	if profile_id != PROFILE_DEFAULT:
		var ok := super._replace_host_rig(profile_id)
		if ok:
			_apply_preview_zoom()
			_atlas_signature = ""
			_layers_signature = ""
		return ok
	if host == null:
		return false
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return false
	var preview_world: Node2D = preview_world_value as Node2D
	var old_rig_value: Variant = host.get("rig")
	if old_rig_value is Node:
		var old_rig: Node = old_rig_value as Node
		if is_instance_valid(old_rig):
			if old_rig.get_parent() != null:
				old_rig.get_parent().remove_child(old_rig)
			old_rig.queue_free()

	var new_rig: Node2D = DefaultSkinRigScript.new() as Node2D
	if new_rig == null:
		return false
	new_rig.call("configure_skin_profile", PROFILE_DEFAULT)
	new_rig.name = "DefaultBoneStudioSharedRig"
	preview_world.add_child(new_rig)
	if new_rig.has_method("initialize_skin") and not bool(new_rig.call("initialize_skin")):
		new_rig.queue_free()
		return false

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
	# Parent owns Juno/Dummy/Male. DEFAULT adds its own immutable native source and
	# its own custom-copy namespace; Juno clips remain globally available to retarget.
	super._rebuild_animation_records()
	var records: Array = Library.get_animation_records(PROFILE_DEFAULT)
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record := (record_value as Dictionary).duplicate(true)
		record["source_profile"] = PROFILE_DEFAULT
		animation_records.append(record)
	_rebuild_animation_option()


func _record_passes_filter(source_profile: String, source_kind: String, filter_name: String) -> bool:
	if filter_name == DEFAULT_LABEL:
		return source_profile == PROFILE_DEFAULT
	return super._record_passes_filter(source_profile, source_kind, filter_name)


func _load_selected_animation() -> void:
	super._load_selected_animation()
	# The library's DEFAULT source list starts from the immutable Dummy-authored
	# bank, but the actual DEFAULT gameplay rig overlays Juno's canonical clips on
	# names such as walk/run/idle. For DEFAULT-on-DEFAULT editing, resolve the data
	# from the already initialized shared rig so Live Tuning, gameplay and Mechanic
	# Lab are literally sampling the same runtime animation object.
	_install_default_canonical_runtime_preview()
	_refresh_save_buttons()
	_refresh_live_inspection(true)


func _install_default_canonical_runtime_preview() -> void:
	if not _uses_default_canonical_runtime_source():
		return
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object := rig_value as Object
	if not rig_object.has_method("get_animation_data") or not rig_object.has_method("install_runtime_animation"):
		return
	var animation_name := str(current_record.get("name", ""))
	var canonical_value: Variant = rig_object.call("get_animation_data", animation_name)
	if not canonical_value is Dictionary or (canonical_value as Dictionary).is_empty():
		return
	var canonical := (canonical_value as Dictionary).duplicate(true)
	var tuning_value: Variant = canonical.get(TUNING_KEY, {})
	working_tuning = (tuning_value as Dictionary).duplicate(true) if tuning_value is Dictionary else {}
	canonical["repeat"] = loop_check.button_pressed
	if not bool(rig_object.call("install_runtime_animation", PREVIEW_ANIMATION, canonical)):
		_set_status("Could not install canonical DEFAULT runtime preview.", true)
		return
	rig_object.call("set_animation", PREVIEW_ANIMATION)
	_apply_working_tuning()
	_set_playback_state(autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE)
	_clamp_live_frame_range()
	var start_frame := int(canonical.get("animStart", 0))
	_seek_frame(start_frame)
	_sync_adjustment_controls()
	var variant_label := "runtime canonical"
	var retarget_value: Variant = canonical.get("retarget_meta", {})
	if retarget_value is Dictionary:
		variant_label = str((retarget_value as Dictionary).get("target_variant", variant_label))
	_set_status("DEFAULT/%s is using the same canonical runtime clip as Mechanic Lab (%s). Source data remains read-only." % [animation_name, variant_label])


func _uses_default_canonical_runtime_source() -> bool:
	return (
		target_profile == PROFILE_DEFAULT
		and str(current_record.get("source_profile", "")) == PROFILE_DEFAULT
		and str(current_record.get("source", "builtin")) == "builtin"
	)


func _on_preview_zoom_changed(value: float) -> void:
	_preview_zoom = clampf(value, PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX)
	_update_preview_zoom_label()
	_apply_preview_zoom()


func _reset_preview_zoom() -> void:
	_preview_zoom = 1.0
	if _preview_zoom_slider != null:
		_preview_zoom_slider.set_value_no_signal(_preview_zoom)
	_update_preview_zoom_label()
	_apply_preview_zoom()


func _update_preview_zoom_label() -> void:
	if _preview_zoom_value != null:
		_preview_zoom_value.text = "%d%%" % roundi(_preview_zoom * 100.0)


func _apply_preview_zoom() -> void:
	var rig_value: Variant = _rig()
	if rig_value is Node2D:
		(rig_value as Node2D).scale = Vector2.ONE * PREVIEW_BASE_SCALE * _preview_zoom


func _refresh_live_inspection(force: bool) -> void:
	_refresh_atlas_inspector(force)
	_refresh_visual_layer_list(force)


func _sprite_records() -> Array:
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return []
	var records_value: Variant = (rig_value as Object).get("_sprite_records")
	return records_value as Array if records_value is Array else []


func _refresh_atlas_inspector(force: bool) -> void:
	if _atlas_texture_rect == null or _atlas_canvas == null or _atlas_highlight_layer == null:
		return
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var atlas_value: Variant = (rig_value as Object).get("_atlas")
	if not atlas_value is Texture2D:
		return
	var atlas := atlas_value as Texture2D
	var records := _sprite_records()
	var signature := "%d|%s" % [atlas.get_instance_id(), selected_part]
	var selected_regions: Array[Dictionary] = []
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("node", "")) != selected_part:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		var gfx_index := int(record.get("gfx_index", 0))
		selected_regions.append({"rect": region, "gfx_index": gfx_index})
		signature += "|%d:%d,%d,%d,%d" % [gfx_index, int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)]
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

	var region_labels: Array[String] = []
	for region_record in selected_regions:
		var region: Rect2 = region_record["rect"]
		var mask := ColorRect.new()
		mask.position = region.position
		mask.size = region.size
		mask.color = ATLAS_GREEN
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atlas_highlight_layer.add_child(mask)
		region_labels.append("gfx%d @ (%d,%d) %dx%d" % [
			int(region_record["gfx_index"]),
			int(region.position.x), int(region.position.y),
			int(region.size.x), int(region.size.y),
		])
	if _atlas_info_label != null:
		if selected_part.is_empty():
			_atlas_info_label.text = "Atlas %dx%d · select a visual part/bone to highlight its current sprite cell." % [atlas.get_width(), atlas.get_height()]
		elif region_labels.is_empty():
			_atlas_info_label.text = "%s · no visible sprite cell in the current frame/direction." % selected_part
		else:
			_atlas_info_label.text = "%s · %s" % [selected_part, " · ".join(region_labels)]


func _refresh_visual_layer_list(force: bool) -> void:
	if _layer_list == null:
		return
	var rows: Array[Dictionary] = []
	for record_value in _sprite_records():
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null:
			continue
		var node_name := str(record.get("node", ""))
		var gfx_index := int(record.get("gfx_index", 0))
		rows.append({
			"node": node_name,
			"gfx_index": gfx_index,
			"z": sprite.z_index,
			"visible": sprite.visible,
			"name": sprite.name,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var za := int(a.get("z", 0))
		var zb := int(b.get("z", 0))
		if za == zb:
			return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
		return za > zb
	)
	var signature := ""
	for row in rows:
		signature += "%s:%d:%d:%s|" % [str(row["node"]), int(row["gfx_index"]), int(row["z"]), str(row["visible"])]
	if not force and signature == _layers_signature:
		return
	_layers_signature = signature
	_layer_list.clear()
	for index in range(rows.size()):
		var row := rows[index]
		var visibility := "VISIBLE" if bool(row["visible"]) else "hidden"
		var prefix := "TOP" if index == 0 else "%02d" % (index + 1)
		_layer_list.add_item("%s  z=%d  %s · gfx%d  [%s]" % [prefix, int(row["z"]), str(row["node"]), int(row["gfx_index"]), visibility])
		_layer_list.set_item_metadata(_layer_list.item_count - 1, row.duplicate(true))
		if str(row["node"]) == selected_part and not _layer_list.is_selected(_layer_list.item_count - 1):
			_layer_list.select(_layer_list.item_count - 1)


func _on_visual_layer_selected(index: int) -> void:
	if _layer_list == null or index < 0 or index >= _layer_list.item_count:
		return
	var meta_value: Variant = _layer_list.get_item_metadata(index)
	if not meta_value is Dictionary:
		return
	var node_name := str((meta_value as Dictionary).get("node", ""))
	if node_name.is_empty():
		return
	selected_part = node_name
	_select_part_in_list(selected_part)
	var rig_value: Variant = _rig()
	if rig_value is Object and (rig_value as Object).has_method("set_selected_sprite_part"):
		(rig_value as Object).call("set_selected_sprite_part", selected_part)
	_sync_adjustment_controls()
	_atlas_signature = ""
	_layers_signature = ""
	_refresh_live_inspection(true)


func _refresh_save_buttons() -> void:
	if _save_current_button == null:
		return
	var can_update := (
		str(current_record.get("source", "")) == "custom"
		and str(current_record.get("source_profile", "")) == target_profile
	)
	_save_current_button.disabled = not can_update
	if can_update:
		_save_current_button.tooltip_text = "Update '%s' in place." % str(current_record.get("name", ""))
	else:
		_save_current_button.tooltip_text = "Select an existing custom animation for this target figure to update it."


func _save_custom_tuning() -> void:
	# This override is the signal target of the original save button. It now means
	# SAVE NEW explicitly and refuses to silently overwrite an existing custom.
	if current_record.is_empty():
		_set_status("Choose an animation first.", true)
		return
	var clean_name := _sanitize_name(save_name.text)
	if clean_name.is_empty():
		_set_status("Choose a valid custom animation name.", true)
		return
	var existing := Library.load_custom_animations(target_profile)
	if existing.has(clean_name):
		_set_status("Custom '%s' already exists. Select it and use SAVE CURRENT, or choose a new name." % clean_name, true)
		return
	if _uses_default_canonical_runtime_source():
		_save_default_runtime_copy(clean_name)
		return
	super._save_custom_tuning()
	call_deferred("_activate_saved_custom", clean_name)


func _save_current_tuning() -> void:
	if str(current_record.get("source", "")) != "custom" or str(current_record.get("source_profile", "")) != target_profile:
		_set_status("SAVE CURRENT is available only for an existing custom animation of the active target figure.", true)
		return
	var current_name := str(current_record.get("name", ""))
	if current_name.is_empty():
		return
	save_name.text = current_name
	# Call the parent implementation deliberately: updating the already selected
	# custom name is the one place where overwrite is intentional.
	super._save_custom_tuning()
	call_deferred("_activate_saved_custom", current_name)


func _save_default_runtime_copy(clean_name: String) -> void:
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object := rig_value as Object
	if not rig_object.has_method("get_animation_data"):
		return
	var source_name := str(current_record.get("name", ""))
	var source_value: Variant = rig_object.call("get_animation_data", source_name)
	if not source_value is Dictionary or (source_value as Dictionary).is_empty():
		_set_status("Could not reload canonical DEFAULT runtime animation '%s'." % source_name, true)
		return
	var save_data := (source_value as Dictionary).duplicate(true)
	save_data[TUNING_KEY] = working_tuning.duplicate(true)
	save_data["repeat"] = loop_check.button_pressed
	var meta := {
		"type": "live_tuning",
		"target_profile": PROFILE_DEFAULT,
		"source_profile": PROFILE_DEFAULT,
		"source_animation": source_name,
		"source_kind": "runtime_canonical",
		"runtime_equivalent_to_mechanic_lab": true,
		"non_destructive": true,
	}
	if not Library.save_custom_animation(clean_name, save_data, meta):
		_set_status("Save blocked. Source/runtime clips are read-only; choose another copy name.", true)
		return
	if rig_object.has_method("install_runtime_animation"):
		rig_object.call("install_runtime_animation", clean_name, save_data)
	_rebuild_animation_records()
	_set_status("Saved new custom '%s' from the canonical DEFAULT runtime clip. Mechanic Lab source was not modified." % clean_name)
	call_deferred("_activate_saved_custom", clean_name)


func _activate_saved_custom(animation_name: String) -> void:
	if animation_option == null:
		return
	for index in range(animation_option.item_count):
		var meta_value: Variant = animation_option.get_item_metadata(index)
		if not meta_value is Dictionary:
			continue
		var record := meta_value as Dictionary
		if (
			str(record.get("name", "")) == animation_name
			and str(record.get("source_profile", "")) == target_profile
			and str(record.get("source", "")) == "custom"
		):
			animation_option.select(index)
			_on_animation_selected(index)
			_refresh_save_buttons()
			return
