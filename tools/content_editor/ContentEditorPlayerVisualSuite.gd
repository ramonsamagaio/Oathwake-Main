extends "res://tools/content_editor/ContentEditorLightingSuite.gd"


func _build_monster_form() -> void:
	super._build_monster_form()
	# Keep legacy per-monster shadow data compatible, but hide its scattered
	# controls. Projection shape and intensity now live in World Shadows.
	for field_name in [
		"content_shadow_enabled",
		"content_shadow_opacity",
		"content_shadow_offset_x",
		"content_shadow_offset_y",
		"content_shadow_scale_x",
		"content_shadow_scale_y",
		"content_shadow_z",
	]:
		var control: Variant = field_controls.get(field_name)
		if control is Control and (control as Control).get_parent() is Control:
			((control as Control).get_parent() as Control).visible = false
	for child in form_container.get_children():
		if child is Label and (child as Label).text == "Ground Shadow":
			(child as Label).visible = false


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Visual Calibration")
	var note := Label.new()
	note.text = "These values affect only the player artwork. Collision, movement speed and world position stay unchanged. Depth uses the player's ground line. Global projected shadows now live in the separate World Shadows tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box("Visual Scale", "player_visual_scale", float(current_record.get("visual_scale", 1.0)), 0.10, 8.0, 0.05)
	_add_float_spin_box("Visual Offset X", "player_visual_offset_x", float(current_record.get("visual_offset_x", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Visual Offset Y", "player_visual_offset_y", float(current_record.get("visual_offset_y", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Depth Sort Offset Y", "player_depth_sort_offset_y", float(current_record.get("depth_sort_offset_y", 0.0)), -512.0, 512.0, 0.5)

	var light := _record_dictionary(current_record, "light")
	var light_offset := _dictionary_vector(light, "offset", Vector2(0.0, 6.0))
	_add_subsection_title("Player Light")
	var light_note := Label.new()
	light_note.text = "Small light around the active player. Aura controls the visible circle; Emission and Radius control the real PointLight2D."
	light_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(light_note)
	_add_check_box("Player Light Enabled", "player_light_enabled", bool(light.get("enabled", true)))
	_add_check_box("Visible Aura Enabled", "player_light_visual_aura", bool(light.get("visual_aura_enabled", true)))
	_add_content_color_picker("Light Color", "player_light_color", _color_from_value(light.get("color", "#AFCBFFFF"), Color(0.69, 0.80, 1.0, 1.0)))
	_add_float_spin_box("Aura Intensity", "player_light_aura_intensity", float(light.get("aura_intensity", 0.75)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "player_light_aura_alpha", float(light.get("aura_alpha", 0.30)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Size", "player_light_aura_scale", float(light.get("aura_scale", 0.44)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Aura Blur / Softness", "player_light_blur", float(light.get("blur", 1.25)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Emission", "player_light_emission", float(light.get("emission", 0.85)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius", "player_light_radius", float(light.get("radius_scale", 1.20)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Day Multiplier", "player_light_day", float(light.get("day_multiplier", 0.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Multiplier", "player_light_night", float(light.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Light Offset X", "player_light_offset_x", light_offset.x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Light Offset Y", "player_light_offset_y", light_offset.y, -512.0, 512.0, 0.5)


func _get_player_tuning_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	var base_record := super._get_player_tuning_form_record()
	for key in base_record.keys():
		record[key] = base_record[key]
	record["visual_scale"] = _get_spin_box_value("player_visual_scale")
	record["visual_offset_x"] = _get_spin_box_value("player_visual_offset_x")
	record["visual_offset_y"] = _get_spin_box_value("player_visual_offset_y")
	record["depth_sort_offset_y"] = _get_spin_box_value("player_depth_sort_offset_y")
	record["light"] = {
		"enabled": _get_check_box_pressed("player_light_enabled"),
		"visual_aura_enabled": _get_check_box_pressed("player_light_visual_aura"),
		"color": _get_content_color_html("player_light_color"),
		"aura_intensity": _get_spin_box_value("player_light_aura_intensity"),
		"aura_alpha": _get_spin_box_value("player_light_aura_alpha"),
		"aura_scale": _get_spin_box_value("player_light_aura_scale"),
		"blur": _get_spin_box_value("player_light_blur"),
		"emission": _get_spin_box_value("player_light_emission"),
		"radius_scale": _get_spin_box_value("player_light_radius"),
		"day_multiplier": _get_spin_box_value("player_light_day"),
		"night_multiplier": _get_spin_box_value("player_light_night"),
		"offset": {
			"x": _get_spin_box_value("player_light_offset_x"),
			"y": _get_spin_box_value("player_light_offset_y"),
		},
	}
	return record


func _build_character_form() -> void:
	super._build_character_form()
	_add_subsection_title("Attack Animation Variation")
	var note := Label.new()
	note.text = "Comma-separated animation names. Use {direction} to resolve the current facing direction, for example attack_{direction}. A shuffle bag cycles compatible animations without immediate repetition."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_line_edit("Attack Animation Variants", "character_attack_variants", _join_string_array(current_record.get("attack_animation_variants", []), ", "))
	_add_check_box("Avoid Immediate Repeat", "character_avoid_attack_repeat", bool(current_record.get("avoid_immediate_attack_repeat", true)))


func _get_character_form_record() -> Dictionary:
	var record := super._get_character_form_record()
	record["attack_animation_variants"] = _split_string_list(_get_line_edit_text("character_attack_variants"))
	record["avoid_immediate_attack_repeat"] = _get_check_box_pressed("character_avoid_attack_repeat")
	return record


func _build_resource_form() -> void:
	super._build_resource_form()
	var collision := _record_dictionary(current_record, "collision")
	_add_subsection_title("Resource Collision")
	var collision_note := Label.new()
	collision_note.text = "When enabled, the player and wildlife may cross this resource. Small foliage bends from its grounded base when a character brushes through it."
	collision_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(collision_note)
	_add_check_box("Player Can Pass Through (contact rustle)", "resource_player_pass_through", bool(collision.get("player_pass_through", false)))
	var depth := _record_dictionary(current_record, "depth_sort")
	_add_subsection_title("World Depth Line")
	var depth_note := Label.new()
	depth_note.text = "The player changes from behind to in front when the player's feet cross this vertical ratio inside the resource sprite. 0.50 is the exact middle; 0.58 is slightly below it."
	depth_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(depth_note)
	_add_float_spin_box("Depth Line Ratio", "resource_depth_line_ratio", float(depth.get("line_ratio", 0.58)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Depth Offset Y", "resource_depth_offset_y", float(depth.get("offset_y", 0.0)), -512.0, 512.0, 0.5)

	var layered := _record_dictionary(current_record, "layered_visual")
	_add_subsection_title("Layered Tree Backend")
	var layered_note := Label.new()
	layered_note.text = "Prepared backend only. Nothing changes in the current map until Layered Visual Enabled is saved for a resource. Trunk stays rigid; canopy can receive wind independently."
	layered_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(layered_note)
	_add_check_box("Layered Visual Enabled", "resource_layered_enabled", bool(layered.get("enabled", false)))
	_add_line_edit("Trunk Sprite ID", "resource_layered_trunk_sprite_id", str(layered.get("trunk_sprite_id", "")))
	_add_line_edit("Canopy Sprite ID", "resource_layered_canopy_sprite_id", str(layered.get("canopy_sprite_id", "")))
	var trunk_offset := _dictionary_vector(layered, "trunk_offset", Vector2.ZERO)
	var canopy_offset := _dictionary_vector(layered, "canopy_offset", Vector2.ZERO)
	_add_float_spin_box("Trunk Offset X", "resource_layered_trunk_offset_x", trunk_offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Trunk Offset Y", "resource_layered_trunk_offset_y", trunk_offset.y, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Canopy Offset X", "resource_layered_canopy_offset_x", canopy_offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Canopy Offset Y", "resource_layered_canopy_offset_y", canopy_offset.y, -1024.0, 1024.0, 0.5)
	_add_spin_box("Canopy Z Offset", "resource_layered_canopy_z", int(layered.get("canopy_z_offset", 2)), -64, 64, 1)
	_add_check_box("Canopy Wind Enabled", "resource_layered_canopy_wind", bool(layered.get("canopy_wind_enabled", true)))


func _get_resource_form_record() -> Dictionary:
	var record := super._get_resource_form_record()
	var collision := _record_dictionary(record, "collision")
	collision["player_pass_through"] = _get_check_box_pressed("resource_player_pass_through")
	record["collision"] = collision
	record["depth_sort"] = {
		"line_ratio": _get_spin_box_value("resource_depth_line_ratio"),
		"offset_y": _get_spin_box_value("resource_depth_offset_y"),
	}
	record["layered_visual"] = {
		"enabled": _get_check_box_pressed("resource_layered_enabled"),
		"trunk_sprite_id": _get_line_edit_text("resource_layered_trunk_sprite_id"),
		"canopy_sprite_id": _get_line_edit_text("resource_layered_canopy_sprite_id"),
		"trunk_offset": {
			"x": _get_spin_box_value("resource_layered_trunk_offset_x"),
			"y": _get_spin_box_value("resource_layered_trunk_offset_y"),
		},
		"canopy_offset": {
			"x": _get_spin_box_value("resource_layered_canopy_offset_x"),
			"y": _get_spin_box_value("resource_layered_canopy_offset_y"),
		},
		"canopy_z_offset": _get_spin_box_int("resource_layered_canopy_z"),
		"canopy_wind_enabled": _get_check_box_pressed("resource_layered_canopy_wind"),
	}
	return record


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	var shadow := _record_dictionary(current_record, "directional_shadow")
	var direction := _dictionary_vector(shadow, "direction", Vector2(-1.0, 0.55))
	_add_subsection_title("Global Directional Shadow")
	_add_float_spin_box("Direction X", "global_shadow_direction_x", direction.x, -4.0, 4.0, 0.05)
	_add_float_spin_box("Direction Y", "global_shadow_direction_y", direction.y, -4.0, 4.0, 0.05)
	_add_float_spin_box("Default Opacity", "global_shadow_opacity", float(shadow.get("opacity", 0.32)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Length Scale", "global_shadow_length_scale", float(shadow.get("length_scale", 1.0)), 0.1, 8.0, 0.05)
	_add_float_spin_box("Width Scale", "global_shadow_width_scale", float(shadow.get("width_scale", 1.0)), 0.1, 8.0, 0.05)
	_add_float_spin_box("Fade Power", "global_shadow_fade_power", float(shadow.get("fade_power", 1.6)), 0.1, 8.0, 0.1)
	_add_line_edit("Shadow Color", "global_shadow_color", str(shadow.get("color", "#040306FF")))

	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var occlusion := _record_dictionary(world_visuals, "occlusion")
	var wind := _record_dictionary(world_visuals, "wind")
	var particles := _record_dictionary(world_visuals, "particles")
	var wind_direction := _dictionary_vector(wind, "direction", Vector2(1.0, 0.16))
	var particle_area := _dictionary_vector(particles, "area_size", Vector2(900.0, 520.0))
	_add_subsection_title("World Occlusion")
	_add_check_box("Occlusion Enabled", "world_occlusion_enabled", bool(occlusion.get("enabled", true)))
	_add_float_spin_box("Tree Hidden Alpha", "world_occlusion_tree_alpha", float(occlusion.get("tree_alpha", 0.38)), 0.05, 1.0, 0.01)
	_add_float_spin_box("Roof Hidden Alpha", "world_occlusion_roof_alpha", float(occlusion.get("roof_alpha", 0.30)), 0.05, 1.0, 0.01)
	_add_float_spin_box("Fade Speed", "world_occlusion_fade_speed", float(occlusion.get("fade_speed", 5.5)), 0.1, 30.0, 0.1)
	_add_float_spin_box("Horizontal Coverage", "world_occlusion_horizontal_ratio", float(occlusion.get("horizontal_ratio", 0.38)), 0.05, 1.5, 0.01)
	_add_float_spin_box("Vertical Coverage", "world_occlusion_vertical_ratio", float(occlusion.get("vertical_ratio", 0.78)), 0.1, 2.0, 0.01)

	_add_subsection_title("Shared World Wind")
	_add_check_box("Wind Enabled", "world_wind_enabled", bool(wind.get("enabled", true)))
	_add_float_spin_box("Wind Direction X", "world_wind_direction_x", wind_direction.x, -2.0, 2.0, 0.05)
	_add_float_spin_box("Wind Direction Y", "world_wind_direction_y", wind_direction.y, -2.0, 2.0, 0.05)
	_add_float_spin_box("Wind Strength", "world_wind_strength", float(wind.get("strength", 0.85)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Gust Strength", "world_wind_gust_strength", float(wind.get("gust_strength", 0.34)), 0.0, 1.5, 0.01)
	_add_float_spin_box("Gust Speed", "world_wind_gust_speed", float(wind.get("gust_speed", 0.42)), 0.01, 4.0, 0.01)
	_add_float_spin_box("Large Foliage Scale", "world_wind_large_scale", float(wind.get("large_amplitude_scale", 1.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Small Foliage Scale", "world_wind_small_scale", float(wind.get("small_amplitude_scale", 0.78)), 0.0, 4.0, 0.01)

	_add_subsection_title("Biome Ambient Particles")
	_add_check_box("Ambient Particles Enabled", "world_particles_enabled", bool(particles.get("enabled", true)))
	_add_spin_box("Pollen Count", "world_particles_pollen", int(particles.get("pollen_count", 22)), 0, 128, 1)
	_add_spin_box("Firefly Count", "world_particles_fireflies", int(particles.get("firefly_count", 8)), 0, 128, 1)
	_add_spin_box("Leaf Count", "world_particles_leaves", int(particles.get("leaf_count", 5)), 0, 128, 1)
	_add_float_spin_box("Particle Area Width", "world_particles_width", particle_area.x, 64.0, 4096.0, 16.0)
	_add_float_spin_box("Particle Area Height", "world_particles_height", particle_area.y, 64.0, 4096.0, 16.0)
	_add_float_spin_box("Day Particle Alpha", "world_particles_day_alpha", float(particles.get("day_alpha", 0.52)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Night Particle Alpha", "world_particles_night_alpha", float(particles.get("night_alpha", 0.86)), 0.0, 1.0, 0.01)
	_add_content_color_picker("Pollen Color", "world_particles_pollen_color", _color_from_value(particles.get("pollen_color", "#D8D19AFF"), Color(0.85, 0.82, 0.60, 1.0)))
	_add_content_color_picker("Firefly Color", "world_particles_firefly_color", _color_from_value(particles.get("firefly_color", "#FFE286FF"), Color(1.0, 0.89, 0.52, 1.0)))
	_add_content_color_picker("Leaf Color", "world_particles_leaf_color", _color_from_value(particles.get("leaf_color", "#758B4DFF"), Color(0.46, 0.55, 0.30, 1.0)))


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(record.get("id", "default")) == "default" and field_controls.has("global_shadow_direction_x"):
		record["directional_shadow"] = {
			"direction": {
				"x": _get_spin_box_value("global_shadow_direction_x"),
				"y": _get_spin_box_value("global_shadow_direction_y"),
			},
			"opacity": _get_spin_box_value("global_shadow_opacity"),
			"length_scale": _get_spin_box_value("global_shadow_length_scale"),
			"width_scale": _get_spin_box_value("global_shadow_width_scale"),
			"fade_power": _get_spin_box_value("global_shadow_fade_power"),
			"tail_width_ratio": 0.18,
			"color": _get_line_edit_text("global_shadow_color"),
		}
		record["world_visuals"] = {
			"enabled": true,
			"occlusion": {
				"enabled": _get_check_box_pressed("world_occlusion_enabled"),
				"tree_alpha": _get_spin_box_value("world_occlusion_tree_alpha"),
				"roof_alpha": _get_spin_box_value("world_occlusion_roof_alpha"),
				"fade_speed": _get_spin_box_value("world_occlusion_fade_speed"),
				"horizontal_ratio": _get_spin_box_value("world_occlusion_horizontal_ratio"),
				"vertical_ratio": _get_spin_box_value("world_occlusion_vertical_ratio"),
				"minimum_radius": 22.0,
				"front_margin": 8.0,
			},
			"wind": {
				"enabled": _get_check_box_pressed("world_wind_enabled"),
				"direction": {
					"x": _get_spin_box_value("world_wind_direction_x"),
					"y": _get_spin_box_value("world_wind_direction_y"),
				},
				"strength": _get_spin_box_value("world_wind_strength"),
				"gust_strength": _get_spin_box_value("world_wind_gust_strength"),
				"gust_speed": _get_spin_box_value("world_wind_gust_speed"),
				"large_amplitude_scale": _get_spin_box_value("world_wind_large_scale"),
				"small_amplitude_scale": _get_spin_box_value("world_wind_small_scale"),
			},
			"particles": {
				"enabled": _get_check_box_pressed("world_particles_enabled"),
				"area_size": {
					"x": _get_spin_box_value("world_particles_width"),
					"y": _get_spin_box_value("world_particles_height"),
				},
				"pollen_count": _get_spin_box_int("world_particles_pollen"),
				"firefly_count": _get_spin_box_int("world_particles_fireflies"),
				"leaf_count": _get_spin_box_int("world_particles_leaves"),
				"day_alpha": _get_spin_box_value("world_particles_day_alpha"),
				"night_alpha": _get_spin_box_value("world_particles_night_alpha"),
				"pollen_color": _get_content_color_html("world_particles_pollen_color"),
				"firefly_color": _get_content_color_html("world_particles_firefly_color"),
				"leaf_color": _get_content_color_html("world_particles_leaf_color"),
				"z_index": 3600,
			},
		}
	return record
