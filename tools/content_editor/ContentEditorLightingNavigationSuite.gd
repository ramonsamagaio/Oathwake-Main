extends "res://tools/content_editor/ContentEditorPlayerLightPerspectiveSuite.gd"

const SECTION_LIGHTING := "lighting"
const LIGHTING_DEFAULT_CATEGORY := "player"
const LIGHTING_CATEGORIES := [
	{
		"id": "player",
		"label": "Player",
		"description": "Light emitted by the active player body and future equipped emitters.",
		"section": ContentEditorData.SECTION_PLAYER_TUNING,
	},
	{
		"id": "monsters",
		"label": "Emitters • Monsters",
		"description": "Natural, magical and creature-based light emitters.",
		"section": ContentEditorData.SECTION_MONSTERS,
	},
	{
		"id": "buildings",
		"label": "Emitters • Buildings",
		"description": "Campfires, lamps, windows and other constructed emitters.",
		"section": ContentEditorData.SECTION_BUILDINGS,
	},
	{
		"id": "resources",
		"label": "Emitters • Resources",
		"description": "Crystals, lava resources and gatherable world emitters.",
		"section": ContentEditorData.SECTION_RESOURCES,
	},
	{
		"id": "items",
		"label": "Emitters • Items",
		"description": "Prepared for lanterns, luminous helmets, lava armor and equipped item lights.",
		"section": ContentEditorData.SECTION_ITEMS,
	},
	{
		"id": "skills",
		"label": "Emitters • Skills",
		"description": "Reserved for persistent spell, aura and summoned skill emitters.",
		"section": "",
	},
]

const LEGACY_CONTENT_LIGHT_FIELDS := [
	"content_glow_enabled",
	"content_glow_visual_enabled",
	"content_glow_visual_mode",
	"content_glow_blend_mode",
	"content_glow_color",
	"content_glow_intensity",
	"content_glow_alpha",
	"content_glow_scale",
	"content_glow_blur",
	"content_glow_stretch_x",
	"content_glow_stretch_y",
	"content_glow_offset_x",
	"content_glow_offset_y",
	"content_glow_flicker_enabled",
	"content_glow_flicker_amount",
	"content_glow_flicker_speed",
	"content_glow_overlay_z",
	"content_glow_light_enabled",
	"content_glow_light_energy",
	"content_glow_light_scale",
	"content_glow_day_multiplier",
	"content_glow_night_multiplier",
]

const LEGACY_PLAYER_LIGHT_FIELDS := [
	"player_light_enabled",
	"player_light_visual_aura",
	"player_light_color",
	"player_light_aura_intensity",
	"player_light_aura_alpha",
	"player_light_aura_scale",
	"player_light_blur",
	"player_light_emission",
	"player_light_radius",
	"player_light_day",
	"player_light_night",
	"player_light_offset_x",
	"player_light_offset_y",
	"player_light_perspective_angle",
]

const CENTRAL_ONLY_GLOW_KEYS := [
	"perspective_angle_degrees",
	"casts_night_shadows",
]

const CENTRAL_ONLY_PLAYER_KEYS := [
	"light_enabled",
	"visual_mode",
	"blend_mode",
	"stretch",
	"flicker_enabled",
	"flicker_amount",
	"flicker_speed",
	"overlay_z",
	"casts_night_shadows",
]

var _lighting_category := LIGHTING_DEFAULT_CATEGORY
var _lighting_record_id := "default"
var _lighting_category_button: OptionButton


func _ready() -> void:
	super._ready()
	call_deferred("_install_lighting_workspace")


