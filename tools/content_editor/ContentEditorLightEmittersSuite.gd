extends "res://tools/content_editor/ContentEditorPlayerLightPerspectiveSuite.gd"

const SECTION_LIGHT_PLAYER := "light_emitters_player"
const SECTION_LIGHT_MONSTERS := "light_emitters_monsters"
const SECTION_LIGHT_BUILDINGS := "light_emitters_buildings"
const SECTION_LIGHT_ITEMS := "light_emitters_items"
const SECTION_LIGHT_SKILLS := "light_emitters_skills"

const LIGHT_SECTIONS := [
	SECTION_LIGHT_PLAYER,
	SECTION_LIGHT_MONSTERS,
	SECTION_LIGHT_BUILDINGS,
	SECTION_LIGHT_ITEMS,
	SECTION_LIGHT_SKILLS,
]


func _ready() -> void:
	super._ready()
	_install_light_emitter_sidebar()


func _install_light_emitter_sidebar() -> void:
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		return
	var heading := Label.new()
	heading.name = "LightEmittersHeading"
	heading.text = "LIGHT EMITTERS"
	heading.tooltip_text = "Centralized light-only editing. Choose a category here, an emitter in the middle column, and edit only its light parameters on the right."
	sidebar.add_child(heading)
	var entries := [
		[SECTION_LIGHT_PLAYER, "Player / Equipment"],
		[SECTION_LIGHT_MONSTERS, "Monsters"],
		[SECTION_LIGHT_BUILDINGS, "Buildings"],
		[SECTION_LIGHT_ITEMS, "Items"],
		[SECTION_LIGHT_SKILLS, "Skills"],
	]
	for entry in entries:
		var section := str(entry[0])
		var button := Button.new()
		button.text = str(entry[1])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_section_button_pressed.bind(section))
		sidebar.add_child(button)
		sidebar_buttons[section] = button
	var combat_button: Variant = sidebar_buttons.get(ContentEditorData.SECTION_COMBAT_PREVIEW)
	if combat_button is Button:
		var insert_index := (combat_button as Button).get_index()
		sidebar.move_child(heading, insert_index)
		for entry in entries:
			var button := sidebar_buttons.get(str(entry[0])) as Button
			if button != null:
				insert_index += 1
				sidebar.move_child(button, insert_index)


func _is_light_section(section: String) -> bool:
	return LIGHT_SECTIONS.has(section)


func _is_independent_section(section: String) -> bool:
	return _is_light_section(section) or super._is_independent_section(section)


func _canonical_section(section: String) -> String:
	match section:
		SECTION_LIGHT_PLAYER:
			return ContentEditorData.SECTION_PLAYER_TUNING
		SECTION_LIGHT_MONSTERS:
			return ContentEditorData.SECTION_MONSTERS
		SECTION_LIGHT_BUILDINGS:
			return ContentEditorData.SECTION_BUILDINGS
		SECTION_LIGHT_ITEMS:
			return ContentEditorData.SECTION_ITEMS
		SECTION_LIGHT_SKILLS:
			return ""
	return super._canonical_section(section)


func _section_title(section: String) -> String:
	match section:
		SECTION_LIGHT_PLAYER:
			return "Light Emitters: Player / Equipment"
		SECTION_LIGHT_MONSTERS:
			return "Light Emitters: Monsters"
		SECTION_LIGHT_BUILDINGS:
			return "Light Emitters: Buildings"
		SECTION_LIGHT_ITEMS:
			return "Light Emitters: Items"
		SECTION_LIGHT_SKILLS:
			return "Light Emitters: Skills"
	return super._section_title(section)


func _select_section(section: String, force := false) -> void:
	if not _is_light_section(section):
		super._select_section(section, force)
		return
	if not force and has_unsaved_changes:
		_set_status("Save or Revert before changing section.", true)
		_sync_sidebar_buttons()
		return
	current_section = section
	section_title_label.text = _section_title(section)
	var canonical := _canonical_section(section)
	current_file_label.text = "Future content section" if canonical.is_empty() else "File: %s" % data_store.get_section_path(canonical)
	current_original_id = ""
	current_id = ""
	current_record = {}
	if section == SECTION_LIGHT_PLAYER:
		current_original_id = "default"
		current_id = "default"
		current_record = data_store.get_record(canonical, "default")
	else:
		var records := data_store.get_records(canonical) if not canonical.is_empty() else []
		if not records.is_empty():
			current_record = (records[0] as Dictionary).duplicate(true)
			current_id = str(current_record.get("id", ""))
			current_original_id = current_id
	has_unsaved_changes = false
	_sync_sidebar_buttons()
	_refresh_record_list()
	_build_form_for_current_record()
	_update_action_buttons()
	_set_status("Selected %s" % _section_title(section))


