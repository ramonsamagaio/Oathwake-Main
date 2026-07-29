extends "res://tools/content_editor/ContentEditorPostEffectsNavigationSuite.gd"

const OCCLUSION_ALPHA_FIELD := "world_occlusion_default_alpha"
const SHADOW_SOFTNESS_FIELD := "shadow_softness"
const SPRITE_OCCLUSION_FIELD := "sprite_fade_when_player_behind"


func _build_sprite_form() -> void:
	super._build_sprite_form()
	_add_subsection_title("Player Occlusion")
	var note := Label.new()
	note.text = "When enabled, world elements using this sprite become translucent while they cover the player. Disable it for floor decoration or any sprite that should always remain fully opaque."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_check_box("Fade When Player Is Behind", SPRITE_OCCLUSION_FIELD, bool(current_record.get("fade_when_player_behind", true)))


func _get_sprite_form_record() -> Dictionary:
	var record := super._get_sprite_form_record()
	if field_controls.has(SPRITE_OCCLUSION_FIELD):
		record["fade_when_player_behind"] = _get_check_box_pressed(SPRITE_OCCLUSION_FIELD)
	return record


func _build_world_shadows_form() -> void:
	super._build_world_shadows_form()
	var shadow := _record_dictionary(current_record, "directional_shadow")
	_add_float_spin_box("Diffusion / Blur", SHADOW_SOFTNESS_FIELD, float(shadow.get("softness", 0.0)), 0.0, 16.0, 0.1)
	var softness_control: Variant = field_controls.get(SHADOW_SOFTNESS_FIELD)
	if softness_control is Control:
		(softness_control as Control).tooltip_text = "Softens the final combined shadow mask. Zero preserves the current sharp pixel-art edge."

	var solar := _record_dictionary(shadow, "solar")
	_add_subsection_title("Solar Shadow Cycle")
	_add_check_box("Rotate With Day", "shadow_solar_rotate", bool(solar.get("rotate_with_day", true)))
	_add_check_box("Fade As Night Falls", "shadow_solar_fade", bool(solar.get("fade_with_night", true)))
	_add_float_spin_box("Morning Direction", "shadow_solar_morning", float(solar.get("morning_direction_degrees", -45.0)), -180.0, 180.0, 1.0)
	_add_float_spin_box("Evening Direction", "shadow_solar_evening", float(solar.get("evening_direction_degrees", 45.0)), -180.0, 180.0, 1.0)

	var local_lights := _record_dictionary(shadow, "local_lights")
	_add_subsection_title("Night Local-Light Shadows")
	var local_note := Label.new()
	local_note.text = "At night, every active PointLight2D can cast a weak shadow away from its own position. These masks use the same shared compositor, so overlaps remain bounded instead of multiplying darkness."
	local_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(local_note)
	_add_check_box("Local-Light Shadows Enabled", "shadow_local_enabled", bool(local_lights.get("enabled", true)))
	_add_float_spin_box("Local Shadow Strength", "shadow_local_opacity", float(local_lights.get("opacity_multiplier", 0.28)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Local Shadow Stretch", "shadow_local_stretch", float(local_lights.get("stretch", 0.82)), 0.05, 4.0, 0.05)
	_add_float_spin_box("Distance Falloff", "shadow_local_falloff", float(local_lights.get("distance_falloff", 1.35)), 0.1, 4.0, 0.05)
	_add_spin_box("Max Lights Per Caster", "shadow_local_max_emitters", int(local_lights.get("max_emitters_per_caster", 4)), 1, 8, 1)


func _get_world_shadows_record() -> Dictionary:
	var record := super._get_world_shadows_record()
	var shadow := _record_dictionary(record, "directional_shadow")
	shadow["softness"] = _get_spin_box_value(SHADOW_SOFTNESS_FIELD) if field_controls.has(SHADOW_SOFTNESS_FIELD) else 0.0
	shadow["solar"] = {
		"rotate_with_day": _get_check_box_pressed("shadow_solar_rotate"),
		"fade_with_night": _get_check_box_pressed("shadow_solar_fade"),
		"morning_direction_degrees": _get_spin_box_value("shadow_solar_morning"),
		"evening_direction_degrees": _get_spin_box_value("shadow_solar_evening"),
	}
	shadow["local_lights"] = {
		"enabled": _get_check_box_pressed("shadow_local_enabled"),
		"opacity_multiplier": _get_spin_box_value("shadow_local_opacity"),
		"stretch": _get_spin_box_value("shadow_local_stretch"),
		"distance_falloff": _get_spin_box_value("shadow_local_falloff"),
		"max_emitters_per_caster": _get_spin_box_int("shadow_local_max_emitters"),
		"maximum_mask_weight": 0.32,
		"reference_energy": 1.0,
		"update_interval": 0.10,
	}
	record["directional_shadow"] = shadow
	return record


func _build_post_effects_form() -> void:
	super._build_post_effects_form()
	if _selected_post_effect_group != "world_occlusion":
		return
	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var occlusion := _record_dictionary(world_visuals, "occlusion")
	_add_float_spin_box("Occluded Element Alpha", OCCLUSION_ALPHA_FIELD, float(occlusion.get("default_alpha", occlusion.get("tree_alpha", 0.38))), 0.05, 1.0, 0.01)
	var control: Variant = field_controls.get(OCCLUSION_ALPHA_FIELD)
	var row := _top_level_form_child(control)
	if row != null:
		row.visible = true
		form_container.move_child(row, mini(2, form_container.get_child_count() - 1))
	if control is Control:
		(control as Control).tooltip_text = "Opacity used by every element whose sprite allows player occlusion."


func _get_post_effects_record() -> Dictionary:
	var record := super._get_post_effects_record()
	if not field_controls.has(OCCLUSION_ALPHA_FIELD):
		return record
	var world_visuals := _record_dictionary(record, "world_visuals")
	var occlusion := _record_dictionary(world_visuals, "occlusion")
	occlusion["default_alpha"] = _get_spin_box_value(OCCLUSION_ALPHA_FIELD)
	world_visuals["occlusion"] = occlusion
	record["world_visuals"] = world_visuals
	return record
