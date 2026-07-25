extends "res://tools/content_editor/ContentEditorShaderSuite.gd"


func _build_monster_form() -> void:
	super._build_monster_form()
	_add_subsection_title("Ground Shadow")
	var shadow := _record_dictionary(current_record, "shadow")
	var shadow_offset := _dictionary_vector(shadow, "offset", Vector2(0.0, 12.0))
	var shadow_scale := _dictionary_vector(shadow, "scale", Vector2(0.9, 0.34))
	_add_check_box("Shadow Enabled", "content_shadow_enabled", bool(shadow.get("enabled", true)))
	_add_float_spin_box("Shadow Opacity", "content_shadow_opacity", float(shadow.get("opacity", 0.42)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Shadow Offset X", "content_shadow_offset_x", shadow_offset.x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Offset Y", "content_shadow_offset_y", shadow_offset.y, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Scale X", "content_shadow_scale_x", shadow_scale.x, 0.01, 16.0, 0.01)
	_add_float_spin_box("Shadow Scale Y", "content_shadow_scale_y", shadow_scale.y, 0.01, 16.0, 0.01)
	_add_spin_box("Shadow Z Index", "content_shadow_z", int(shadow.get("z_index", 0)), -4096, 4096, 1)
	_add_content_glow_fields(_record_dictionary(current_record, "glow"), "Monster Glow & Real Light", 24)


func _get_monster_form_record() -> Dictionary:
	var record := super._get_monster_form_record()
	record["shadow"] = {
		"enabled": _get_check_box_pressed("content_shadow_enabled"),
		"opacity": _get_spin_box_value("content_shadow_opacity"),
		"offset": {
			"x": _get_spin_box_value("content_shadow_offset_x"),
			"y": _get_spin_box_value("content_shadow_offset_y"),
		},
		"scale": {
			"x": _get_spin_box_value("content_shadow_scale_x"),
			"y": _get_spin_box_value("content_shadow_scale_y"),
		},
		"z_index": _get_spin_box_int("content_shadow_z"),
	}
	record["glow"] = _get_content_glow_record()
	return record


func _build_building_form() -> void:
	super._build_building_form()
	_add_content_glow_fields(_record_dictionary(current_record, "glow"), "Natural Glow & Real Light", 24)


func _get_building_form_record() -> Dictionary:
	var record := super._get_building_form_record()
	record["glow"] = _get_content_glow_record()
	return record


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Active Player Character")
	var option_button := OptionButton.new()
	var current_character_id := str(current_record.get("character_id", "player"))
	var selected_index := 0
	for character_record in data_store.get_records(ContentEditorData.SECTION_CHARACTERS):
		var character_id := str(character_record.get("id", ""))
		var label := character_id
		var display_name := str(character_record.get("display_name", ""))
		if not display_name.is_empty():
			label = "%s - %s" % [character_id, display_name]
		var index := option_button.item_count
		option_button.add_item(label)
		option_button.set_item_metadata(index, character_id)
		if character_id == current_character_id:
			selected_index = index
	if option_button.item_count > 0:
		option_button.select(selected_index)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Character", option_button)
	field_controls["active_character_id"] = option_button


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	if field_controls.has("active_character_id"):
		record["character_id"] = _get_option_button_metadata("active_character_id")
	return record


func _build_character_form() -> void:
	super._build_character_form()
	_add_subsection_title("Presentation")
	_add_string_option_button(
		"Orientation Mode",
		"character_orientation_mode",
		["top_down", "side_view"],
		str(current_record.get("orientation_mode", "top_down"))
	)


func _get_character_form_record() -> Dictionary:
	var record := super._get_character_form_record()
	if field_controls.has("character_orientation_mode"):
		record["orientation_mode"] = _get_option_button_metadata("character_orientation_mode")
	return record


func _add_animation_detail_editor() -> void:
	super._add_animation_detail_editor()
	var animation_data := _get_selected_animation_data()
	var sprite_sheet_id := _get_animation_sprite_sheet_id(animation_data, selected_sprite_sheet_id)
	var option_button := _make_sprite_sheet_option(sprite_sheet_id)
	option_button.item_selected.connect(_on_animation_source_sheet_selected.bind(option_button))
	_add_form_row("Animation Sprite Sheet", option_button)
	field_controls["animation_source_sheet_id"] = option_button


func _sync_animation_detail_to_record() -> void:
	super._sync_animation_detail_to_record()
	if not field_controls.has("animation_source_sheet_id") or selected_animation_name.is_empty():
		return
	var animation_data := _get_selected_animation_data()
	animation_data["sprite_sheet_id"] = _get_option_button_metadata("animation_source_sheet_id")
	_set_selected_animation_data(animation_data)


func _add_character_animation_setup() -> void:
	var title := Label.new()
	title.text = "Character Animation Setup"
	form_container.add_child(title)

	_add_character_direction_mode_option()

	var validate_button := Button.new()
	validate_button.text = "Validate Character Animations"
	validate_button.pressed.connect(_on_validate_character_animations_pressed)
	form_container.add_child(validate_button)

	_add_character_animation_tools()

	for animation_name in _get_character_available_animation_names():
		_add_character_animation_slot(str(animation_name))

	_add_preview_zoom_option("character_grid_zoom", _on_character_grid_zoom_selected)
	animation_grid_preview = SpriteSheetPreviewScript.new()
	animation_grid_preview.custom_minimum_size = Vector2(320, 320)
	animation_grid_preview.set_fit_minimum_size(Vector2(320, 320))
	animation_grid_preview.set_zoom_scale(_get_preview_zoom_scale("character_grid_zoom"))
	animation_grid_preview.frame_clicked.connect(_on_character_grid_frame_clicked)
	_add_scrollable_preview_row("Character Frame Grid", animation_grid_preview)
	_update_character_grid_preview()

	animation_preview_rect = TextureRect.new()
	animation_preview_rect.custom_minimum_size = Vector2(180, 180)
	animation_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add_form_row("Character Preview", animation_preview_rect)
	_update_character_preview_frame()
	_add_character_preview_controls()


func _add_character_animation_slot(animation_name: String) -> void:
	super._add_character_animation_slot(animation_name)
	var animation_data := _get_character_animation_data(animation_name)
	var sprite_sheet_id := _get_animation_sprite_sheet_id(animation_data, selected_sprite_sheet_id)
	var option_button := _make_sprite_sheet_option(sprite_sheet_id)
	option_button.item_selected.connect(_on_character_animation_sheet_selected.bind(option_button, animation_name))
	_add_form_row("Sheet • %s" % animation_name, option_button)


func _get_selected_sprite_sheet_record() -> Dictionary:
	var sprite_sheet_id := selected_sprite_sheet_id
	if current_section == ContentEditorData.SECTION_ANIMATION_SETS and not selected_animation_name.is_empty():
		sprite_sheet_id = _get_animation_sprite_sheet_id(_get_selected_animation_data(), sprite_sheet_id)
	elif current_section == ContentEditorData.SECTION_CHARACTERS and not active_character_animation_name.is_empty():
		sprite_sheet_id = _get_animation_sprite_sheet_id(_get_character_animation_data(active_character_animation_name), sprite_sheet_id)
	if sprite_sheet_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id):
		return {}
	return data_store.get_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id)


