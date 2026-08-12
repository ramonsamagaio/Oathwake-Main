extends Node2D

const SlimeScript: Script = preload("res://scripts/creatures/ProceduralSlime.gd")
const SnakeScript: Script = preload("res://scripts/creatures/ProceduralSnake.gd")
const WispScript: Script = preload("res://scripts/creatures/ProceduralWisp.gd")
const CrawlerScript: Script = preload("res://scripts/creatures/ProceduralCrawler.gd")

const PRESET_PATH := "user://procedural_creature_presets.json"
const STAGE_CENTER := Vector2(760.0, 430.0)

var _creatures: Array[ProceduralCreature] = []
var _active: ProceduralCreature
var _stress_instances: Array[ProceduralCreature] = []
var _parameter_controls: Dictionary = {}
var _parameter_box: VBoxContainer
var _creature_selector: OptionButton
var _seed_box: SpinBox
var _pause_button: Button
var _status_label: Label
var _primary_picker: ColorPickerButton
var _secondary_picker: ColorPickerButton
var _accent_picker: ColorPickerButton
var _shadow_picker: ColorPickerButton
var _stress_count: int = 25
var _saved_presets: Dictionary = {}
var _fps_accum: float = 0.0


func _ready() -> void:
	_load_presets_from_disk()
	_build_stage()
	_spawn_reference_creatures()
	_build_ui()
	_select_creature(0)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		_refresh_status()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1600, 900)), Color("101619"), true)
	draw_rect(Rect2(Vector2(320, 105), Vector2(1240, 690)), Color("182126"), true)
	draw_rect(Rect2(Vector2(345, 130), Vector2(1190, 640)), Color("202c30"), true)
	draw_line(Vector2(360, 610), Vector2(1520, 610), Color("50615b"), 2.0, false)
	for x: int in range(380, 1520, 64):
		draw_line(Vector2(x, 600), Vector2(x, 620), Color(0.3, 0.38, 0.36, 0.28), 1.0, false)
	draw_string(ThemeDB.fallback_font, Vector2(355, 92), "PROCEDURAL CREATURE SYSTEM LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("c7d4c7"))


func _build_stage() -> void:
	var marker := Node2D.new()
	marker.name = "LODAnchor"
	marker.position = STAGE_CENTER
	add_child(marker)


func _spawn_reference_creatures() -> void:
	var scripts: Array[Script] = [SlimeScript, SnakeScript, WispScript, CrawlerScript]
	for script: Script in scripts:
		var creature: ProceduralCreature = script.new() as ProceduralCreature
		if creature == null:
			continue
		creature.position = STAGE_CENTER
		creature.visible = false
		creature.set_lod_anchor(get_node("LODAnchor") as Node2D)
		add_child(creature)
		_creatures.append(creature)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CreatureLabUI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(286, 864)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(258, 0)
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "CREATURE LAB"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pixel-native procedural monster authoring"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)
	root.add_child(HSeparator.new())

	_creature_selector = OptionButton.new()
	_creature_selector.add_item("Slime · Blob Spring")
	_creature_selector.add_item("Snake · Segment Chain")
	_creature_selector.add_item("Wisp · Field + Trail")
	_creature_selector.add_item("Crawler · Radial IK")
	_creature_selector.item_selected.connect(_select_creature)
	root.add_child(_creature_selector)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "LMB: push · RMB: pull · wheel: scale. Tune, stress-test, save presets, then reuse the solver in production monsters."
	root.add_child(help)
	root.add_child(HSeparator.new())

	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.custom_minimum_size.x = 48
	seed_row.add_child(seed_label)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 1
	_seed_box.max_value = 2147483000
	_seed_box.step = 1
	_seed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_box)
	var reseed_button := Button.new()
	reseed_button.text = "Reseed"
	reseed_button.pressed.connect(_on_reseed)
	seed_row.add_child(reseed_button)
	root.add_child(seed_row)

	var transport := HBoxContainer.new()
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.pressed.connect(_toggle_pause)
	transport.add_child(_pause_button)
	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.pressed.connect(_reset_active)
	transport.add_child(reset_button)
	var random_button := Button.new()
	random_button.text = "Randomize"
	random_button.pressed.connect(_randomize_active)
	transport.add_child(random_button)
	root.add_child(transport)

	var impulse_row := HBoxContainer.new()
	_add_impulse_button(impulse_row, "← Hit", Vector2(-180, -35))
	_add_impulse_button(impulse_row, "↑ Pop", Vector2(0, -220))
	_add_impulse_button(impulse_row, "Hit →", Vector2(180, -35))
	root.add_child(impulse_row)
	root.add_child(HSeparator.new())

	var params_title := Label.new()
	params_title.text = "LIVE PARAMETERS"
	params_title.add_theme_font_size_override("font_size", 15)
	root.add_child(params_title)
	_parameter_box = VBoxContainer.new()
	_parameter_box.add_theme_constant_override("separation", 4)
	root.add_child(_parameter_box)
	root.add_child(HSeparator.new())

	var palette_title := Label.new()
	palette_title.text = "PALETTE"
	root.add_child(palette_title)
	var palette_row := HBoxContainer.new()
	_primary_picker = _make_color_picker("Body", _on_palette_changed.bind("primary"))
	_secondary_picker = _make_color_picker("Shade", _on_palette_changed.bind("secondary"))
	_accent_picker = _make_color_picker("Accent", _on_palette_changed.bind("accent"))
	_shadow_picker = _make_color_picker("Dark", _on_palette_changed.bind("shadow"))
	for picker: ColorPickerButton in [_primary_picker, _secondary_picker, _accent_picker, _shadow_picker]:
		palette_row.add_child(picker)
	root.add_child(palette_row)
	root.add_child(HSeparator.new())

	var preset_title := Label.new()
	preset_title.text = "PRESETS"
	root.add_child(preset_title)
	var preset_row := HBoxContainer.new()
	_add_action_button(preset_row, "Save", _save_current_preset)
	_add_action_button(preset_row, "Load", _load_current_preset)
	_add_action_button(preset_row, "Copy JSON", _copy_preset_json)
	root.add_child(preset_row)
	root.add_child(HSeparator.new())

	var perf_title := Label.new()
	perf_title.text = "PERFORMANCE / LOD"
	root.add_child(perf_title)
	var stress_row := HBoxContainer.new()
	var stress_selector := OptionButton.new()
	for count: int in [10, 25, 50, 100, 200]:
		stress_selector.add_item("%d clones" % count)
		stress_selector.set_item_metadata(stress_selector.item_count - 1, count)
	stress_selector.selected = 1
	stress_selector.item_selected.connect(_on_stress_count_selected.bind(stress_selector))
	stress_row.add_child(stress_selector)
	_add_action_button(stress_row, "Spawn", _spawn_stress_test)
	_add_action_button(stress_row, "Clear", _clear_stress_test)
	root.add_child(stress_row)

	var lod_toggle := CheckButton.new()
	lod_toggle.text = "Distance LOD enabled"
	lod_toggle.button_pressed = true
	lod_toggle.toggled.connect(_on_lod_toggled)
	root.add_child(lod_toggle)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _add_impulse_button(parent: HBoxContainer, text: String, impulse: Vector2) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_apply_named_impulse.bind(impulse))
	parent.add_child(button)


