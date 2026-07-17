extends "res://tools/content_editor/ContentEditorEnhanced.gd"

const ShaderContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const OUTLINE_SETTINGS_PATH := "res://scenes/effects/settings/WorldItemOutlineSettings.tscn"
const FOLIAGE_SETTINGS_PATH := "res://scenes/effects/settings/FoliageWindSettings.tscn"
const SCREEN_SETTINGS_PATH := "res://scenes/effects/settings/ScreenEffectsSettings.tscn"

var shader_window: Window
var shader_tabs: TabContainer
var shader_fields: Dictionary = {}
var shader_status_label: Label
var foliage_resource_picker: OptionButton
var foliage_large_list: ItemList
var foliage_small_list: ItemList
var foliage_large_ids: Array[String] = []
var foliage_small_ids: Array[String] = []

var outline_settings_node: Node
var foliage_settings_node: Node
var screen_settings_node: Node


func _ready() -> void:
	super._ready()
	call_deferred("_install_scene_shader_editor")


func _install_scene_shader_editor() -> void:
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		push_warning("ContentEditorShaderSuite could not find the sidebar.")
		return
	if sidebar.get_node_or_null("SceneShaderEffectsButton") != null:
		return

	var button := Button.new()
	button.name = "SceneShaderEffectsButton"
	button.text = "Scene Shader Effects"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_open_scene_shader_editor)
	sidebar.add_child(button)
	_build_scene_shader_window()


func _build_scene_shader_window() -> void:
	if shader_window != null:
		return

	shader_window = Window.new()
	shader_window.title = "Oathwake Scene Shader Effects"
	shader_window.size = Vector2i(1180, 820)
	shader_window.min_size = Vector2i(980, 700)
	shader_window.close_requested.connect(shader_window.hide)
	add_child(shader_window)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	shader_window.add_child(root)

	var intro := Label.new()
	intro.text = "These controls edit real .tscn settings scenes. The same settings remain visible and editable in the normal Godot Inspector."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)

	shader_tabs = TabContainer.new()
	shader_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shader_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(shader_tabs)

	_build_outline_tab()
	_build_foliage_tab()
	_build_dash_tab()
	_build_glow_tab()
	_build_fog_tab()

	var actions := HBoxContainer.new()
	root.add_child(actions)
	_add_shader_button(actions, "Reload Scene Settings", _load_scene_shader_settings)
	_add_shader_button(actions, "Save Scene Settings", _save_scene_shader_settings)

	shader_status_label = Label.new()
	shader_status_label.text = "Open this window to load the current scene values."
	shader_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shader_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(shader_status_label)


func _build_outline_tab() -> void:
	var form := _make_shader_tab("World Item Outline")
	_add_shader_note(form, "Scene: %s\nInstanced visibly inside scenes/items/WorldItem.tscn as OutlineSettings." % OUTLINE_SETTINGS_PATH)
	shader_fields["outline_enabled"] = _add_shader_check(form, "Enabled", true)
	shader_fields["outline_color"] = _add_shader_color(form, "Line Color", Color(0.08, 0.06, 0.04, 0.95))
	shader_fields["outline_size"] = _add_shader_spin(form, "Line Thickness", 0.0, 0.2, 0.001, 0.018)
	shader_fields["outline_alpha_threshold"] = _add_shader_spin(form, "Alpha Threshold", 0.0, 1.0, 0.05, 0.5)
	shader_fields["outline_samples"] = _add_shader_spin(form, "Corner Samples", 4.0, 32.0, 1.0, 12.0)


