extends "res://tools/content_editor/ContentEditorEnvironmentSuite.gd"

const SECTION_WORLD_SHADOWS := "world_shadows"
const SECTION_POST_EFFECTS := "post_effects"
const SECTION_CAMERA_DISPLAY := "camera_display"


func _ready() -> void:
	super._ready()
	_install_independent_sidebar_buttons()


func _install_independent_sidebar_buttons() -> void:
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		return
	var sections := [
		[SECTION_WORLD_SHADOWS, "World Shadows"],
		[SECTION_POST_EFFECTS, "Post Effects"],
		[SECTION_CAMERA_DISPLAY, "Camera & Display"],
	]
	for entry in sections:
		var section := str(entry[0])
		if sidebar_buttons.has(section):
			continue
		var button := Button.new()
		button.text = str(entry[1])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_section_button_pressed.bind(section))
		sidebar.add_child(button)
		sidebar_buttons[section] = button
		var combat_button: Variant = sidebar_buttons.get(ContentEditorData.SECTION_COMBAT_PREVIEW)
		if combat_button is Button:
			sidebar.move_child(button, (combat_button as Button).get_index())


func _is_independent_section(section: String) -> bool:
	return section == SECTION_WORLD_SHADOWS or section == SECTION_POST_EFFECTS or section == SECTION_CAMERA_DISPLAY


func _canonical_section(section: String) -> String:
	return ContentEditorData.SECTION_PLAYER_TUNING if section == SECTION_CAMERA_DISPLAY else ContentEditorData.SECTION_VFX_PROFILES


func _section_title(section: String) -> String:
	match section:
		SECTION_WORLD_SHADOWS:
			return "World Shadows"
		SECTION_POST_EFFECTS:
			return "Post Effects"
		SECTION_CAMERA_DISPLAY:
			return "Camera & Display"
	return section.capitalize()


func _select_section(section: String, force := false) -> void:
	if not _is_independent_section(section):
		super._select_section(section, force)
		return
	if not force and has_unsaved_changes:
		_set_status("Save or Revert before changing section.", true)
		_sync_sidebar_buttons()
		return
	var canonical := _canonical_section(section)
	super._select_section(canonical, true)
	if current_record.is_empty():
		return
	current_section = section
	section_title_label.text = _section_title(section)
	current_file_label.text = "File: %s" % data_store.get_section_path(canonical)
	_sync_sidebar_buttons()
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Selected %s" % _section_title(section))


func _refresh_record_list() -> void:
	if not _is_independent_section(current_section):
		super._refresh_record_list()
		return
	is_refreshing_list = true
	record_list.clear()
	if not current_record.is_empty():
		_add_record_list_item(current_record)
		_select_current_record_in_list()
	is_refreshing_list = false


func _load_record(record_id: String) -> void:
	if not _is_independent_section(current_section):
		super._load_record(record_id)
		return
	var canonical := _canonical_section(current_section)
	current_original_id = "default"
	current_id = "default"
	current_record = data_store.get_record(canonical, "default")
	has_unsaved_changes = false
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Loaded %s" % _section_title(current_section))


func _build_form_for_current_record() -> void:
	if not _is_independent_section(current_section):
		super._build_form_for_current_record()
		return
	_clear_form()
	is_building_form = true
	match current_section:
		SECTION_WORLD_SHADOWS:
			_build_world_shadows_form()
		SECTION_POST_EFFECTS:
			_build_post_effects_form()
		SECTION_CAMERA_DISPLAY:
			_build_camera_display_form()
	is_building_form = false


func _on_save_pressed() -> void:
	if not _is_independent_section(current_section):
		super._on_save_pressed()
		return
	var record := _get_camera_display_record() if current_section == SECTION_CAMERA_DISPLAY else (_get_world_shadows_record() if current_section == SECTION_WORLD_SHADOWS else _get_post_effects_record())
	_save_independent_record(record)


func _save_independent_record(record: Dictionary) -> void:
	var canonical := _canonical_section(current_section)
	var error := data_store.validate_player_tuning("default", "default", record) if canonical == ContentEditorData.SECTION_PLAYER_TUNING else data_store.validate_vfx_profile("default", "default", record)
	if not error.is_empty():
		_set_status(error, true)
		return
	data_store.set_record(canonical, "default", "default", record)
	error = data_store.save_section(canonical)
	if not error.is_empty():
		_set_status(error, true)
		return
	_reload_content_db()
	current_record = data_store.get_record(canonical, "default")
	current_id = "default"
	current_original_id = "default"
	has_unsaved_changes = false
	_refresh_record_list()
	_build_form_for_current_record()
	_update_action_buttons()
	_set_status("Saved %s" % _section_title(current_section))


func _on_revert_pressed() -> void:
	if not _is_independent_section(current_section):
		super._on_revert_pressed()
		return
	_load_record("default")