func _add_action_button(parent: HBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _make_color_picker(label_text: String, callback: Callable) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(54, 32)
	picker.tooltip_text = label_text
	picker.color_changed.connect(callback)
	return picker


func _select_creature(index: int) -> void:
	if index < 0 or index >= _creatures.size():
		return
	for creature: ProceduralCreature in _creatures:
		creature.visible = false
		creature.set_simulation_active(false)
	_active = _creatures[index]
	_active.position = STAGE_CENTER
	_active.visible = true
	_active.set_simulation_active(true)
	_seed_box.value = _active.random_seed
	_sync_palette()
	_rebuild_parameter_controls()
	_pause_button.text = "Pause"
	_clear_stress_test()
	_refresh_status()


func _rebuild_parameter_controls() -> void:
	for child: Node in _parameter_box.get_children():
		child.queue_free()
	_parameter_controls.clear()
	if _active == null:
		return
	for descriptor: Dictionary in _active.get_editor_schema():
		var key: StringName = StringName(descriptor.get("key", &""))
		var type_name: String = String(descriptor.get("type", "float"))
		if type_name == "bool":
			var toggle := CheckButton.new()
			toggle.text = String(descriptor.get("label", String(key)))
			toggle.button_pressed = bool(_active.get_parameter(key))
			toggle.toggled.connect(_on_bool_parameter_changed.bind(key))
			_parameter_box.add_child(toggle)
			_parameter_controls[key] = toggle
			continue

		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(descriptor.get("label", String(key)))
		label.custom_minimum_size.x = 108
		row.add_child(label)

		var slider := HSlider.new()
		slider.min_value = float(descriptor.get("min", 0.0))
		slider.max_value = float(descriptor.get("max", 1.0))
		slider.step = float(descriptor.get("step", 0.01))
		slider.value = float(_active.get_parameter(key))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_numeric_parameter_changed.bind(key))
		row.add_child(slider)

		var value_label := Label.new()
		value_label.text = _format_value(slider.value, type_name)
		value_label.custom_minimum_size.x = 44
		row.add_child(value_label)
		slider.set_meta("value_label", value_label)
		slider.set_meta("value_type", type_name)
		_parameter_box.add_child(row)
		_parameter_controls[key] = slider


