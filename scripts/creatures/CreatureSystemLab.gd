extends Node2D

const SlimeScript := preload("res://scripts/creatures/ProceduralSlime.gd")
const SnakeScript := preload("res://scripts/creatures/ProceduralSnake.gd")
const WispScript := preload("res://scripts/creatures/ProceduralWisp.gd")
const CrawlerScript := preload("res://scripts/creatures/ProceduralCrawler.gd")

const PRESET_PATH := "user://procedural_creature_presets.json"
const STAGE_CENTER := Vector2(760, 430)

var _creatures: Array[ProceduralCreature] = []
var _active: ProceduralCreature
var _stress_instances: Array[ProceduralCreature] = []
var _parameter_controls: Dictionary = {}
var _panel: PanelContainer
var _parameter_box: VBoxContainer
var _creature_selector: OptionButton
var _seed_box: SpinBox
var _pause_button: Button
var _status_label: Label
var _help_label: Label
var _palette_row: HBoxContainer
var _primary_picker: ColorPickerButton
var _secondary_picker: ColorPickerButton
var _accent_picker: ColorPickerButton
var _shadow_picker: ColorPickerButton
var _stress_count := 25
var _saved_presets: Dictionary = {}
var _fps_accum := 0.0


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
	draw_rect(Rect2(Vector2(0, 0), Vector2(1600, 900)), Color("101619"), true)
	draw_rect(Rect2(Vector2(320, 105), Vector2(1240, 690)), Color("182126"), true)
	draw_rect(Rect2(Vector2(345, 130), Vector2(1190, 640)), Color("202c30"), true)
	draw_line(Vector2(360, 610), Vector2(1520, 610), Color("50615b"), 2.0, false)
	for x in range(380, 1520, 64):
		draw_line(Vector2(x, 600), Vector2(x, 620), Color(0.3, 0.38, 0.36, 0.28), 1.0, false)
	draw_string(ThemeDB.fallback_font, Vector2(355, 92), "PROCEDURAL CREATURE SYSTEM LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("c7d4c7"))


func _build_stage() -> void:
	var marker := Node2D.new()
	marker.name = "LODAnchor"
	marker.position = STAGE_CENTER
	add_child(marker)


func _spawn_reference_creatures() -> void:
	var scripts: Array[Script] = [SlimeScript, SnakeScript, WispScript, CrawlerScript]
	for script in scripts:
		var creature := script.new() as ProceduralCreature
		creature.position = STAGE_CENTER
		creature.visible = false
		creature.set_lod_anchor(get_node("LODAnchor"))
		add_child(creature)
		_creatures.append(creature)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CreatureLabUI"
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(18, 18)
	_panel.size = Vector2(286, 864)
	layer.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
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
	_help_label = Label.new()
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.text = "LMB on stage: push away from click. RMB: pull toward click. Mouse wheel: scale active creature."
	root.add_child(_help_label)
	root.add_child(HSeparator.new())
	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.custom_minimum_size.x = 58
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
	for item in [["← Hit", Vector2(-180, -35)], ["↑ Pop", Vector2(0, -220)], ["Hit →", Vector2(180, -35)]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(_apply_named_impulse.bind(item[1]))
		impulse_row.add_child(button)
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
	_palette_row = HBoxContainer.new()
	_primary_picker = _make_color_picker("Body", _on_palette_changed.bind("primary"))
	_secondary_picker = _make_color_picker("Shade", _on_palette_changed.bind("secondary"))
	_accent_picker = _make_color_picker("Accent", _on_palette_changed.bind("accent"))
	_shadow_picker = _make_color_picker("Dark", _on_palette_changed.bind("shadow"))
	for picker in [_primary_picker, _secondary_picker, _accent_picker, _shadow_picker]:
		_palette_row.add_child(picker)
	root.add_child(_palette_row)
	root.add_child(HSeparator.new())
	var preset_title := Label.new()
	preset_title.text = "PRESETS"
	root.add_child(preset_title)
	var preset_row := HBoxContainer.new()
	var save_button := Button.new()
	save_button.text = "Save Slot"
	save_button.pressed.connect(_save_current_preset)
	preset_row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load Slot"
	load_button.pressed.connect(_load_current_preset)
	preset_row.add_child(load_button)
	var copy_button := Button.new()
	copy_button.text = "Copy JSON"
	copy_button.pressed.connect(_copy_preset_json)
	preset_row.add_child(copy_button)
	root.add_child(preset_row)
	root.add_child(HSeparator.new())
	var stress_title := Label.new()
	stress_title.text = "PERFORMANCE / LOD"
	root.add_child(stress_title)
	var stress_row := HBoxContainer.new()
	var stress_selector := OptionButton.new()
	for count in [10, 25, 50, 100, 200]:
		stress_selector.add_item("%d clones" % count)
		stress_selector.set_item_metadata(stress_selector.item_count - 1, count)
	stress_selector.selected = 1
	stress_selector.item_selected.connect(func(index: int) -> void:
		_stress_count = int(stress_selector.get_item_metadata(index))
	)
	stress_row.add_child(stress_selector)
	var stress_button := Button.new()
	stress_button.text = "Spawn"
	stress_button.pressed.connect(_spawn_stress_test)
	stress_row.add_child(stress_button)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_clear_stress_test)
	stress_row.add_child(clear_button)
	root.add_child(stress_row)
	var lod_toggle := CheckButton.new()
	lod_toggle.text = "Distance LOD enabled"
	lod_toggle.button_pressed = true
	lod_toggle.toggled.connect(func(enabled: bool) -> void:
		if _active:
			_active.set_parameter(&"lod_enabled", enabled)
	)
	root.add_child(lod_toggle)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _make_color_picker(label_text: String, callback: Callable) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(54, 32)
	picker.tooltip_text = label_text
	picker.color_changed.connect(callback)
	return picker


func _select_creature(index: int) -> void:
	if index < 0 or index >= _creatures.size():
		return
	for creature in _creatures:
		creature.visible = false
		creature.set_simulation_active(false)
	_active = _creatures[index]
	_active.visible = true
	_active.position = STAGE_CENTER
	_active.set_simulation_active(true)
	_seed_box.value = _active.random_seed
	_sync_palette()
	_rebuild_parameter_controls()
	_pause_button.text = "Pause"
	_clear_stress_test()
	_refresh_status()


func _rebuild_parameter_controls() -> void:
	for child in _parameter_box.get_children():
		child.queue_free()
	_parameter_controls.clear()
	if _active == null:
		return
	for descriptor in _active.get_editor_schema():
		var key: StringName = descriptor.get("key", &"")
		var type_name := String(descriptor.get("type", "float"))
		if type_name == "bool":
			var toggle := CheckButton.new()
			toggle.text = String(descriptor.get("label", key))
			toggle.button_pressed = bool(_active.get_parameter(key))
			toggle.toggled.connect(_on_bool_parameter_changed.bind(key))
			_parameter_box.add_child(toggle)
			_parameter_controls[key] = toggle
		else:
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = String(descriptor.get("label", key))
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
	var control := _parameter_controls.get(key) as HSlider
	var type_name := "float"
	if control:
		type_name = String(control.get_meta("value_type", "float"))
		var label := control.get_meta("value_label") as Label
		if label:
			label.text = _format_value(value, type_name)
	_active.set_parameter(key, int(value) if type_name == "int" else value)


func _on_bool_parameter_changed(enabled: bool, key: StringName) -> void:
	if _active:
		_active.set_parameter(key, enabled)


func _format_value(value: float, type_name: String) -> String:
	if type_name == "int":
		return str(int(round(value)))
	return "%.2f" % value


func _on_reseed() -> void:
	if _active:
		_active.reseed(int(_seed_box.value))
		_seed_box.value = _active.random_seed


func _toggle_pause() -> void:
	if _active == null:
		return
	var next := not _active.simulation_enabled
	_active.set_simulation_active(next)
	_pause_button.text = "Pause" if next else "Play"


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
	for descriptor in _active.get_editor_schema():
		var key: StringName = descriptor.get("key", &"")
		var type_name := String(descriptor.get("type", "float"))
		if type_name == "bool":
			continue
		var min_value := float(descriptor.get("min", 0.0))
		var max_value := float(descriptor.get("max", 1.0))
		var value := _active._rng.randf_range(min_value, max_value)
		if type_name == "int":
			value = round(value)
		_active.set_parameter(key, value)
	_rebuild_parameter_controls()


func _apply_named_impulse(impulse: Vector2) -> void:
	if _active:
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
	return String(_active.creature_id) if _active else "none"


func _save_current_preset() -> void:
	if _active == null:
		return
	_saved_presets[_preset_key()] = _active.make_preset()
	_write_presets_to_disk()
	_refresh_status("Preset saved")


func _load_current_preset() -> void:
	if _active == null:
		return
	var key := _preset_key()
	if not _saved_presets.has(key):
		_refresh_status("No saved preset for %s" % key)
		return
	_active.apply_preset(_saved_presets[key])
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
	var file := FileAccess.open(PRESET_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed := JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_saved_presets = parsed


func _write_presets_to_disk() -> void:
	var file := FileAccess.open(PRESET_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_saved_presets, "\t"))


func _spawn_stress_test() -> void:
	_clear_stress_test()
	if _active == null:
		return
	var script := _active.get_script() as Script
	for i in range(_stress_count):
		var clone := script.new() as ProceduralCreature
		clone.apply_preset(_active.make_preset())
		clone.global_scale_factor *= randf_range(0.75, 1.15)
		clone.position = Vector2(randf_range(390.0, 1500.0), randf_range(180.0, 730.0))
		clone.set_lod_anchor(get_node("LODAnchor"))
		add_child(clone)
		_stress_instances.append(clone)
	_active.visible = false
	_refresh_status("Stress test spawned")


func _clear_stress_test() -> void:
	for creature in _stress_instances:
		if is_instance_valid(creature):
			creature.queue_free()
	_stress_instances.clear()
	if _active:
		_active.visible = true
	_refresh_status()


func _refresh_status(message: String = "") -> void:
	if _status_label == null:
		return
	var prefix := (message + "\n") if not message.is_empty() else ""
	var active_name := String(_active.creature_id) if _active else "none"
	_status_label.text = prefix + "FPS: %d  |  procedural: %d\nActive: %s  |  sim: %s\nPreset file: %s" % [Engine.get_frames_per_second(), _stress_instances.size() + (1 if _active != null else 0), active_name, "ON" if _active != null and _active.simulation_enabled else "OFF", PRESET_PATH]


func _unhandled_input(event: InputEvent) -> void:
	if _active == null or not _active.visible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.position.x < 320.0:
			return
		var world_point := mouse_event.position
		var direction := (_active.position - world_point).normalized()
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_active.apply_impulse(direction * 220.0 + Vector2(0, -35))
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_active.apply_impulse(-direction * 180.0)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_active.set_parameter(&"global_scale_factor", _active.global_scale_factor + 0.05)
			_rebuild_parameter_controls()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_active.set_parameter(&"global_scale_factor", _active.global_scale_factor - 0.05)
			_rebuild_parameter_controls()
