extends "res://tools/content_editor/ContentEditorIndependentTabsSuite.gd"

const HitSparksPreviewScript := preload("res://tools/content_editor/previews/HitSparksPreview.gd")
const CampfireLivePreviewScript := preload("res://tools/content_editor/previews/CampfireLivePreview.gd")

var _hit_sparks_preview: Control
var _campfire_preview: Control
var _campfire_night_slider: HSlider


func _clear_form() -> void:
	_hit_sparks_preview = null
	_campfire_preview = null
	_campfire_night_slider = null
	super._clear_form()


func _add_hit_sparks_profile_fields() -> void:
	super._add_hit_sparks_profile_fields()
	_add_subsection_title("Live Hit Pixel Preview")
	var note := Label.new()
	note.text = "Replays the selected hit-spark profile and its contact light continuously. Pixel motion, fade, color, light radius, energy and duration update before saving."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)

	_hit_sparks_preview = HitSparksPreviewScript.new()
	_hit_sparks_preview.name = "HitSparksLivePreview"
	form_container.add_child(_hit_sparks_preview)

	var replay_button := Button.new()
	replay_button.text = "Replay Hit Pixels + Light"
	replay_button.pressed.connect(_restart_hit_sparks_preview)
	form_container.add_child(replay_button)

	# Descendant suites add the contact-light controls after super returns. Bind on
	# the next frame so the preview sees the complete form instead of a half-built one.
	call_deferred("_finish_hit_sparks_preview_setup")


func _finish_hit_sparks_preview_setup() -> void:
	if _hit_sparks_preview == null or not is_instance_valid(_hit_sparks_preview):
		return
	if not bool(_hit_sparks_preview.get_meta("controls_bound", false)):
		_bind_hit_sparks_preview_controls()
		_hit_sparks_preview.set_meta("controls_bound", true)
	_refresh_hit_sparks_preview()


func _build_building_form() -> void:
	super._build_building_form()
	if str(current_record.get("id", "")) != "campfire":
		return

	_add_subsection_title("Live Campfire Preview")
	var note := Label.new()
	note.text = "Uses the real Building.tscn, campfire sprite, ContentGlow, PointLight2D and flicker runtime. Glow and light changes update immediately before saving."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)

	_campfire_preview = CampfireLivePreviewScript.new()
	_campfire_preview.name = "CampfireLivePreview"
	form_container.add_child(_campfire_preview)

	_campfire_night_slider = HSlider.new()
	_campfire_night_slider.min_value = 0.0
	_campfire_night_slider.max_value = 1.0
	_campfire_night_slider.step = 0.01
	_campfire_night_slider.value = 0.65
	_campfire_night_slider.custom_minimum_size = Vector2(220.0, 32.0)
	_campfire_night_slider.value_changed.connect(_on_campfire_preview_night_changed)
	_add_form_row("Preview Night Strength", _campfire_night_slider)

	_bind_campfire_preview_controls()
	_refresh_campfire_preview()


func _bind_hit_sparks_preview_controls() -> void:
	for field_name in [
		"pixel_count",
		"lifetime",
		"fade_out_time",
		"speed_min",
		"speed_max",
		"horizontal_bias",
		"upward_bias",
		"distance",
		"jitter_radius",
		"color_switch_interval",
		"size_min",
		"size_max",
		"gravity",
		"colors",
		"contact_light_enabled",
		"contact_light_color",
		"contact_light_energy",
		"contact_light_radius",
		"contact_light_duration",
		"contact_light_critical_multiplier",
	]:
		_connect_live_preview_control(field_controls.get(field_name), _refresh_hit_sparks_preview)


func _bind_campfire_preview_controls() -> void:
	for field_name in [
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
	]:
		_connect_live_preview_control(field_controls.get(field_name), _refresh_campfire_preview)


