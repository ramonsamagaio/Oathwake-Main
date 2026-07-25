extends "res://tools/content_editor/ContentEditorPostProcessSuite.gd"


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var fog := _record_dictionary(world_visuals, "layered_fog")
	var shafts := _record_dictionary(world_visuals, "light_shafts")
	var water := _record_dictionary(world_visuals, "water")
	var micro := _record_dictionary(world_visuals, "micro_motion")

	_add_subsection_title("Layered World Fog")
	var fog_note := Label.new()
	fog_note.text = "One procedural pass combines broad mist, low ground ribbons, a middle depth band and distant haze. Day and night multipliers keep the atmosphere readable."
	fog_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(fog_note)
	_add_check_box("Layered Fog Enabled", "env_fog_enabled", bool(fog.get("enabled", true)))
	_add_content_color_picker("Fog Color", "env_fog_color", _color_from_value(fog.get("color", "#9EADB829"), Color(0.62, 0.68, 0.72, 0.16)))
	_add_float_spin_box("Base Density", "env_fog_density", float(fog.get("density", 0.42)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Coverage", "env_fog_coverage", float(fog.get("coverage", 0.52)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Softness", "env_fog_softness", float(fog.get("softness", 0.26)), 0.01, 0.75, 0.01)
	_add_float_spin_box("Ground Mist Density", "env_fog_ground_density", float(fog.get("ground_density", 0.28)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Ground Mist Height", "env_fog_ground_height", float(fog.get("ground_height", 0.42)), 0.05, 1.0, 0.01)
	_add_float_spin_box("Middle Mist Density", "env_fog_middle_density", float(fog.get("middle_density", 0.16)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Depth Haze Density", "env_fog_depth_density", float(fog.get("depth_density", 0.08)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Day Fog Multiplier", "env_fog_day", float(fog.get("day_multiplier", 0.72)), 0.0, 3.0, 0.01)
	_add_float_spin_box("Night Fog Multiplier", "env_fog_night", float(fog.get("night_multiplier", 1.18)), 0.0, 3.0, 0.01)

	_add_subsection_title("Forest Light Shafts")
	var shaft_note := Label.new()
	shaft_note.text = "Broad, low-alpha beams remain below the HUD and fade almost completely at night. They are world anchored so camera movement does not turn them into wallpaper."
	shaft_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(shaft_note)
	_add_check_box("Light Shafts Enabled", "env_shafts_enabled", bool(shafts.get("enabled", true)))
	_add_content_color_picker("Shaft Color", "env_shafts_color", _color_from_value(shafts.get("color", "#FFE8A81C"), Color(1.0, 0.91, 0.66, 0.11)))
	_add_float_spin_box("Shaft Intensity", "env_shafts_intensity", float(shafts.get("intensity", 0.32)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Beam Count", "env_shafts_count", float(shafts.get("beam_count", 4.0)), 1.0, 12.0, 0.1)
	_add_float_spin_box("Beam Width", "env_shafts_width", float(shafts.get("beam_width", 0.22)), 0.02, 0.8, 0.01)
	_add_float_spin_box("Beam Softness", "env_shafts_softness", float(shafts.get("softness", 0.16)), 0.01, 0.5, 0.01)
	_add_float_spin_box("Drift Speed", "env_shafts_drift", float(shafts.get("drift_speed", 0.045)), 0.0, 2.0, 0.005)
	_add_float_spin_box("Day Shaft Multiplier", "env_shafts_day", float(shafts.get("day_multiplier", 1.0)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Night Shaft Multiplier", "env_shafts_night", float(shafts.get("night_multiplier", 0.08)), 0.0, 2.0, 0.01)

	_add_subsection_title("Water Surface")
	var water_note := Label.new()
	water_note.text = "Reusable top-down water for authored sprites, TileMapLayers and the WaterSurface2D scene. Names containing water, river, lake, pond or stream are wired automatically."
	water_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(water_note)
	_add_check_box("Water Effects Enabled", "env_water_enabled", bool(water.get("enabled", true)))
	_add_content_color_picker("Shallow Water", "env_water_shallow", _color_from_value(water.get("shallow_color", "#347184E0"), Color(0.20, 0.43, 0.53, 0.88)))
	_add_content_color_picker("Deep Water", "env_water_deep", _color_from_value(water.get("deep_color", "#14304FF0"), Color(0.08, 0.19, 0.30, 0.94)))
	_add_content_color_picker("Water Highlight", "env_water_highlight", _color_from_value(water.get("highlight_color", "#94D1E0B8"), Color(0.58, 0.82, 0.88, 0.72)))
	_add_float_spin_box("Flow Speed", "env_water_flow_speed", float(water.get("flow_speed", 0.36)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Ripple Scale", "env_water_ripple_scale", float(water.get("ripple_scale", 28.0)), 1.0, 96.0, 0.5)
	_add_float_spin_box("Ripple Strength", "env_water_ripple_strength", float(water.get("ripple_strength", 0.008)), 0.0, 0.08, 0.0005)
	_add_float_spin_box("Reflection Strength", "env_water_reflection", float(water.get("reflection_strength", 0.24)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Caustic Strength", "env_water_caustic", float(water.get("caustic_strength", 0.18)), 0.0, 1.0, 0.01)

	_add_subsection_title("Environmental Micro Motion")
	var micro_note := Label.new()
	micro_note.text = "Adds tiny wind-linked rotation and breathing scale to flowers, fungi, herbs and small bushes without changing collision, ground position or pixel assets."
	micro_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(micro_note)
	_add_check_box("Micro Motion Enabled", "env_micro_enabled", bool(micro.get("enabled", true)))
	_add_float_spin_box("Plant Rotation Degrees", "env_micro_rotation", float(micro.get("plant_rotation_degrees", 0.8)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Plant Scale Amount", "env_micro_plant_scale", float(micro.get("plant_scale_amount", 0.010)), 0.0, 0.20, 0.001)
	_add_float_spin_box("Flower Scale Amount", "env_micro_flower_scale", float(micro.get("flower_scale_amount", 0.024)), 0.0, 0.20, 0.001)
	_add_float_spin_box("Fungus Scale Amount", "env_micro_fungus_scale", float(micro.get("fungus_scale_amount", 0.018)), 0.0, 0.20, 0.001)
	_add_float_spin_box("Sway Speed", "env_micro_sway_speed", float(micro.get("sway_speed", 0.85)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Breathing Speed", "env_micro_breathe_speed", float(micro.get("breathe_speed", 0.72)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Wind Influence", "env_micro_wind", float(micro.get("wind_influence", 0.55)), 0.0, 4.0, 0.01)


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(record.get("id", "default")) != "default" or not field_controls.has("env_fog_enabled"):
		return record
	var world_visuals := _record_dictionary(record, "world_visuals")
	world_visuals["layered_fog"] = {
		"enabled": _get_check_box_pressed("env_fog_enabled"),
		"color": _get_content_color_html("env_fog_color"),
		"density": _get_spin_box_value("env_fog_density"),
		"speed": {"x": 0.018, "y": 0.007},
		"scale": 3.25,
		"coverage": _get_spin_box_value("env_fog_coverage"),
		"softness": _get_spin_box_value("env_fog_softness"),
		"detail_mix": 0.42,
		"world_anchor_strength": 1.0,
		"ground_density": _get_spin_box_value("env_fog_ground_density"),
		"ground_height": _get_spin_box_value("env_fog_ground_height"),
		"ground_scale": 5.2,
		"ground_speed": {"x": -0.010, "y": 0.004},
		"middle_density": _get_spin_box_value("env_fog_middle_density"),
		"middle_band_center": 0.56,
		"middle_band_width": 0.40,
		"depth_density": _get_spin_box_value("env_fog_depth_density"),
		"depth_falloff": 1.35,
		"day_multiplier": _get_spin_box_value("env_fog_day"),
		"night_multiplier": _get_spin_box_value("env_fog_night"),
	}
	world_visuals["light_shafts"] = {
		"enabled": _get_check_box_pressed("env_shafts_enabled"),
		"color": _get_content_color_html("env_shafts_color"),
		"direction": {"x": -0.38, "y": 1.0},
		"intensity": _get_spin_box_value("env_shafts_intensity"),
		"beam_count": _get_spin_box_value("env_shafts_count"),
		"beam_width": _get_spin_box_value("env_shafts_width"),
		"softness": _get_spin_box_value("env_shafts_softness"),
		"drift_speed": _get_spin_box_value("env_shafts_drift"),
		"noise_strength": 0.28,
		"world_anchor_strength": 0.65,
		"day_multiplier": _get_spin_box_value("env_shafts_day"),
		"night_multiplier": _get_spin_box_value("env_shafts_night"),
	}
	world_visuals["water"] = {
		"enabled": _get_check_box_pressed("env_water_enabled"),
		"shallow_color": _get_content_color_html("env_water_shallow"),
		"deep_color": _get_content_color_html("env_water_deep"),
		"highlight_color": _get_content_color_html("env_water_highlight"),
		"flow_direction": {"x": 1.0, "y": 0.18},
		"flow_speed": _get_spin_box_value("env_water_flow_speed"),
		"ripple_scale": _get_spin_box_value("env_water_ripple_scale"),
		"ripple_strength": _get_spin_box_value("env_water_ripple_strength"),
		"reflection_strength": _get_spin_box_value("env_water_reflection"),
		"caustic_strength": _get_spin_box_value("env_water_caustic"),
		"edge_fade": 0.06,
	}
	world_visuals["micro_motion"] = {
		"enabled": _get_check_box_pressed("env_micro_enabled"),
		"plant_rotation_degrees": _get_spin_box_value("env_micro_rotation"),
		"plant_scale_amount": _get_spin_box_value("env_micro_plant_scale"),
		"flower_scale_amount": _get_spin_box_value("env_micro_flower_scale"),
		"fungus_scale_amount": _get_spin_box_value("env_micro_fungus_scale"),
		"sway_speed": _get_spin_box_value("env_micro_sway_speed"),
		"breathe_speed": _get_spin_box_value("env_micro_breathe_speed"),
		"wind_influence": _get_spin_box_value("env_micro_wind"),
	}
	record["world_visuals"] = world_visuals
	return record