func _install_lighting_workspace() -> void:
	if not is_inside_tree():
		return
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar != null and not sidebar_buttons.has(SECTION_LIGHTING):
		var button := Button.new()
		button.name = "LightingSectionButton"
		button.text = "Lighting"
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Central workspace for every authored light emitter."
		button.pressed.connect(_on_section_button_pressed.bind(SECTION_LIGHTING))
		sidebar.add_child(button)
		sidebar_buttons[SECTION_LIGHTING] = button
		var world_shadows_button: Variant = sidebar_buttons.get(SECTION_WORLD_SHADOWS)
		if world_shadows_button is Button:
			sidebar.move_child(button, (world_shadows_button as Button).get_index())

	var record_panel := get_node_or_null("MarginContainer/MainLayout/ContentSplit/RecordPanel") as VBoxContainer
	if record_panel != null and _lighting_category_button == null:
		_lighting_category_button = OptionButton.new()
		_lighting_category_button.name = "LightingCategoryFilter"
		_lighting_category_button.tooltip_text = "Choose which kind of emitter is listed below."
		for category_value in LIGHTING_CATEGORIES:
			var category := category_value as Dictionary
			var index := _lighting_category_button.item_count
			_lighting_category_button.add_item(str(category.get("label", "Emitter")))
			_lighting_category_button.set_item_metadata(index, str(category.get("id", "")))
		_lighting_category_button.item_selected.connect(_on_lighting_category_selected)
		record_panel.add_child(_lighting_category_button)
		record_panel.move_child(_lighting_category_button, 1)
	_sync_lighting_workspace_visibility()


func _is_independent_section(section: String) -> bool:
	return section == SECTION_LIGHTING or super._is_independent_section(section)


func _canonical_section(section: String) -> String:
	if section == SECTION_LIGHTING:
		var category_section := _lighting_category_section()
		return category_section if not category_section.is_empty() else ContentEditorData.SECTION_PLAYER_TUNING
	return super._canonical_section(section)


func _section_title(section: String) -> String:
	if section == SECTION_LIGHTING:
		return "Lighting"
	return super._section_title(section)


func _select_section(section: String, force := false) -> void:
	super._select_section(section, force)
	_sync_lighting_workspace_visibility()
	if section != SECTION_LIGHTING or current_section != SECTION_LIGHTING:
		return
	search_line_edit.placeholder_text = "Search light emitters by id or name"
	_select_lighting_category_button()
	if _lighting_record_id.is_empty() or not _lighting_record_exists(_lighting_record_id):
		_lighting_record_id = _default_lighting_record_id()
	_load_lighting_record(_lighting_record_id)


func _sync_lighting_workspace_visibility() -> void:
	if _lighting_category_button != null:
		_lighting_category_button.visible = current_section == SECTION_LIGHTING


func _select_lighting_category_button() -> void:
	if _lighting_category_button == null:
		return
	for index in range(_lighting_category_button.item_count):
		if str(_lighting_category_button.get_item_metadata(index)) == _lighting_category:
			_lighting_category_button.select(index)
			return


func _on_lighting_category_selected(index: int) -> void:
	if _lighting_category_button == null or index < 0 or index >= _lighting_category_button.item_count:
		return
	var selected_category := str(_lighting_category_button.get_item_metadata(index))
	if selected_category == _lighting_category:
		return
	if has_unsaved_changes:
		_set_status("Save or Revert before changing emitter category.", true)
		_select_lighting_category_button()
		return
	_lighting_category = selected_category
	_lighting_record_id = _default_lighting_record_id()
	_load_lighting_record(_lighting_record_id)


func _refresh_record_list() -> void:
	if current_section != SECTION_LIGHTING:
		super._refresh_record_list()
		return
	is_refreshing_list = true
	record_list.clear()
	var query := search_line_edit.text.strip_edges().to_lower()
	if _lighting_category == "skills":
		var skills_label := "Prepared • no skill content records yet"
		if query.is_empty() or skills_label.to_lower().contains(query):
			record_list.add_item(skills_label)
			record_list.set_item_metadata(0, "skills_future")
	else:
		for record_value in _lighting_records():
			var record := record_value as Dictionary
			if not _record_matches_search(record, query):
				continue
			var record_id := str(record.get("id", ""))
			var display_name := str(record.get("display_name", ""))
			if _lighting_category == "player":
				display_name = "Active Player"
			var config := _normalized_light_config(record)
			var state_marker := "●" if bool(config.get("enabled", false)) else "○"
			var label := "%s  %s" % [state_marker, record_id]
			if not display_name.is_empty():
				label += " • %s" % display_name
			var item_index := record_list.item_count
			record_list.add_item(label)
			record_list.set_item_metadata(item_index, record_id)
	_select_current_lighting_record()
	is_refreshing_list = false


func _select_current_lighting_record() -> void:
	record_list.deselect_all()
	for index in range(record_list.item_count):
		if str(record_list.get_item_metadata(index)) == _lighting_record_id:
			record_list.select(index)
			return


