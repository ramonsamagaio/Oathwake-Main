extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"

# Thin UI layer over the already validated Alabaster mechanic lab.
# It does not alter the rig/render path. F3 only hot-loads the complete
# animation dictionary from the demo's juno.json into the existing runtime.

var _juno_source_dialog: FileDialog
var _sprite_opacity_slider: HSlider


func _ready() -> void:
	super._ready()
	_build_juno_source_dialog()
	_build_sprite_opacity_control()
	if hotkey_label != null:
		hotkey_label.text = "F3 carregar juno.json • " + hotkey_label.text


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_open_juno_source_dialog()
		return
	super._unhandled_key_input(event)


func _update_browser_label() -> void:
	super._update_browser_label()
	if browser_label != null and _catalog.size() <= 3:
		browser_label.text += " • F3: selecione terra/data/figures/char/player/juno.json"


func _build_juno_source_dialog() -> void:
	_juno_source_dialog = FileDialog.new()
	_juno_source_dialog.name = "JunoSourceDialog"
	_juno_source_dialog.title = "Selecione terra/data/figures/char/player/juno.json"
	_juno_source_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_juno_source_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_juno_source_dialog.filters = PackedStringArray(["*.json ; Juno figure JSON"])
	_juno_source_dialog.file_selected.connect(_on_juno_source_selected)
	add_child(_juno_source_dialog)


func _build_sprite_opacity_control() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpriteOpacityControls"
	layer.layer = 90
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 112)
	panel.custom_minimum_size = Vector2(310, 58)
	layer.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	label.text = "Sprite opacity"
	label.custom_minimum_size = Vector2(115, 0)
	row.add_child(label)
	_sprite_opacity_slider = HSlider.new()
	_sprite_opacity_slider.min_value = 0.0
	_sprite_opacity_slider.max_value = 1.0
	_sprite_opacity_slider.step = 0.05
	_sprite_opacity_slider.value = 1.0
	_sprite_opacity_slider.custom_minimum_size = Vector2(150, 0)
	_sprite_opacity_slider.tooltip_text = "Lower this to inspect the bones underneath Juno's sprites."
	_sprite_opacity_slider.value_changed.connect(_on_sprite_opacity_changed)
	row.add_child(_sprite_opacity_slider)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "100%"
	row.add_child(value_label)
	_sprite_opacity_slider.value_changed.connect(func(value: float) -> void: value_label.text = "%d%%" % roundi(value * 100.0))


func _on_sprite_opacity_changed(value: float) -> void:
	if rig != null and rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", value)


func _open_juno_source_dialog() -> void:
	if _juno_source_dialog != null:
		_juno_source_dialog.popup_centered_ratio(0.82)


func _on_juno_source_selected(source_path: String) -> void:
	_auto_showcase = false
	_stop_manual_animation()
	if not rig.load_external_animation_source(source_path):
		push_warning("AlabasterAnimationPlayground: arquivo incompatível. Selecione terra/data/figures/char/player/juno.json")
		_update_status()
		return

	_browser_category_index = 0
	_browser_index = 0
	_refresh_catalog()
	_update_status()
	if _sprite_opacity_slider != null:
		_on_sprite_opacity_changed(_sprite_opacity_slider.value)
	print("ALABASTER_PLAYGROUND_SOURCE_READY animations=%d" % _catalog.size())