func _on_numeric_parameter_changed(value: float, key: StringName) -> void:
	if _active == null:
		return
	var control: HSlider = _parameter_controls.get(key) as HSlider
	var type_name: String = "float"
	if control != null:
		type_name = String(control.get_meta("value_type", "float"))
		var label: Label = control.get_meta("value_label") as Label
		if label != null:
			label.text = _format_value(value, type_name)
	var applied_value: Variant = int(round(value)) if type_name == "int" else value
	_active.set_parameter(key, applied_value)


func _on_bool_parameter_changed(enabled: bool, key: StringName) -> void:
	if _active != null:
		_active.set_parameter(key, enabled)


func _format_value(value: float, type_name: String) -> String:
	return str(int(round(value))) if type_name == "int" else "%.2f" % value


func _on_reseed() -> void:
	if _active != null:
		_active.reseed(int(_seed_box.value))
		_seed_box.value = _active.random_seed


func _toggle_pause() -> void:
	if _active == null:
		return
	var next_state: bool = not _active.simulation_enabled
	_active.set_simulation_active(next_state)
	_pause_button.text = "Pause" if next_state else "Play"


func _reset_active() -> void:
	if _active == null:
		return
	_active.position = STAGE_CENTER
	_active.reseed(_active.random_seed)
	_active.set_simulation_active(true)
	_pause_button.text = "Pause"


func _randomize_active() -> void:
	if _active == null:
		return
	_active.reseed()
	_seed_box.value = _active.random_seed
	for descriptor: Dictionary in _active.get_editor_schema():
		var key: StringName = StringName(descriptor.get("key", &""))
		var type_name: String = String(descriptor.get("type", "float"))
		if type_name == "bool":
			continue
		var min_value: float = float(descriptor.get("min", 0.0))
		var max_value: float = float(descriptor.get("max", 1.0))
		var value: float = _active._rng.randf_range(min_value, max_value)
		if type_name == "int":
			value = round(value)
		_active.set_parameter(key, value)
	_rebuild_parameter_controls()


func _apply_named_impulse(impulse: Vector2) -> void:
	if _active != null:
		_active.apply_impulse(impulse)


func _on_palette_changed(color: Color, channel: String) -> void:
	if _active == null:
		return
	match channel:
		"primary": _active.primary_color = color
		"secondary": _active.secondary_color = color
		"accent": _active.accent_color = color
		"shadow": _active.shadow_color = color
	_active.queue_redraw()


func _sync_palette() -> void:
	if _active == null:
		return
	_primary_picker.color = _active.primary_color
	_secondary_picker.color = _active.secondary_color
	_accent_picker.color = _active.accent_color
	_shadow_picker.color = _active.shadow_color