func _build_foliage_tab() -> void:
	var form := _make_shader_tab("Foliage Wind")
	_add_shader_note(form, "Scene: %s\nThe selected resource IDs are assigned to either large vegetation or small vegetation." % FOLIAGE_SETTINGS_PATH)
	shader_fields["foliage_enabled"] = _add_shader_check(form, "Enabled", true)

	_add_shader_heading(form, "Shared Wind")
	shader_fields["foliage_time_scale"] = _add_shader_spin(form, "Wind Speed", 0.0, 5.0, 0.01, 0.2)
	shader_fields["foliage_noise_scale"] = _add_shader_spin(form, "World Noise Scale", 0.0001, 2.0, 0.0001, 0.004)
	shader_fields["foliage_render_noise"] = _add_shader_check(form, "Render Noise Debug", false)

	_add_shader_heading(form, "Large Vegetation")
	shader_fields["foliage_large_amplitude"] = _add_shader_spin(form, "Large Intensity", 0.0, 0.5, 0.005, 0.075)
	shader_fields["foliage_large_rotation"] = _add_shader_spin(form, "Large Rotation Strength", 0.0, 5.0, 0.05, 1.0)
	shader_fields["foliage_large_pivot_x"] = _add_shader_spin(form, "Large Pivot X", 0.0, 1.0, 0.01, 0.5)
	shader_fields["foliage_large_pivot_y"] = _add_shader_spin(form, "Large Pivot Y", 0.0, 1.0, 0.01, 1.0)

	_add_shader_heading(form, "Small Vegetation")
	shader_fields["foliage_small_amplitude"] = _add_shader_spin(form, "Small Intensity", 0.0, 0.5, 0.005, 0.12)
	shader_fields["foliage_small_rotation"] = _add_shader_spin(form, "Small Rotation Strength", 0.0, 5.0, 0.05, 1.35)
	shader_fields["foliage_small_pivot_x"] = _add_shader_spin(form, "Small Pivot X", 0.0, 1.0, 0.01, 0.5)
	shader_fields["foliage_small_pivot_y"] = _add_shader_spin(form, "Small Pivot Y", 0.0, 1.0, 0.01, 1.0)

	_add_shader_heading(form, "Resource Assignment")
	foliage_resource_picker = OptionButton.new()
	_populate_foliage_resource_picker()
	_add_shader_row(form, "Map Resource", foliage_resource_picker)

	var add_actions := HBoxContainer.new()
	form.add_child(add_actions)
	_add_shader_button(add_actions, "Add to Large", Callable(self, "_add_selected_foliage_resource").bind("large"))
	_add_shader_button(add_actions, "Add to Small", Callable(self, "_add_selected_foliage_resource").bind("small"))

	var lists := HSplitContainer.new()
	lists.custom_minimum_size = Vector2(0, 300)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(lists)

	var large_box := VBoxContainer.new()
	large_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(large_box)
	_add_shader_heading(large_box, "Large Vegetation Resource IDs")
	foliage_large_list = ItemList.new()
	foliage_large_list.select_mode = ItemList.SELECT_MULTI
	foliage_large_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foliage_large_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	large_box.add_child(foliage_large_list)
	_add_shader_button(large_box, "Remove Selected Large", Callable(self, "_remove_selected_foliage_resources").bind("large"))

	var small_box := VBoxContainer.new()
	small_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(small_box)
	_add_shader_heading(small_box, "Small Vegetation Resource IDs")
	foliage_small_list = ItemList.new()
	foliage_small_list.select_mode = ItemList.SELECT_MULTI
	foliage_small_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foliage_small_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	small_box.add_child(foliage_small_list)
	_add_shader_button(small_box, "Remove Selected Small", Callable(self, "_remove_selected_foliage_resources").bind("small"))


func _build_dash_tab() -> void:
	var form := _make_shader_tab("Dash Speed Lines")
	_add_shader_note(form, "Scene: %s\nInstanced visibly inside Player.tscn through ScreenEffects." % SCREEN_SETTINGS_PATH)
	shader_fields["dash_enabled"] = _add_shader_check(form, "Enabled", true)
	shader_fields["dash_color"] = _add_shader_color(form, "Line Color", Color(0.72, 0.88, 1.0, 0.12))
	shader_fields["dash_line_count"] = _add_shader_spin(form, "Line Count", 0.05, 2.0, 0.05, 0.45)
	shader_fields["dash_density"] = _add_shader_spin(form, "Line Density", 0.0, 1.0, 0.01, 0.18)
	shader_fields["dash_falloff"] = _add_shader_spin(form, "Line Falloff", 0.0, 1.0, 0.01, 0.2)
	shader_fields["dash_mask_size"] = _add_shader_spin(form, "Center Mask Size", 0.0, 1.0, 0.01, 0.18)
	shader_fields["dash_mask_edge"] = _add_shader_spin(form, "Mask Edge", 0.0, 1.0, 0.01, 0.72)
	shader_fields["dash_animation_speed"] = _add_shader_spin(form, "Animation Speed", 0.1, 20.0, 0.1, 7.0)
	shader_fields["dash_duration"] = _add_shader_spin(form, "Visible Duration", 0.02, 1.0, 0.01, 0.16)