func _get_character_animation_warning(animation_name: String, animation_data: Dictionary) -> String:
	var frames_value: Variant = animation_data.get("frames", [])
	if not (frames_value is Array):
		return "Warning: frames is not a list."
	var frames := frames_value as Array
	if frames.is_empty():
		return "Warning: animation has no frames."
	if _has_invalid_frames_for_animation(animation_data):
		return "Error: animation has frame outside its Sprite Sheet range."
	var frame_count := int(animation_data.get("frame_count", _get_default_character_frame_count(animation_name)))
	if frames.size() < frame_count:
		return "Warning: %d/%d frames selected." % [frames.size(), frame_count]
	if (animation_name.begins_with("walk") or animation_name.begins_with("run")) and frames.size() == 1:
		return "Warning: locomotion animation has only 1 frame."
	return ""


func _get_character_animation_status(animation_name: String, animation_data: Dictionary) -> String:
	var frames_value: Variant = animation_data.get("frames", [])
	if not (frames_value is Array):
		return "Invalid frame"
	var frames := frames_value as Array
	if frames.is_empty():
		return "Empty"
	if _has_invalid_frames_for_animation(animation_data):
		return "Invalid frame"
	var frame_count := int(animation_data.get("frame_count", _get_default_character_frame_count(animation_name)))
	if frames.size() < frame_count:
		return "Missing frames"
	return "Complete"