func _on_record_selected(index: int) -> void:
	if current_section != SECTION_LIGHTING:
		super._on_record_selected(index)
		return
	if is_refreshing_list or index < 0 or index >= record_list.item_count:
		return
	var selected_id := str(record_list.get_item_metadata(index))
	if has_unsaved_changes and selected_id != _lighting_record_id:
		_set_status("Save or Revert before changing light emitter.", true)
		_select_current_lighting_record()
		return
	_load_lighting_record(selected_id)


func _load_record(record_id: String) -> void:
	if current_section != SECTION_LIGHTING:
		super._load_record(record_id)
		return
	_load_lighting_record(record_id)


func _load_lighting_record(record_id: String) -> void:
	_lighting_record_id = record_id
	current_id = record_id
	current_original_id = record_id
	if _lighting_category == "skills":
		current_record = {
			"id": "skills_future",
			"display_name": "Skill emitters",
		}
	else:
		var section := _lighting_category_section()
		current_record = data_store.get_record(section, record_id)
		if current_record.is_empty():
			var fallback_id := _default_lighting_record_id()
			_lighting_record_id = fallback_id
			current_id = fallback_id
			current_original_id = fallback_id
			current_record = data_store.get_record(section, fallback_id)
	has_unsaved_changes = false
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Selected %s" % _lighting_record_display_name())


func _build_form_for_current_record() -> void:
	if current_section != SECTION_LIGHTING:
		super._build_form_for_current_record()
		return
	_clear_form()
	is_building_form = true
	_build_lighting_form()
	is_building_form = false