func _build_glow_tab() -> void:
	var form := _make_shader_tab("Gaussian Glow")
	_add_shader_note(form, "Scene: %s\nThis is a Godot 4 screen-reading adaptation. High sample values can be expensive." % SCREEN_SETTINGS_PATH)
	shader_fields["glow_enabled"] = _add_shader_check(form, "Enabled", true)
	shader_fields["glow_threshold"] = _add_shader_spin(form, "Bloom Threshold", 0.0, 2.0, 0.01, 0.82)
	shader_fields["glow_intensity"] = _add_shader_spin(form, "Bloom Intensity", 0.0, 5.0, 0.01, 0.38)
	shader_fields["glow_iterations"] = _add_shader_spin(form, "Blur Iterations", 1.0, 4.0, 1.0, 1.0)
	shader_fields["glow_size"] = _add_shader_spin(form, "Blur Size", 0.0, 0.03, 0.0001, 0.0025)
	shader_fields["glow_subdivisions"] = _add_shader_spin(form, "Blur Subdivisions", 4.0, 16.0, 1.0, 8.0)
	shader_fields["glow_mix"] = _add_shader_spin(form, "Glow Mix", 0.0, 1.0, 0.01, 0.28)


func _build_fog_tab() -> void:
	var form := _make_shader_tab("Map Fog")
	_add_shader_heading(form, "Fog is edited per map")
	_add_shader_note(form, "Open a map scene and select its MapFogOverlay node. Toggle Effect Enabled or edit Density, Speed, Fog Color and Noise Texture directly in the Inspector.\n\nCurrent authored locations:\n• scenes/maps/StartArea.tscn / MapFogOverlay\n• scenes/Main.tscn / World / MapFogOverlay\n\nNew maps should instance scenes/effects/MapFogOverlay.tscn so every map keeps independent weather controls.")


func _open_scene_shader_editor() -> void:
	_load_scene_shader_settings()
	shader_window.popup_centered()


func _load_scene_shader_settings() -> void:
	_free_loaded_settings_nodes()
	outline_settings_node = _instantiate_settings_scene(OUTLINE_SETTINGS_PATH)
	foliage_settings_node = _instantiate_settings_scene(FOLIAGE_SETTINGS_PATH)
	screen_settings_node = _instantiate_settings_scene(SCREEN_SETTINGS_PATH)
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null:
		_set_shader_status("Could not load one or more settings scenes.", true)
		return
	_load_outline_fields()
	_load_foliage_fields()
	_load_screen_fields()
	_set_shader_status("Loaded the current values from the three .tscn settings scenes.")


func _instantiate_settings_scene(path: String) -> Node:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is PackedScene:
		return null
	return (resource as PackedScene).instantiate()


func _load_outline_fields() -> void:
	_set_check("outline_enabled", bool(outline_settings_node.get("effect_enabled")))
	_set_color("outline_color", outline_settings_node.get("outline_color"))
	_set_spin("outline_size", float(outline_settings_node.get("outline_size")))
	_set_spin("outline_alpha_threshold", float(outline_settings_node.get("alpha_threshold")))
	_set_spin("outline_samples", int(outline_settings_node.get("samples")))