func _validate_character_animations() -> Array:
	var results := []
	var character_id := _get_line_edit_text("id")
	if character_id.is_empty():
		results.append("ERROR: Character id is empty.")
	if selected_animation_set_id.is_empty():
		results.append("ERROR: Character has no animation_set_id.")
	elif not data_store.has_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id):
		results.append("ERROR: Animation Set does not exist: %s" % selected_animation_set_id)
		return results

	var animations := _get_character_animation_set_animations()
	for required_name in _get_character_animation_slot_names():
		if not animations.has(required_name):
			results.append("ERROR: Missing required animation: %s" % required_name)

	for animation_key in animations.keys():
		var animation_name := str(animation_key)
		var animation_value: Variant = animations[animation_key]
		if not (animation_value is Dictionary):
			results.append("ERROR: Animation %s data is invalid." % animation_name)
			continue
		var animation_data := animation_value as Dictionary
		var sprite_sheet_id := _get_animation_sprite_sheet_id(animation_data, selected_sprite_sheet_id)
		if sprite_sheet_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id):
			results.append("ERROR: %s references missing Sprite Sheet %s." % [animation_name, sprite_sheet_id])
			continue
		var sprite_record := data_store.get_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id)
		if int(sprite_record.get("frame_width", 0)) < 1 or int(sprite_record.get("frame_height", 0)) < 1:
			results.append("ERROR: %s Sprite Sheet has invalid frame dimensions." % animation_name)
		if int(sprite_record.get("columns", 0)) < 1 or int(sprite_record.get("rows", 0)) < 1:
			results.append("ERROR: %s Sprite Sheet has invalid grid dimensions." % animation_name)
		var frames_value: Variant = animation_data.get("frames", [])
		if not (frames_value is Array):
			results.append("ERROR: %s frames must be a list." % animation_name)
			continue
		var frames := frames_value as Array
		if frames.is_empty():
			results.append("WARNING: %s has no frames." % animation_name)
		if _has_invalid_frames_for_animation(animation_data):
			results.append("ERROR: %s has a frame outside %s." % [animation_name, sprite_sheet_id])
		if float(animation_data.get("fps", 0.0)) <= 0.0:
			results.append("ERROR: %s fps must be > 0." % animation_name)

	if results.is_empty():
		results.append("OK: Character animations and per-animation Sprite Sheets are valid.")
	return results


func _update_character_preview_info(extra_message := "") -> void:
	if character_preview_info_label == null:
		return
	var animation_data := _get_character_animation_data(active_character_animation_name)
	var actual_sheet_id := _get_animation_sprite_sheet_id(animation_data, selected_sprite_sheet_id)
	var lines := [
		"animation_set_id: %s" % selected_animation_set_id,
		"sprite_sheet_id: %s" % actual_sheet_id,
		"current_animation: %s" % active_character_animation_name,
		"current_frame_index: %d" % animation_preview_frame_index,
		"fps: %s" % str(animation_data.get("fps", "-")),
		"loop: %s" % str(animation_data.get("loop", "-")),
	]
	if not extra_message.is_empty():
		lines.append(extra_message)
	character_preview_info_label.text = "\n".join(lines)


func _on_animation_source_sheet_selected(index: int, option_button: OptionButton) -> void:
	if selected_animation_name.is_empty() or index < 0 or index >= option_button.item_count:
		return
	var animation_data := _get_selected_animation_data()
	animation_data["sprite_sheet_id"] = str(option_button.get_item_metadata(index))
	_set_selected_animation_data(animation_data)
	animation_preview_frame_index = 0
	_build_form_for_current_record()
	_mark_dirty()