func _connect_live_preview_control(control: Variant, callback: Callable) -> void:
	if control is SpinBox:
		(control as SpinBox).value_changed.connect(func(_value: float) -> void: callback.call())
	elif control is ColorPickerButton:
		(control as ColorPickerButton).color_changed.connect(func(_value: Color) -> void: callback.call())
	elif control is OptionButton:
		(control as OptionButton).item_selected.connect(func(_index: int) -> void: callback.call())
	elif control is CheckBox:
		(control as CheckBox).toggled.connect(func(_pressed: bool) -> void: callback.call())
	elif control is LineEdit:
		(control as LineEdit).text_changed.connect(func(_text: String) -> void: callback.call())


func _refresh_hit_sparks_preview() -> void:
	if _hit_sparks_preview == null or not is_instance_valid(_hit_sparks_preview):
		return
	_hit_sparks_preview.call("set_profile", _get_hit_sparks_preview_profile())


func _restart_hit_sparks_preview() -> void:
	if _hit_sparks_preview != null and is_instance_valid(_hit_sparks_preview):
		_hit_sparks_preview.call("restart")


func _get_hit_sparks_preview_profile() -> Dictionary:
	var is_critical: bool = str(current_record.get("id", "")) == "critical_hit_sparks"
	var base_light_record: Dictionary = current_record
	if is_critical:
		base_light_record = data_store.get_record(ContentEditorData.SECTION_VFX_PROFILES, "hit_sparks")

	var contact_enabled: bool = bool(base_light_record.get("contact_light_enabled", true))
	var contact_color: String = str(base_light_record.get("contact_light_color", "#FFD78AFF"))
	var contact_energy: float = float(base_light_record.get("contact_light_energy", 0.72))
	var contact_radius: float = float(base_light_record.get("contact_light_radius", 34.0))
	var contact_duration: float = float(base_light_record.get("contact_light_duration", 0.055))
	if not is_critical:
		if field_controls.has("contact_light_enabled"):
			contact_enabled = _get_check_box_pressed("contact_light_enabled")
		if field_controls.has("contact_light_color"):
			contact_color = _get_content_color_html("contact_light_color")
		if field_controls.has("contact_light_energy"):
			contact_energy = _get_spin_box_value("contact_light_energy")
		if field_controls.has("contact_light_radius"):
			contact_radius = _get_spin_box_value("contact_light_radius")
		if field_controls.has("contact_light_duration"):
			contact_duration = _get_spin_box_value("contact_light_duration")

	var critical_multiplier: float = float(current_record.get("contact_light_critical_multiplier", 2.0))
	if field_controls.has("contact_light_critical_multiplier"):
		critical_multiplier = _get_spin_box_value("contact_light_critical_multiplier")

	return {
		"pixel_count": _get_spin_box_int("pixel_count"),
		"lifetime": _get_spin_box_value("lifetime"),
		"fade_out_time": _get_spin_box_value("fade_out_time"),
		"speed_min": _get_spin_box_value("speed_min"),
		"speed_max": _get_spin_box_value("speed_max"),
		"horizontal_bias": _get_spin_box_value("horizontal_bias"),
		"upward_bias": _get_spin_box_value("upward_bias"),
		"distance": _get_spin_box_value("distance"),
		"jitter_radius": _get_spin_box_value("jitter_radius"),
		"color_switch_interval": _get_spin_box_value("color_switch_interval"),
		"size_min": _get_spin_box_value("size_min"),
		"size_max": _get_spin_box_value("size_max"),
		"gravity": _get_spin_box_value("gravity"),
		"colors": _split_string_list(_get_line_edit_text("colors")),
		"contact_light_enabled": contact_enabled,
		"contact_light_color": contact_color,
		"contact_light_energy": contact_energy,
		"contact_light_radius": contact_radius,
		"contact_light_duration": contact_duration,
		"contact_light_critical_multiplier": critical_multiplier,
		"is_critical": is_critical,
	}


func _refresh_campfire_preview() -> void:
	if _campfire_preview == null or not is_instance_valid(_campfire_preview):
		return
	_campfire_preview.call("set_building_data", _get_building_form_record())
	if _campfire_night_slider != null:
		_campfire_preview.call("set_night_strength", _campfire_night_slider.value)


func _on_campfire_preview_night_changed(value: float) -> void:
	if _campfire_preview != null and is_instance_valid(_campfire_preview):
		_campfire_preview.call("set_night_strength", value)