func _load_foliage_fields() -> void:
	_set_check("foliage_enabled", bool(foliage_settings_node.get("effect_enabled")))
	_set_spin("foliage_time_scale", float(foliage_settings_node.get("time_scale")))
	_set_spin("foliage_noise_scale", float(foliage_settings_node.get("noise_scale")))
	_set_check("foliage_render_noise", bool(foliage_settings_node.get("render_noise_debug")))
	_set_spin("foliage_large_amplitude", float(foliage_settings_node.get("large_amplitude")))
	_set_spin("foliage_large_rotation", float(foliage_settings_node.get("large_rotation_strength")))
	var large_pivot: Vector2 = foliage_settings_node.get("large_rotation_pivot")
	_set_spin("foliage_large_pivot_x", large_pivot.x)
	_set_spin("foliage_large_pivot_y", large_pivot.y)
	_set_spin("foliage_small_amplitude", float(foliage_settings_node.get("small_amplitude")))
	_set_spin("foliage_small_rotation", float(foliage_settings_node.get("small_rotation_strength")))
	var small_pivot: Vector2 = foliage_settings_node.get("small_rotation_pivot")
	_set_spin("foliage_small_pivot_x", small_pivot.x)
	_set_spin("foliage_small_pivot_y", small_pivot.y)

	foliage_large_ids = _packed_string_array_to_array(foliage_settings_node.get("large_resource_ids"))
	foliage_small_ids = _packed_string_array_to_array(foliage_settings_node.get("small_resource_ids"))
	_refresh_foliage_lists()


func _load_screen_fields() -> void:
	_set_check("dash_enabled", bool(screen_settings_node.get("dash_lines_enabled")))
	_set_color("dash_color", screen_settings_node.get("dash_line_color"))
	_set_spin("dash_line_count", float(screen_settings_node.get("dash_line_count")))
	_set_spin("dash_density", float(screen_settings_node.get("dash_line_density")))
	_set_spin("dash_falloff", float(screen_settings_node.get("dash_line_falloff")))
	_set_spin("dash_mask_size", float(screen_settings_node.get("dash_mask_size")))
	_set_spin("dash_mask_edge", float(screen_settings_node.get("dash_mask_edge")))
	_set_spin("dash_animation_speed", float(screen_settings_node.get("dash_animation_speed")))
	_set_spin("dash_duration", float(screen_settings_node.get("dash_effect_duration")))
	_set_check("glow_enabled", bool(screen_settings_node.get("glow_enabled")))
	_set_spin("glow_threshold", float(screen_settings_node.get("bloom_threshold")))
	_set_spin("glow_intensity", float(screen_settings_node.get("bloom_intensity")))
	_set_spin("glow_iterations", int(screen_settings_node.get("blur_iterations")))
	_set_spin("glow_size", float(screen_settings_node.get("blur_size")))
	_set_spin("glow_subdivisions", int(screen_settings_node.get("blur_subdivisions")))
	_set_spin("glow_mix", float(screen_settings_node.get("glow_mix_amount")))


func _save_scene_shader_settings() -> void:
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null:
		_load_scene_shader_settings()
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null:
		return

	_capture_outline_fields()
	_capture_foliage_fields()
	_capture_screen_fields()

	var errors: Array[String] = []
	for entry in [
		{"path": OUTLINE_SETTINGS_PATH, "node": outline_settings_node},
		{"path": FOLIAGE_SETTINGS_PATH, "node": foliage_settings_node},
		{"path": SCREEN_SETTINGS_PATH, "node": screen_settings_node},
	]:
		var error := _save_settings_scene(str(entry["path"]), entry["node"])
		if not error.is_empty():
			errors.append(error)

	if not errors.is_empty():
		_set_shader_status("\n".join(errors), true)
		return
	_set_shader_status("Saved shader controls directly into the .tscn settings scenes.")


func _capture_outline_fields() -> void:
	outline_settings_node.set("effect_enabled", _get_check("outline_enabled"))
	outline_settings_node.set("outline_color", _get_color("outline_color"))
	outline_settings_node.set("outline_size", _get_spin("outline_size"))
	outline_settings_node.set("alpha_threshold", _get_spin("outline_alpha_threshold"))
	outline_settings_node.set("samples", int(_get_spin("outline_samples")))