func _preset_key() -> String:
	return String(_active.creature_id) if _active != null else "none"


func _save_current_preset() -> void:
	if _active == null:
		return
	_saved_presets[_preset_key()] = _active.make_preset()
	_write_presets_to_disk()
	_refresh_status("Preset saved")


func _load_current_preset() -> void:
	if _active == null:
		return
	var key: String = _preset_key()
	if not _saved_presets.has(key):
		_refresh_status("No saved preset for %s" % key)
		return
	var preset: Dictionary = _saved_presets[key] as Dictionary
	_active.apply_preset(preset)
	_seed_box.value = _active.random_seed
	_sync_palette()
	_rebuild_parameter_controls()
	_refresh_status("Preset loaded")


func _copy_preset_json() -> void:
	if _active == null:
		return
	DisplayServer.clipboard_set(JSON.stringify(_active.make_preset(), "\t"))
	_refresh_status("Preset JSON copied")


func _load_presets_from_disk() -> void:
	if not FileAccess.file_exists(PRESET_PATH):
		return
	var file: FileAccess = FileAccess.open(PRESET_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_saved_presets = parsed as Dictionary


func _write_presets_to_disk() -> void:
	var file: FileAccess = FileAccess.open(PRESET_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_saved_presets, "\t"))


func _on_stress_count_selected(index: int, selector: OptionButton) -> void:
	_stress_count = int(selector.get_item_metadata(index))


func _on_lod_toggled(enabled: bool) -> void:
	if _active != null:
		_active.set_parameter(&"lod_enabled", enabled)


func _spawn_stress_test() -> void:
	_clear_stress_test()
	if _active == null:
		return
	var script: Script = _active.get_script() as Script
	if script == null:
		return
	var preset: Dictionary = _active.make_preset()
	for _i: int in range(_stress_count):
		var clone: ProceduralCreature = script.new() as ProceduralCreature
		if clone == null:
			continue
		clone.apply_preset(preset)
		clone.global_scale_factor *= randf_range(0.75, 1.15)
		clone.position = Vector2(randf_range(390.0, 1500.0), randf_range(180.0, 730.0))
		clone.set_lod_anchor(get_node("LODAnchor") as Node2D)
		add_child(clone)
		_stress_instances.append(clone)
	_active.visible = false
	_refresh_status("Stress test spawned")


func _clear_stress_test() -> void:
	for creature: ProceduralCreature in _stress_instances:
		if is_instance_valid(creature):
			creature.queue_free()
	_stress_instances.clear()
	if _active != null:
		_active.visible = true
	_refresh_status()


func _refresh_status(message: String = "") -> void:
	if _status_label == null:
		return
	var prefix: String = (message + "\n") if not message.is_empty() else ""
	var active_name: String = String(_active.creature_id) if _active != null else "none"
	var sim_state: String = "ON" if _active != null and _active.simulation_enabled else "OFF"
	_status_label.text = prefix + "FPS: %d  |  procedural: %d\nActive: %s  |  sim: %s\nPreset file: %s" % [
		Engine.get_frames_per_second(),
		_stress_instances.size() + (1 if _active != null else 0),
		active_name,
		sim_state,
		PRESET_PATH,
	]


func _unhandled_input(event: InputEvent) -> void:
	if _active == null or not _active.visible:
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.position.x < 320.0:
		return
	var direction: Vector2 = (_active.position - mouse_event.position).normalized()
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			_active.apply_impulse(direction * 220.0 + Vector2(0, -35))
		MOUSE_BUTTON_RIGHT:
			_active.apply_impulse(-direction * 180.0)
		MOUSE_BUTTON_WHEEL_UP:
			_active.set_parameter(&"global_scale_factor", _active.global_scale_factor + 0.05)
			_rebuild_parameter_controls()
		MOUSE_BUTTON_WHEEL_DOWN:
			_active.set_parameter(&"global_scale_factor", _active.global_scale_factor - 0.05)
			_rebuild_parameter_controls()
