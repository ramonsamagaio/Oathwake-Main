extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"

# Thin UI layer over the already validated Alabaster mechanic lab.
# It does not alter the rig/render path. F3 only hot-loads the complete
# animation dictionary from the demo's juno.json into the existing runtime.

var _juno_source_dialog: FileDialog


func _ready() -> void:
	super._ready()
	_build_juno_source_dialog()
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
	print("ALABASTER_PLAYGROUND_SOURCE_READY animations=%d" % _catalog.size())