func _refresh_record_list() -> void:
	if not _is_light_section(current_section):
		super._refresh_record_list()
		return
	is_refreshing_list = true
	record_list.clear()
	var canonical := _canonical_section(current_section)
	if current_section == SECTION_LIGHT_SKILLS:
		is_refreshing_list = false
		return
	for record in data_store.get_records(canonical):
		_add_record_list_item(record)
	_select_current_record_in_list()
	is_refreshing_list = false


func _load_record(record_id: String) -> void:
	if not _is_light_section(current_section):
		super._load_record(record_id)
		return
	var canonical := _canonical_section(current_section)
	if canonical.is_empty():
		return
	current_original_id = record_id
	current_id = record_id
	current_record = data_store.get_record(canonical, record_id)
	has_unsaved_changes = false
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Loaded light settings for %s" % record_id)


func _build_form_for_current_record() -> void:
	if not _is_light_section(current_section):
		super._build_form_for_current_record()
		return
	_clear_form()
	is_building_form = true
	_build_light_emitter_form()
	is_building_form = false


func _build_light_emitter_form() -> void:
	form_title_label.text = _section_title(current_section)
	if current_section == SECTION_LIGHT_SKILLS:
		_add_subsection_title("Reserved for Skills")
		var note := Label.new()
		note.text = "Skill emitters are intentionally reserved here, but the project does not have a Skills content file yet. When that content domain is added, its emitters will use this same middle-list / right-parameters workflow."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form_container.add_child(note)
		return
	if current_record.is_empty():
		_add_read_only_value("Status", "No records available in this category.")
		return
	_add_read_only_value("Emitter", str(current_record.get("id", "default")))
	_add_read_only_value("Storage", data_store.get_section_path(_canonical_section(current_section)))
	var note := Label.new()
	note.text = "This page edits light only. The middle column selects the content element; gameplay, combat, sprites and unrelated parameters remain in their original sections."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	if current_section == SECTION_LIGHT_PLAYER:
		_build_player_light_only_form()
	else:
		_add_content_glow_fields(_record_dictionary(current_record, "glow"), "Light Emitter", 24)