func _build_lighting_form() -> void:
	var category := _lighting_category_definition()
	form_title_label.text = "Lighting: %s" % _lighting_record_display_name()
	var section := _lighting_category_section()
	current_file_label.text = "File: %s" % (data_store.get_section_path(section) if not section.is_empty() else "future skills content")

	_add_read_only_value("Emitter Category", str(category.get("label", "Lighting")))
	_add_read_only_value("Emitter ID", _lighting_record_id)
	var architecture_note := Label.new()
	architecture_note.text = "Only light-related settings live here. Choose a category and emitter in the middle column; the right column edits that emitter without mixing combat, sprites or gameplay data."
	architecture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(architecture_note)

	if _lighting_category == "skills":
		var future_note := Label.new()
		future_note.text = "Skill emitters are reserved in this workspace. When the skills content section is introduced, its records will appear here without adding another scattered lighting panel."
		future_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form_container.add_child(future_note)
		return

	var config := _normalized_light_config(current_record)
	var offset := _dictionary_vector(config, "offset", Vector2.ZERO)
	var stretch := _dictionary_vector(config, "stretch", Vector2.ONE)

	_add_subsection_title("Emitter Status")
	_add_check_box("Emitter Enabled", "lighting_enabled", bool(config.get("enabled", false)))
	_add_check_box("Visible Aura Enabled", "lighting_visual_enabled", bool(config.get("visual_enabled", true)))
	_add_check_box("Real Light Enabled", "lighting_real_enabled", bool(config.get("light_enabled", true)))

	_add_subsection_title("Aura Appearance")
	_add_string_option_button("Visual Mode", "lighting_visual_mode", ["texture", "procedural", "both"], str(config.get("visual_mode", "texture")))
	_add_string_option_button("Blend Mode", "lighting_blend_mode", ["additive", "mix"], str(config.get("blend_mode", "additive")))
	_add_content_color_picker("Light Color", "lighting_color", _color_from_value(config.get("color", "#FFFFFFFF"), Color.WHITE))
	_add_float_spin_box("Aura Intensity", "lighting_intensity", float(config.get("intensity", 1.0)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "lighting_alpha", float(config.get("alpha", 0.75)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Scale", "lighting_scale", float(config.get("scale", 1.0)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Aura Blur / Softness", "lighting_blur", float(config.get("blur", 0.0)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Stretch X", "lighting_stretch_x", stretch.x, 0.01, 8.0, 0.01)
	_add_float_spin_box("Stretch Y", "lighting_stretch_y", stretch.y, 0.01, 8.0, 0.01)
	_add_float_spin_box("Offset X", "lighting_offset_x", offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Offset Y", "lighting_offset_y", offset.y, -1024.0, 1024.0, 0.5)
	_add_spin_box("Overlay Z Index", "lighting_overlay_z", int(config.get("overlay_z", 24)), -4096, 4096, 1)

	_add_subsection_title("Real Illumination")
	var perspective_note := Label.new()
	perspective_note.text = "Perspective Angle controls the same ellipse for the visible aura, PointLight2D and the mask that protects lit pixels from the night filter. 90° is circular; lower values match the game's angled top-down camera."
	perspective_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(perspective_note)
	_add_float_spin_box("Light Energy", "lighting_energy", float(config.get("light_energy", 0.8)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius Scale", "lighting_radius", float(config.get("light_scale", 1.5)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Perspective Angle", "lighting_perspective", float(config.get("perspective_angle_degrees", 50.0)), 15.0, 90.0, 1.0)
	_add_float_spin_box("Day Multiplier", "lighting_day", float(config.get("day_multiplier", 0.18)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Multiplier", "lighting_night", float(config.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)

	_add_subsection_title("Light Motion")
	_add_check_box("Flicker Enabled", "lighting_flicker_enabled", bool(config.get("flicker_enabled", false)))
	_add_float_spin_box("Flicker Amount", "lighting_flicker_amount", float(config.get("flicker_amount", 0.08)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Flicker Speed", "lighting_flicker_speed", float(config.get("flicker_speed", 2.0)), 0.05, 12.0, 0.05)

	_add_subsection_title("Shadow Interaction")
	var shadow_note := Label.new()
	shadow_note.text = "At night, an enabled emitter can project weak local shadows away from itself. Multiple emitters create multiple directions, while the shared local compositor prevents overlapping shadows from becoming unnaturally darker."
	shadow_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(shadow_note)
	_add_check_box("Casts Local Night Shadows", "lighting_casts_night_shadows", bool(config.get("casts_night_shadows", true)))


func _normalized_light_config(record: Dictionary) -> Dictionary:
	if _lighting_category != "player":
		var glow := _record_dictionary(record, "glow")
		return {
			"enabled": bool(glow.get("enabled", false)),
			"visual_enabled": bool(glow.get("visual_enabled", true)),
			"visual_mode": str(glow.get("visual_mode", "texture")),
			"blend_mode": str(glow.get("blend_mode", "additive")),
			"color": glow.get("color", "#FFFFFFFF"),
			"intensity": float(glow.get("intensity", 1.0)),
			"alpha": float(glow.get("alpha", 0.75)),
			"scale": float(glow.get("scale", 1.0)),
			"blur": float(glow.get("blur", 0.0)),
			"stretch": _dictionary_vector(glow, "stretch", Vector2.ONE),
			"offset": _dictionary_vector(glow, "offset", Vector2.ZERO),
			"flicker_enabled": bool(glow.get("flicker_enabled", false)),
			"flicker_amount": float(glow.get("flicker_amount", 0.08)),
			"flicker_speed": float(glow.get("flicker_speed", 2.0)),
			"overlay_z": int(glow.get("overlay_z", 24)),
			"light_enabled": bool(glow.get("light_enabled", true)),
			"light_energy": float(glow.get("light_energy", 0.8)),
			"light_scale": float(glow.get("light_scale", 1.5)),
			"perspective_angle_degrees": float(glow.get("perspective_angle_degrees", 50.0)),
			"day_multiplier": float(glow.get("day_multiplier", 0.18)),
			"night_multiplier": float(glow.get("night_multiplier", 1.0)),
			"casts_night_shadows": bool(glow.get("casts_night_shadows", true)),
		}

	var light := _record_dictionary(record, "light")
	return {
		"enabled": bool(light.get("enabled", true)),
		"visual_enabled": bool(light.get("visual_aura_enabled", true)),
		"visual_mode": str(light.get("visual_mode", "texture")),
		"blend_mode": str(light.get("blend_mode", "additive")),
		"color": light.get("color", "#AFCBFFFF"),
		"intensity": float(light.get("aura_intensity", 0.75)),
		"alpha": float(light.get("aura_alpha", 0.30)),
		"scale": float(light.get("aura_scale", 0.44)),
		"blur": float(light.get("blur", 1.25)),
		"stretch": _dictionary_vector(light, "stretch", Vector2.ONE),
		"offset": _dictionary_vector(light, "offset", Vector2(0.0, 6.0)),
		"flicker_enabled": bool(light.get("flicker_enabled", false)),
		"flicker_amount": float(light.get("flicker_amount", 0.08)),
		"flicker_speed": float(light.get("flicker_speed", 2.0)),
		"overlay_z": int(light.get("overlay_z", 18)),
		"light_enabled": bool(light.get("light_enabled", true)),
		"light_energy": float(light.get("emission", 0.85)),
		"light_scale": float(light.get("radius_scale", 1.20)),
		"perspective_angle_degrees": float(light.get("perspective_angle_degrees", 50.0)),
		"day_multiplier": float(light.get("day_multiplier", 0.0)),
		"night_multiplier": float(light.get("night_multiplier", 1.0)),
		"casts_night_shadows": bool(light.get("casts_night_shadows", true)),
	}


func _get_lighting_form_config() -> Dictionary:
	return {
		"enabled": _get_check_box_pressed("lighting_enabled"),
		"visual_enabled": _get_check_box_pressed("lighting_visual_enabled"),
		"visual_mode": _get_option_button_metadata("lighting_visual_mode"),
		"blend_mode": _get_option_button_metadata("lighting_blend_mode"),
		"color": _get_content_color_html("lighting_color"),
		"intensity": _get_spin_box_value("lighting_intensity"),
		"alpha": _get_spin_box_value("lighting_alpha"),
		"scale": _get_spin_box_value("lighting_scale"),
		"blur": _get_spin_box_value("lighting_blur"),
		"stretch": {
			"x": _get_spin_box_value("lighting_stretch_x"),
			"y": _get_spin_box_value("lighting_stretch_y"),
		},
		"offset": {
			"x": _get_spin_box_value("lighting_offset_x"),
			"y": _get_spin_box_value("lighting_offset_y"),
		},
		"flicker_enabled": _get_check_box_pressed("lighting_flicker_enabled"),
		"flicker_amount": _get_spin_box_value("lighting_flicker_amount"),
		"flicker_speed": _get_spin_box_value("lighting_flicker_speed"),
		"overlay_z": _get_spin_box_int("lighting_overlay_z"),
		"light_enabled": _get_check_box_pressed("lighting_real_enabled"),
		"light_energy": _get_spin_box_value("lighting_energy"),
		"light_scale": _get_spin_box_value("lighting_radius"),
		"perspective_angle_degrees": _get_spin_box_value("lighting_perspective"),
		"day_multiplier": _get_spin_box_value("lighting_day"),
		"night_multiplier": _get_spin_box_value("lighting_night"),
		"casts_night_shadows": _get_check_box_pressed("lighting_casts_night_shadows"),
	}


func _on_save_pressed() -> void:
	if current_section != SECTION_LIGHTING:
		super._on_save_pressed()
		return
	if _lighting_category == "skills":
		_set_status("Skill emitter records are prepared but not available yet.", true)
		return
	var section := _lighting_category_section()
	var record := current_record.duplicate(true)
	var config := _get_lighting_form_config()
	if _lighting_category == "player":
		var light := _record_dictionary(record, "light")
		light["enabled"] = config["enabled"]
		light["visual_aura_enabled"] = config["visual_enabled"]
		light["visual_mode"] = config["visual_mode"]
		light["blend_mode"] = config["blend_mode"]
		light["color"] = config["color"]
		light["aura_intensity"] = config["intensity"]
		light["aura_alpha"] = config["alpha"]
		light["aura_scale"] = config["scale"]
		light["blur"] = config["blur"]
		light["stretch"] = config["stretch"]
		light["offset"] = config["offset"]
		light["flicker_enabled"] = config["flicker_enabled"]
		light["flicker_amount"] = config["flicker_amount"]
		light["flicker_speed"] = config["flicker_speed"]
		light["overlay_z"] = config["overlay_z"]
		light["light_enabled"] = config["light_enabled"]
		light["emission"] = config["light_energy"]
		light["radius_scale"] = config["light_scale"]
		light["perspective_angle_degrees"] = config["perspective_angle_degrees"]
		light["day_multiplier"] = config["day_multiplier"]
		light["night_multiplier"] = config["night_multiplier"]
		light["casts_night_shadows"] = config["casts_night_shadows"]
		record["light"] = light
	else:
		record["glow"] = config

	var error := _validate_lighting_record(section, _lighting_record_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return
	data_store.set_record(section, _lighting_record_id, _lighting_record_id, record)
	error = data_store.save_section(section)
	if not error.is_empty():
		_set_status(error, true)
		return
	if has_method("_reload_content_db"):
		call("_reload_content_db")
	current_record = data_store.get_record(section, _lighting_record_id)
	has_unsaved_changes = false
	_refresh_record_list()
	_build_form_for_current_record()
	_update_action_buttons()
	_set_status("Saved light settings for %s and applied them to the running game." % _lighting_record_display_name())


func _validate_lighting_record(section: String, record_id: String, record: Dictionary) -> String:
	match section:
		ContentEditorData.SECTION_PLAYER_TUNING:
			return data_store.validate_player_tuning(record_id, record_id, record)
		ContentEditorData.SECTION_MONSTERS:
			return data_store.validate_monster(record_id, record_id, record)
		ContentEditorData.SECTION_BUILDINGS:
			return data_store.validate_building(record_id, record_id, record)
		ContentEditorData.SECTION_RESOURCES:
			return data_store.validate_resource(record_id, record_id, record)
		ContentEditorData.SECTION_ITEMS:
			return data_store.validate_item(record_id, record_id, record)
	return "Unsupported lighting content section."


func _on_revert_pressed() -> void:
	if current_section != SECTION_LIGHTING:
		super._on_revert_pressed()
		return
	_load_lighting_record(_lighting_record_id)


func _on_reload_current_pressed() -> void:
	if current_section != SECTION_LIGHTING:
		super._on_reload_current_pressed()
		return
	var section := _lighting_category_section()
	if section.is_empty():
		return
	var error := data_store.load_section(section)
	if not error.is_empty():
		_set_status(error, true)
		return
	_load_lighting_record(_lighting_record_id)


func _update_action_buttons() -> void:
	super._update_action_buttons()
	if current_section != SECTION_LIGHTING:
		return
	new_button.disabled = true
	duplicate_button.disabled = true
	delete_button.disabled = true
	var editable := _lighting_category != "skills" and not current_record.is_empty()
	save_button.disabled = not editable
	revert_button.disabled = not editable
	reload_current_button.disabled = not editable


func _build_world_shadows_form() -> void:
	super._build_world_shadows_form()
	var shadow := _record_dictionary(current_record, "directional_shadow")
	_add_subsection_title("Solar Shadow Cycle")
	var solar_note := Label.new()
	solar_note.text = "The global sun shadow rotates from the morning side to the evening side, then fades away as daylight disappears."
	solar_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(solar_note)
	_add_check_box("Follow Day Cycle", "shadow_follow_day_cycle", bool(shadow.get("follow_day_cycle", true)))
	_add_float_spin_box("Morning Direction Degrees", "shadow_morning_direction", float(shadow.get("morning_direction_degrees", 135.0)), -360.0, 360.0, 1.0)
	_add_float_spin_box("Evening Direction Degrees", "shadow_evening_direction", float(shadow.get("evening_direction_degrees", 45.0)), -360.0, 360.0, 1.0)
	_add_float_spin_box("Sun Fade Power", "shadow_sun_fade_power", float(shadow.get("sun_fade_power", 1.35)), 0.05, 8.0, 0.05)

	_add_subsection_title("Local Night-Light Shadows")
	var local_note := Label.new()
	local_note.text = "At night, each nearby emitter projects a weaker silhouette in the opposite direction. All local silhouettes are combined through one mask, so their overlaps remain uniform."
	local_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(local_note)
	_add_check_box("Local Light Shadows Enabled", "shadow_local_enabled", bool(shadow.get("local_light_shadows_enabled", true)))
	_add_float_spin_box("Local Shadow Opacity", "shadow_local_opacity", float(shadow.get("local_light_shadow_opacity", 0.12)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Local Shadow Stretch", "shadow_local_stretch", float(shadow.get("local_light_shadow_stretch", 0.72)), 0.05, 4.0, 0.05)
	_add_float_spin_box("Local Shadow Softness", "shadow_local_softness", float(shadow.get("local_light_shadow_softness", 1.5)), 0.0, 16.0, 0.1)


func _get_world_shadows_record() -> Dictionary:
	var record := super._get_world_shadows_record()
	var shadow := _record_dictionary(record, "directional_shadow")
	if field_controls.has("shadow_follow_day_cycle"):
		shadow["follow_day_cycle"] = _get_check_box_pressed("shadow_follow_day_cycle")
		shadow["morning_direction_degrees"] = _get_spin_box_value("shadow_morning_direction")
		shadow["evening_direction_degrees"] = _get_spin_box_value("shadow_evening_direction")
		shadow["sun_fade_power"] = _get_spin_box_value("shadow_sun_fade_power")
		shadow["local_light_shadows_enabled"] = _get_check_box_pressed("shadow_local_enabled")
		shadow["local_light_shadow_opacity"] = _get_spin_box_value("shadow_local_opacity")
		shadow["local_light_shadow_stretch"] = _get_spin_box_value("shadow_local_stretch")
		shadow["local_light_shadow_softness"] = _get_spin_box_value("shadow_local_softness")
	record["directional_shadow"] = shadow
	return record


func _build_monster_form() -> void:
	super._build_monster_form()
	_hide_centralized_lighting_rows(LEGACY_CONTENT_LIGHT_FIELDS, ["Monster Glow & Real Light"])
	_add_lighting_location_note()


func _build_building_form() -> void:
	super._build_building_form()
	_hide_centralized_lighting_rows(LEGACY_CONTENT_LIGHT_FIELDS, ["Natural Glow & Real Light"])
	_add_lighting_location_note()


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_hide_centralized_lighting_rows(LEGACY_PLAYER_LIGHT_FIELDS, ["Player Light"])
	_add_lighting_location_note()


func _hide_centralized_lighting_rows(fields: Array, headings: Array) -> void:
	for field_value in fields:
		_hide_form_row(str(field_value))
	for heading_value in headings:
		_hide_form_label(str(heading_value))
	for child in form_container.get_children():
		if child is Label:
			var label := child as Label
			if label.text.contains("Small light around the active player") or label.text.contains("additive aura is drawn above"):
				label.visible = false


func _add_lighting_location_note() -> void:
	var note := Label.new()
	note.text = "Light parameters for this record are centralized in the Lighting section."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)


func _get_monster_form_record() -> Dictionary:
	return _preserve_centralized_generic_light_keys(super._get_monster_form_record())


func _get_building_form_record() -> Dictionary:
	return _preserve_centralized_generic_light_keys(super._get_building_form_record())


func _preserve_centralized_generic_light_keys(record: Dictionary) -> Dictionary:
	var existing := _record_dictionary(current_record, "glow")
	var glow := _record_dictionary(record, "glow")
	for key_value in CENTRAL_ONLY_GLOW_KEYS:
		var key := str(key_value)
		if existing.has(key):
			glow[key] = existing[key]
	record["glow"] = glow
	return record


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	var existing := _record_dictionary(current_record, "light")
	var light := _record_dictionary(record, "light")
	for key_value in CENTRAL_ONLY_PLAYER_KEYS:
		var key := str(key_value)
		if existing.has(key):
			light[key] = existing[key]
	record["light"] = light
	return record


func _lighting_category_definition() -> Dictionary:
	for category_value in LIGHTING_CATEGORIES:
		var category := category_value as Dictionary
		if str(category.get("id", "")) == _lighting_category:
			return category
	return LIGHTING_CATEGORIES[0] as Dictionary


func _lighting_category_section() -> String:
	return str(_lighting_category_definition().get("section", ""))


func _lighting_records() -> Array:
	var section := _lighting_category_section()
	if section.is_empty():
		return []
	if _lighting_category == "player":
		var player_record := data_store.get_record(section, "default")
		return [player_record] if not player_record.is_empty() else []
	return data_store.get_records(section)


func _default_lighting_record_id() -> String:
	if _lighting_category == "skills":
		return "skills_future"
	if _lighting_category == "player":
		return "default"
	var records := _lighting_records()
	return str((records[0] as Dictionary).get("id", "")) if not records.is_empty() else ""


func _lighting_record_exists(record_id: String) -> bool:
	if _lighting_category == "skills":
		return record_id == "skills_future"
	var section := _lighting_category_section()
	return not section.is_empty() and data_store.has_record(section, record_id)


func _lighting_record_display_name() -> String:
	if _lighting_category == "skills":
		return "Skill Emitters (Prepared)"
	if _lighting_category == "player":
		return "Active Player"
	var display_name := str(current_record.get("display_name", ""))
	return display_name if not display_name.is_empty() else _lighting_record_id