func _on_reload_current_pressed() -> void:
	if not _is_independent_section(current_section):
		super._on_reload_current_pressed()
		return
	var error := data_store.load_section(_canonical_section(current_section))
	if not error.is_empty():
		_set_status(error, true)
		return
	_load_record("default")


func _update_action_buttons() -> void:
	super._update_action_buttons()
	if not _is_independent_section(current_section):
		return
	var has_record := not current_record.is_empty()
	new_button.disabled = true
	duplicate_button.disabled = true
	delete_button.disabled = true
	save_button.disabled = not has_record
	revert_button.disabled = not has_record
	reload_current_button.disabled = false


func _build_vfx_profile_form() -> void:
	if current_section == SECTION_POST_EFFECTS:
		_build_post_effects_form()
		return
	form_title_label.text = "VFX Profile: %s" % str(current_record.get("id", "default"))
	if str(current_record.get("id", "default")) != "default":
		super._build_vfx_profile_form()
		return
	_add_read_only_value("ID", "default")
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	var note := Label.new()
	note.text = "Global shadows and screen/world post effects now live in the independent World Shadows and Post Effects tabs."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box("Smoke Puff Lifetime", "smoke_puff_lifetime", float(current_record.get("smoke_puff_lifetime", 0.35)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Smoke Puff Scale", "smoke_puff_scale", float(current_record.get("smoke_puff_scale", 1.2)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Floating Text Duration", "floating_text_duration", float(current_record.get("floating_text_duration", 1.45)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Text Duration", "critical_text_duration", float(current_record.get("critical_text_duration", 1.6)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Hit Flash Duration", "hit_flash_duration", float(current_record.get("hit_flash_duration", 0.10)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Hit Flash Duration", "critical_hit_flash_duration", float(current_record.get("critical_hit_flash_duration", 0.14)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Hit Bump Scale", "hit_bump_scale", float(current_record.get("hit_bump_scale", 1.04)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Bump Scale", "critical_bump_scale", float(current_record.get("critical_bump_scale", 1.08)), 0.0, 10.0, 0.01)


func _build_world_shadows_form() -> void:
	form_title_label.text = "World Shadows"
	var shadow := _record_dictionary(current_record, "directional_shadow")
	_add_read_only_value("Storage", "data/vfx_profiles.json → default.directional_shadow")
	var note := Label.new()
	note.text = "Projects the element's own current sprite frame as a ground silhouette. Direction uses screen-space degrees: -45° points northeast, 0° east, 90° south and 180° west."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_check_box("Projected Shadows Enabled", "shadow_enabled", bool(shadow.get("enabled", true)))
	_add_float_spin_box("Opacity / Intensity", "shadow_opacity", float(shadow.get("opacity", 0.30)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Stretch Amount", "shadow_stretch", float(shadow.get("stretch", 1.25)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Direction Degrees", "shadow_direction_degrees", float(shadow.get("direction_degrees", -45.0)), -360.0, 360.0, 1.0)
	_add_content_color_picker("Shadow Color", "shadow_color", _color_from_value(shadow.get("color", "#050609FF"), Color(0.02, 0.024, 0.035, 1.0)))


func _build_post_effects_form() -> void:
	# Reuse the complete existing VFX chain, but expose it from one obvious tab.
	super._build_vfx_profile_form()
	form_title_label.text = "Post Effects"
	_add_subsection_title("Normal Hit Screen Shake")
	var note := Label.new()
	note.text = "Normal hits use a short, weak shake. Critical Hit Strength and Duration are listed near the top of this same tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box("Normal Hit Strength", "normal_shake_strength", float(current_record.get("normal_shake_strength", 0.65)), 0.0, 32.0, 0.05)
	_add_float_spin_box("Normal Hit Duration", "normal_shake_duration", float(current_record.get("normal_shake_duration", 0.075)), 0.0, 2.0, 0.005)
	for field_name in [
		"global_shadow_direction_x",
		"global_shadow_direction_y",
		"global_shadow_opacity",
		"global_shadow_length_scale",
		"global_shadow_width_scale",
		"global_shadow_fade_power",
		"global_shadow_color",
	]:
		_hide_form_row(field_name)
	_hide_form_label("Global Directional Shadow")


func _build_camera_display_form() -> void:
	form_title_label.text = "Camera & Display"
	_add_read_only_value("Storage", "data/player_tuning.json → default.camera / default.display")
	var camera := _record_dictionary(current_record, "camera")
	var display := _record_dictionary(current_record, "display")
	_add_subsection_title("Mouse Wheel Camera Zoom")
	var zoom_note := Label.new()
	zoom_note.text = "Zoom changes only Camera2D. The HUD remains in its CanvasLayer and keeps the same scale. Mouse wheel up zooms in; mouse wheel down zooms out."
	zoom_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(zoom_note)
	_add_check_box("Wheel Zoom Enabled", "camera_wheel_zoom_enabled", bool(camera.get("wheel_zoom_enabled", true)))
	_add_float_spin_box("Default Zoom", "camera_default_zoom", float(camera.get("default_zoom", 2.0)), 0.25, 8.0, 0.05)
	_add_float_spin_box("Minimum Zoom", "camera_minimum_zoom", float(camera.get("minimum_zoom", 1.25)), 0.25, 8.0, 0.05)
	_add_float_spin_box("Maximum Zoom", "camera_maximum_zoom", float(camera.get("maximum_zoom", 3.25)), 0.25, 8.0, 0.05)
	_add_float_spin_box("Zoom Step", "camera_zoom_step", float(camera.get("zoom_step", 0.15)), 0.01, 2.0, 0.01)
	_add_float_spin_box("Zoom Smoothing", "camera_zoom_smoothing", float(camera.get("zoom_smoothing_speed", 10.0)), 0.01, 60.0, 0.1)

	_add_subsection_title("Desktop-Filling Fullscreen")
	var display_note := Label.new()
	display_note.text = "Uses Godot borderless fullscreen, not exclusive fullscreen. It fills the current display while keeping normal Alt+Tab and other application windows available. F11 toggles it at runtime."
	display_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(display_note)
	_add_check_box("Start in Borderless Fullscreen", "display_borderless_on_start", bool(display.get("borderless_fullscreen_on_start", false)))


func _get_vfx_profile_form_record() -> Dictionary:
	if current_section == SECTION_WORLD_SHADOWS:
		return _get_world_shadows_record()
	if current_section == SECTION_POST_EFFECTS:
		return _get_post_effects_record()
	if str(current_record.get("id", "default")) != "default":
		return super._get_vfx_profile_form_record()
	var record := current_record.duplicate(true)
	record["id"] = "default"
	record["display_name"] = _get_line_edit_text("display_name")
	record["smoke_puff_lifetime"] = _get_spin_box_value("smoke_puff_lifetime")
	record["smoke_puff_scale"] = _get_spin_box_value("smoke_puff_scale")
	record["floating_text_duration"] = _get_spin_box_value("floating_text_duration")
	record["critical_text_duration"] = _get_spin_box_value("critical_text_duration")
	record["hit_flash_duration"] = _get_spin_box_value("hit_flash_duration")
	record["critical_hit_flash_duration"] = _get_spin_box_value("critical_hit_flash_duration")
	record["hit_bump_scale"] = _get_spin_box_value("hit_bump_scale")
	record["critical_bump_scale"] = _get_spin_box_value("critical_bump_scale")
	return record


func _get_world_shadows_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = "default"
	record["directional_shadow"] = {
		"enabled": _get_check_box_pressed("shadow_enabled"),
		"opacity": _get_spin_box_value("shadow_opacity"),
		"stretch": _get_spin_box_value("shadow_stretch"),
		"direction_degrees": _get_spin_box_value("shadow_direction_degrees"),
		"color": _get_content_color_html("shadow_color"),
		"z_index": -1,
	}
	return record


func _get_post_effects_record() -> Dictionary:
	var preserved_shadow := _record_dictionary(current_record, "directional_shadow").duplicate(true)
	var record := super._get_vfx_profile_form_record()
	record["id"] = "default"
	record["normal_shake_strength"] = _get_spin_box_value("normal_shake_strength")
	record["normal_shake_duration"] = _get_spin_box_value("normal_shake_duration")
	record["directional_shadow"] = preserved_shadow
	return record


func _get_camera_display_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = "default"
	var minimum_zoom := _get_spin_box_value("camera_minimum_zoom")
	var maximum_zoom := maxf(_get_spin_box_value("camera_maximum_zoom"), minimum_zoom)
	record["camera"] = {
		"wheel_zoom_enabled": _get_check_box_pressed("camera_wheel_zoom_enabled"),
		"default_zoom": clampf(_get_spin_box_value("camera_default_zoom"), minimum_zoom, maximum_zoom),
		"minimum_zoom": minimum_zoom,
		"maximum_zoom": maximum_zoom,
		"zoom_step": _get_spin_box_value("camera_zoom_step"),
		"zoom_smoothing_speed": _get_spin_box_value("camera_zoom_smoothing"),
	}
	record["display"] = {
		"borderless_fullscreen_on_start": _get_check_box_pressed("display_borderless_on_start"),
	}
	return record


func _hide_form_row(field_name: String) -> void:
	var control: Variant = field_controls.get(field_name)
	if control is Control and (control as Control).get_parent() is Control:
		((control as Control).get_parent() as Control).visible = false


func _hide_form_label(label_text: String) -> void:
	for child in form_container.get_children():
		if child is Label and (child as Label).text == label_text:
			(child as Label).visible = false