func _capture_foliage_fields() -> void:
	foliage_settings_node.set("effect_enabled", _get_check("foliage_enabled"))
	foliage_settings_node.set("time_scale", _get_spin("foliage_time_scale"))
	foliage_settings_node.set("noise_scale", _get_spin("foliage_noise_scale"))
	foliage_settings_node.set("render_noise_debug", _get_check("foliage_render_noise"))
	foliage_settings_node.set("large_amplitude", _get_spin("foliage_large_amplitude"))
	foliage_settings_node.set("large_rotation_strength", _get_spin("foliage_large_rotation"))
	foliage_settings_node.set("large_rotation_pivot", Vector2(_get_spin("foliage_large_pivot_x"), _get_spin("foliage_large_pivot_y")))
	foliage_settings_node.set("small_amplitude", _get_spin("foliage_small_amplitude"))
	foliage_settings_node.set("small_rotation_strength", _get_spin("foliage_small_rotation"))
	foliage_settings_node.set("small_rotation_pivot", Vector2(_get_spin("foliage_small_pivot_x"), _get_spin("foliage_small_pivot_y")))
	foliage_settings_node.set("large_resource_ids", PackedStringArray(foliage_large_ids))
	foliage_settings_node.set("small_resource_ids", PackedStringArray(foliage_small_ids))


func _capture_screen_fields() -> void:
	screen_settings_node.set("dash_lines_enabled", _get_check("dash_enabled"))
	screen_settings_node.set("dash_line_color", _get_color("dash_color"))
	screen_settings_node.set("dash_line_count", _get_spin("dash_line_count"))
	screen_settings_node.set("dash_line_density", _get_spin("dash_density"))
	screen_settings_node.set("dash_line_falloff", _get_spin("dash_falloff"))
	screen_settings_node.set("dash_mask_size", _get_spin("dash_mask_size"))
	screen_settings_node.set("dash_mask_edge", _get_spin("dash_mask_edge"))
	screen_settings_node.set("dash_animation_speed", _get_spin("dash_animation_speed"))
	screen_settings_node.set("dash_effect_duration", _get_spin("dash_duration"))
	screen_settings_node.set("glow_enabled", _get_check("glow_enabled"))
	screen_settings_node.set("bloom_threshold", _get_spin("glow_threshold"))
	screen_settings_node.set("bloom_intensity", _get_spin("glow_intensity"))
	screen_settings_node.set("blur_iterations", int(_get_spin("glow_iterations")))
	screen_settings_node.set("blur_size", _get_spin("glow_size"))
	screen_settings_node.set("blur_subdivisions", int(_get_spin("glow_subdivisions")))
	screen_settings_node.set("glow_mix_amount", _get_spin("glow_mix"))


func _save_settings_scene(path: String, settings_node: Node) -> String:
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(settings_node)
	if pack_error != OK:
		return "Could not pack %s (error %d)." % [path, pack_error]
	var save_error := ResourceSaver.save(packed_scene, path)
	if save_error != OK:
		return "Could not save %s (error %d)." % [path, save_error]
	return ""


func _populate_foliage_resource_picker() -> void:
	if foliage_resource_picker == null:
		return
	foliage_resource_picker.clear()
	var records := data_store.get_records(ShaderContentEditorData.SECTION_RESOURCES)
	var sorted_records: Array = records.duplicate()
	sorted_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	for record in sorted_records:
		var resource_id := str(record.get("id", ""))
		if resource_id.is_empty():
			continue
		var display_name := str(record.get("display_name", resource_id))
		var index := foliage_resource_picker.item_count
		foliage_resource_picker.add_item("%s - %s" % [resource_id, display_name])
		foliage_resource_picker.set_item_metadata(index, resource_id)


func _add_selected_foliage_resource(size_class: String) -> void:
	if foliage_resource_picker == null or foliage_resource_picker.selected < 0:
		return
	var resource_id := str(foliage_resource_picker.get_item_metadata(foliage_resource_picker.selected))
	if resource_id.is_empty():
		return
	foliage_large_ids.erase(resource_id)
	foliage_small_ids.erase(resource_id)
	if size_class == "large":
		foliage_large_ids.append(resource_id)
	else:
		foliage_small_ids.append(resource_id)
	foliage_large_ids.sort()
	foliage_small_ids.sort()
	_refresh_foliage_lists()


