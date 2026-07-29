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
	_add_check_box(
		"Fade When Player Is Behind",
		SPRITE_OCCLUSION_FIELD,
		bool(current_record.get("fade_when_player_behind", true))
	)


func _get_sprite_form_record() -> Dictionary:
	var record := super._get_sprite_form_record()
	if field_controls.has(SPRITE_OCCLUSION_FIELD):
		record["fade_when_player_behind"] = _get_check_box_pressed(SPRITE_OCCLUSION_FIELD)
	return record


func _build_world_shadows_form() -> void:
	super._build_world_shadows_form()
	var shadow := _record_dictionary(current_record, "directional_shadow")
	_add_float_spin_box(
		"Diffusion / Blur",
		SHADOW_SOFTNESS_FIELD,
		float(shadow.get("softness", 0.0)),
		0.0,
		16.0,
		0.1
	)
	var control: Variant = field_controls.get(SHADOW_SOFTNESS_FIELD)
	if control is Control:
		(control as Control).tooltip_text = "Softens the final combined shadow mask. Zero preserves the current sharp pixel-art edge."


func _get_world_shadows_record() -> Dictionary:
	var record := super._get_world_shadows_record()
	var shadow := _record_dictionary(record, "directional_shadow")
	shadow["softness"] = _get_spin_box_value(SHADOW_SOFTNESS_FIELD) if field_controls.has(SHADOW_SOFTNESS_FIELD) else 0.0
	record["directional_shadow"] = shadow
	return record


func _build_post_effects_form() -> void:
	super._build_post_effects_form()
	if _selected_post_effect_group != "world_occlusion":
		return
	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var occlusion := _record_dictionary(world_visuals, "occlusion")
	_add_float_spin_box(
		"Occluded Element Alpha",
		OCCLUSION_ALPHA_FIELD,
		float(occlusion.get("default_alpha", occlusion.get("tree_alpha", 0.38))),
		0.05,
		1.0,
		0.01
	)
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