func _on_character_animation_sheet_selected(index: int, option_button: OptionButton, animation_name: String) -> void:
	if index < 0 or index >= option_button.item_count:
		return
	var animation_data := _get_character_animation_data(animation_name)
	animation_data["sprite_sheet_id"] = str(option_button.get_item_metadata(index))
	_set_character_animation_data(animation_name, animation_data)
	active_character_animation_name = animation_name
	animation_preview_frame_index = 0
	_build_form_for_current_record()
	_mark_dirty()


func _make_sprite_sheet_option(selected_id: String) -> OptionButton:
	var option_button := OptionButton.new()
	var selected_index := 0
	for sprite_record in data_store.get_records(ContentEditorData.SECTION_SPRITES):
		if str(sprite_record.get("type", "single_sprite")) != "sprite_sheet":
			continue
		var sprite_id := str(sprite_record.get("id", ""))
		var label := sprite_id
		var display_name := str(sprite_record.get("display_name", ""))
		if not display_name.is_empty():
			label = "%s - %s" % [sprite_id, display_name]
		var index := option_button.item_count
		option_button.add_item(label)
		option_button.set_item_metadata(index, sprite_id)
		if sprite_id == selected_id:
			selected_index = index
	if option_button.item_count > 0:
		option_button.select(selected_index)
	return option_button


func _get_animation_sprite_sheet_id(animation_data: Dictionary, fallback_id: String) -> String:
	var sprite_sheet_id := str(animation_data.get("sprite_sheet_id", fallback_id))
	return fallback_id if sprite_sheet_id.is_empty() else sprite_sheet_id


func _has_invalid_frames_for_animation(animation_data: Dictionary) -> bool:
	var sprite_sheet_id := _get_animation_sprite_sheet_id(animation_data, selected_sprite_sheet_id)
	if sprite_sheet_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id):
		return true
	var sprite_record := data_store.get_record(ContentEditorData.SECTION_SPRITES, sprite_sheet_id)
	var total_frames := int(sprite_record.get("total_frames", 0))
	if total_frames < 1:
		total_frames = int(sprite_record.get("columns", 0)) * int(sprite_record.get("rows", 0))
	var frames_value: Variant = animation_data.get("frames", [])
	if not (frames_value is Array):
		return true
	for frame_value in frames_value as Array:
		var frame_index := int(frame_value)
		if frame_index < 0 or frame_index >= total_frames:
			return true
	return false