func _build_player_light_only_form() -> void:
	var light := _record_dictionary(current_record, "light")
	var offset := _dictionary_vector(light, "offset", Vector2(0.0, 6.0))
	_add_subsection_title("Player Base Light")
	_add_check_box("Player Light Enabled", "light_player_enabled", bool(light.get("enabled", true)))
	_add_check_box("Visible Aura Enabled", "light_player_visual", bool(light.get("visual_aura_enabled", true)))
	_add_content_color_picker("Light Color", "light_player_color", _color_from_value(light.get("color", "#AFCBFFFF"), Color(0.69, 0.80, 1.0, 1.0)))
	_add_float_spin_box("Aura Intensity", "light_player_aura_intensity", float(light.get("aura_intensity", 0.75)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "light_player_aura_alpha", float(light.get("aura_alpha", 0.30)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Size", "light_player_aura_scale", float(light.get("aura_scale", 0.44)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Aura Blur / Softness", "light_player_blur", float(light.get("blur", 1.25)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Emission", "light_player_emission", float(light.get("emission", 0.85)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius", "light_player_radius", float(light.get("radius_scale", 1.20)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Perspective Angle", "light_player_angle", float(light.get("perspective_angle_degrees", 50.0)), 15.0, 90.0, 1.0)
	_add_float_spin_box("Day Multiplier", "light_player_day", float(light.get("day_multiplier", 0.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Multiplier", "light_player_night", float(light.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Offset X", "light_player_offset_x", offset.x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Offset Y", "light_player_offset_y", offset.y, -512.0, 512.0, 0.5)
	var future_note := Label.new()
	future_note.text = "Future equipped lanterns, luminous helmets and emissive armor should contribute additional item emitters. Their authoring belongs in Light Emitters: Items, while this record remains the player's base light."
	future_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(future_note)


func _on_save_pressed() -> void:
	if not _is_light_section(current_section):
		super._on_save_pressed()
		return
	if current_section == SECTION_LIGHT_SKILLS or current_record.is_empty():
		_set_status("There is no editable emitter record in this category.", true)
		return
	var record := current_record.duplicate(true)
	if current_section == SECTION_LIGHT_PLAYER:
		record["light"] = _get_player_light_only_record()
	else:
		record["glow"] = _get_content_glow_record()
	var canonical := _canonical_section(current_section)
	var error := _validate_light_record(canonical, current_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return
	data_store.set_record(canonical, current_original_id, current_id, record)
	error = data_store.save_section(canonical)
	if not error.is_empty():
		_set_status(error, true)
		return
	_reload_content_db()
	current_record = data_store.get_record(canonical, current_id)
	current_original_id = current_id
	has_unsaved_changes = false
	_refresh_record_list()
	_build_form_for_current_record()
	_update_action_buttons()
	_set_status("Saved light settings for %s" % current_id)


func _get_player_light_only_record() -> Dictionary:
	return {
		"enabled": _get_check_box_pressed("light_player_enabled"),
		"visual_aura_enabled": _get_check_box_pressed("light_player_visual"),
		"color": _get_content_color_html("light_player_color"),
		"aura_intensity": _get_spin_box_value("light_player_aura_intensity"),
		"aura_alpha": _get_spin_box_value("light_player_aura_alpha"),
		"aura_scale": _get_spin_box_value("light_player_aura_scale"),
		"blur": _get_spin_box_value("light_player_blur"),
		"emission": _get_spin_box_value("light_player_emission"),
		"radius_scale": _get_spin_box_value("light_player_radius"),
		"perspective_angle_degrees": _get_spin_box_value("light_player_angle"),
		"day_multiplier": _get_spin_box_value("light_player_day"),
		"night_multiplier": _get_spin_box_value("light_player_night"),
		"offset": {"x": _get_spin_box_value("light_player_offset_x"), "y": _get_spin_box_value("light_player_offset_y")},
	}


func _validate_light_record(section: String, record_id: String, original_id: String, record: Dictionary) -> String:
	var method_name := ""
	match section:
		ContentEditorData.SECTION_PLAYER_TUNING:
			method_name = "validate_player_tuning"
		ContentEditorData.SECTION_MONSTERS:
			method_name = "validate_monster"
		ContentEditorData.SECTION_BUILDINGS:
			method_name = "validate_building"
		ContentEditorData.SECTION_ITEMS:
			method_name = "validate_item"
	if not method_name.is_empty() and data_store.has_method(method_name):
		return str(data_store.call(method_name, record_id, original_id, record))
	return ""


func _update_action_buttons() -> void:
	super._update_action_buttons()
	if not _is_light_section(current_section):
		return
	new_button.disabled = true
	duplicate_button.disabled = true
	delete_button.disabled = true
	save_button.disabled = current_record.is_empty() or current_section == SECTION_LIGHT_SKILLS
	revert_button.disabled = save_button.disabled
	reload_current_button.disabled = current_section == SECTION_LIGHT_SKILLS


func _on_revert_pressed() -> void:
	if not _is_light_section(current_section):
		super._on_revert_pressed()
		return
	if not current_id.is_empty():
		_load_record(current_id)


func _on_reload_current_pressed() -> void:
	if not _is_light_section(current_section):
		super._on_reload_current_pressed()
		return
	var canonical := _canonical_section(current_section)
	if canonical.is_empty():
		return
	var error := data_store.load_section(canonical)
	if not error.is_empty():
		_set_status(error, true)
		return
	_load_record(current_id if not current_id.is_empty() else "default")


func _build_monster_form() -> void:
	super._build_monster_form()
	_hide_legacy_light_rows("Monster Glow & Real Light")


func _build_building_form() -> void:
	super._build_building_form()
	_hide_legacy_light_rows("Natural Glow & Real Light")


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	for field_name in [
		"player_light_enabled", "player_light_visual_aura", "player_light_color",
		"player_light_aura_intensity", "player_light_aura_alpha", "player_light_aura_scale",
		"player_light_blur", "player_light_emission", "player_light_radius",
		"player_light_day", "player_light_night", "player_light_offset_x",
		"player_light_offset_y", "player_light_perspective_angle",
	]:
		_hide_form_row(field_name)
	_hide_form_label("Player Light")


func _hide_legacy_light_rows(heading: String) -> void:
	for field_name in [
		"content_glow_enabled", "content_glow_visual_enabled", "content_glow_visual_mode",
		"content_glow_blend_mode", "content_glow_color", "content_glow_intensity",
		"content_glow_alpha", "content_glow_scale", "content_glow_blur",
		"content_glow_stretch_x", "content_glow_stretch_y", "content_glow_offset_x",
		"content_glow_offset_y", "content_glow_flicker_enabled", "content_glow_flicker_amount",
		"content_glow_flicker_speed", "content_glow_overlay_z", "content_glow_light_enabled",
		"content_glow_light_energy", "content_glow_light_scale", "content_glow_day_multiplier",
		"content_glow_night_multiplier",
	]:
		_hide_form_row(field_name)
	_hide_form_label(heading)