func _remove_selected_foliage_resources(size_class: String) -> void:
	var list := foliage_large_list if size_class == "large" else foliage_small_list
	if list == null:
		return
	var selected := list.get_selected_items()
	var ids_to_remove: Array[String] = []
	for index in selected:
		ids_to_remove.append(str(list.get_item_metadata(index)))
	for resource_id in ids_to_remove:
		if size_class == "large":
			foliage_large_ids.erase(resource_id)
		else:
			foliage_small_ids.erase(resource_id)
	_refresh_foliage_lists()


func _refresh_foliage_lists() -> void:
	if foliage_large_list != null:
		foliage_large_list.clear()
		for resource_id in foliage_large_ids:
			var index := foliage_large_list.item_count
			foliage_large_list.add_item(_get_resource_display_label(resource_id))
			foliage_large_list.set_item_metadata(index, resource_id)
	if foliage_small_list != null:
		foliage_small_list.clear()
		for resource_id in foliage_small_ids:
			var index := foliage_small_list.item_count
			foliage_small_list.add_item(_get_resource_display_label(resource_id))
			foliage_small_list.set_item_metadata(index, resource_id)


func _get_resource_display_label(resource_id: String) -> String:
	if data_store.has_record(ShaderContentEditorData.SECTION_RESOURCES, resource_id):
		var record: Dictionary = data_store.get_record(ShaderContentEditorData.SECTION_RESOURCES, resource_id)
		return "%s - %s" % [resource_id, str(record.get("display_name", resource_id))]
	return resource_id


func _packed_string_array_to_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is PackedStringArray or value is Array:
		for entry in value:
			var text := str(entry)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	result.sort()
	return result


func _free_loaded_settings_nodes() -> void:
	for node in [outline_settings_node, foliage_settings_node, screen_settings_node]:
		if node != null and is_instance_valid(node):
			node.free()
	outline_settings_node = null
	foliage_settings_node = null
	screen_settings_node = null


func _make_shader_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shader_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	margin.add_child(form)
	return form


func _add_shader_row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _add_shader_check(parent: VBoxContainer, label_text: String, initial_value: bool) -> CheckBox:
	var check := CheckBox.new()
	check.button_pressed = initial_value
	_add_shader_row(parent, label_text, check)
	return check


func _add_shader_color(parent: VBoxContainer, label_text: String, initial_value: Color) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.color = initial_value
	picker.edit_alpha = true
	_add_shader_row(parent, label_text, picker)
	return picker


func _add_shader_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, initial_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial_value
	spin.allow_greater = false
	spin.allow_lesser = false
	_add_shader_row(parent, label_text, spin)
	return spin


func _add_shader_heading(parent: Container, text_value: String) -> void:
	var heading := Label.new()
	heading.text = text_value
	heading.add_theme_color_override("font_color", Color(0.95, 0.86, 0.62))
	parent.add_child(heading)


func _add_shader_note(parent: Container, text_value: String) -> void:
	var note := Label.new()
	note.text = text_value
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.82, 0.82, 0.86)
	parent.add_child(note)


func _add_shader_button(parent: Container, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _set_check(field_name: String, value: bool) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as CheckBox).button_pressed = value


func _get_check(field_name: String) -> bool:
	return (shader_fields[field_name] as CheckBox).button_pressed


func _set_color(field_name: String, value: Color) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as ColorPickerButton).color = value


func _get_color(field_name: String) -> Color:
	return (shader_fields[field_name] as ColorPickerButton).color


func _set_spin(field_name: String, value: float) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as SpinBox).value = value


func _get_spin(field_name: String) -> float:
	return (shader_fields[field_name] as SpinBox).value


func _set_shader_status(text_value: String, is_error := false) -> void:
	if shader_status_label == null:
		return
	shader_status_label.text = text_value
	shader_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color.WHITE