func _add_content_glow_fields(glow: Dictionary, heading: String, default_z: int) -> void:
	_add_subsection_title(heading)
	var note := Label.new()
	note.text = "The additive aura is drawn above the sprite. PointLight2D brightens the map, player and nearby objects. Day/Night multipliers control how much light survives the world tint."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	var offset := _dictionary_vector(glow, "offset", Vector2.ZERO)
	var stretch := _dictionary_vector(glow, "stretch", Vector2.ONE)
	_add_check_box("Glow Enabled", "content_glow_enabled", bool(glow.get("enabled", false)))
	_add_check_box("Visual Aura Enabled", "content_glow_visual_enabled", bool(glow.get("visual_enabled", true)))
	_add_string_option_button("Visual Mode", "content_glow_visual_mode", ["texture", "procedural", "both"], str(glow.get("visual_mode", "texture")))
	_add_string_option_button("Overlay Blend", "content_glow_blend_mode", ["additive", "mix"], str(glow.get("blend_mode", "additive")))
	_add_content_color_picker("Glow Color", "content_glow_color", _color_from_value(glow.get("color", "#FFFFFF"), Color.WHITE))
	_add_float_spin_box("Aura Intensity", "content_glow_intensity", float(glow.get("intensity", 1.0)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "content_glow_alpha", float(glow.get("alpha", 0.75)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Scale", "content_glow_scale", float(glow.get("scale", 1.0)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Aura Blur / Softness", "content_glow_blur", float(glow.get("blur", 0.0)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Stretch X", "content_glow_stretch_x", stretch.x, 0.01, 8.0, 0.01)
	_add_float_spin_box("Stretch Y", "content_glow_stretch_y", stretch.y, 0.01, 8.0, 0.01)
	_add_float_spin_box("Glow Offset X", "content_glow_offset_x", offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Glow Offset Y", "content_glow_offset_y", offset.y, -1024.0, 1024.0, 0.5)
	_add_check_box("Flicker Enabled", "content_glow_flicker_enabled", bool(glow.get("flicker_enabled", false)))
	_add_float_spin_box("Flicker Amount", "content_glow_flicker_amount", float(glow.get("flicker_amount", 0.08)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Flicker Speed", "content_glow_flicker_speed", float(glow.get("flicker_speed", 2.0)), 0.05, 12.0, 0.05)
	_add_spin_box("Overlay Z Index", "content_glow_overlay_z", int(glow.get("overlay_z", default_z)), -4096, 4096, 1)
	_add_check_box("Real Light Enabled", "content_glow_light_enabled", bool(glow.get("light_enabled", true)))
	_add_float_spin_box("Light Energy", "content_glow_light_energy", float(glow.get("light_energy", 0.8)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius Scale", "content_glow_light_scale", float(glow.get("light_scale", 1.5)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Day Light Multiplier", "content_glow_day_multiplier", float(glow.get("day_multiplier", 0.18)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Light Multiplier", "content_glow_night_multiplier", float(glow.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)


func _get_content_glow_record() -> Dictionary:
	return {
		"enabled": _get_check_box_pressed("content_glow_enabled"),
		"visual_enabled": _get_check_box_pressed("content_glow_visual_enabled"),
		"visual_mode": _get_option_button_metadata("content_glow_visual_mode"),
		"blend_mode": _get_option_button_metadata("content_glow_blend_mode"),
		"color": _get_content_color_html("content_glow_color"),
		"intensity": _get_spin_box_value("content_glow_intensity"),
		"alpha": _get_spin_box_value("content_glow_alpha"),
		"scale": _get_spin_box_value("content_glow_scale"),
		"blur": _get_spin_box_value("content_glow_blur"),
		"stretch": {
			"x": _get_spin_box_value("content_glow_stretch_x"),
			"y": _get_spin_box_value("content_glow_stretch_y"),
		},
		"offset": {
			"x": _get_spin_box_value("content_glow_offset_x"),
			"y": _get_spin_box_value("content_glow_offset_y"),
		},
		"flicker_enabled": _get_check_box_pressed("content_glow_flicker_enabled"),
		"flicker_amount": _get_spin_box_value("content_glow_flicker_amount"),
		"flicker_speed": _get_spin_box_value("content_glow_flicker_speed"),
		"overlay_z": _get_spin_box_int("content_glow_overlay_z"),
		"light_enabled": _get_check_box_pressed("content_glow_light_enabled"),
		"light_energy": _get_spin_box_value("content_glow_light_energy"),
		"light_scale": _get_spin_box_value("content_glow_light_scale"),
		"day_multiplier": _get_spin_box_value("content_glow_day_multiplier"),
		"night_multiplier": _get_spin_box_value("content_glow_night_multiplier"),
	}


func _add_content_color_picker(label_text: String, field_name: String, value: Color) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.color = value
	picker.edit_alpha = true
	picker.custom_minimum_size = Vector2(120, 32)
	picker.color_changed.connect(func(_new_color: Color) -> void: _mark_dirty())
	_add_form_row(label_text, picker)
	field_controls[field_name] = picker
	return picker


func _get_content_color_html(field_name: String) -> String:
	if not field_controls.has(field_name) or not field_controls[field_name] is ColorPickerButton:
		return "#FFFFFFFF"
	return "#%s" % (field_controls[field_name] as ColorPickerButton).color.to_html(true)


func _record_dictionary(record: Dictionary, key: String) -> Dictionary:
	var value: Variant = record.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _dictionary_vector(record: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var value: Variant = record.get(key, {})
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
