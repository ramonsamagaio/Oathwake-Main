extends "res://scripts/BuildSystem.gd"

const BuildMenuScene: PackedScene = preload("res://scenes/ui/BuildMenuUI.tscn")
const ContentGlowRuntime := preload("res://scripts/effects/ContentGlowRuntime.gd")

signal build_mode_changed(enabled: bool)
signal selected_building_changed(building_id: String)

var build_menu: Control
var _menu_install_attempts := 0


func _ready() -> void:
	super._ready()
	call_deferred("_install_build_menu")
	_connect_content_reload()


func setup(context: Dictionary) -> void:
	super.setup(context)
	call_deferred("_refresh_build_menu")


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		_refresh_build_menu()


func _set_build_mode_enabled(is_enabled: bool) -> void:
	super._set_build_mode_enabled(is_enabled)
	if build_menu != null:
		build_menu.call("set_build_mode_visible", is_enabled)
	build_mode_changed.emit(is_enabled)


func select_building(building_id: String) -> void:
	var normalized := _normalize_building_type(building_id)
	if not _is_known_building_type(normalized):
		return
	selected_build_type = normalized
	_update_preview()
	_update_build_label()
	_refresh_build_menu()
	selected_building_changed.emit(selected_build_type)


func get_selected_building_id() -> String:
	return selected_build_type


func get_selected_building_display_name() -> String:
	return _get_building_display_name(selected_build_type)


func get_build_catalog() -> Array:
	var catalog: Array = []
	for building_id_value in _get_building_ui_order():
		var building_id := str(building_id_value)
		var data := _get_building_data(building_id)
		catalog.append({
			"id": building_id,
			"display_name": _get_building_display_name(building_id),
			"key": str(data.get("build_key", "")),
			"cost": _get_building_cost_text(building_id),
		})
	return catalog


func _spawn_building_scene(tile_position: Vector2i, building_type: String) -> void:
	super._spawn_building_scene(tile_position, building_type)
	var cell_key := _cell_key(tile_position)
	if not building_scene_by_cell.has(cell_key):
		return
	var building_node := building_scene_by_cell[cell_key] as Node2D
	if building_node == null:
		return
	var building_data := _get_building_data(building_type)
	var glow_value: Variant = building_data.get("glow", {})
	ContentGlowRuntime.apply_glow(building_node, glow_value if glow_value is Dictionary else {}, 24)


func _install_build_menu() -> void:
	if build_menu != null and is_instance_valid(build_menu):
		_refresh_build_menu()
		return
	var controller := main
	if controller == null:
		controller = get_tree().get_first_node_in_group("main")
	var ui_root: Node = null
	if controller != null:
		ui_root = controller.get_node_or_null("UI")
	if ui_root == null:
		_menu_install_attempts += 1
		if _menu_install_attempts < 8:
			call_deferred("_install_build_menu")
		return
	build_menu = BuildMenuScene.instantiate() as Control
	if build_menu == null:
		return
	build_menu.name = "BuildMenuUI"
	ui_root.add_child(build_menu)
	build_menu.call("setup", self)
	build_menu.call("set_build_mode_visible", build_mode_enabled)


func _refresh_build_menu() -> void:
	if build_menu != null and is_instance_valid(build_menu):
		build_menu.call("refresh_catalog")
		build_menu.call("set_build_mode_visible", build_mode_enabled)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_on_build_content_reloaded")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)


func _on_build_content_reloaded() -> void:
	for cell_key_value in building_scene_by_cell.keys():
		var cell_key := str(cell_key_value)
		var building_node := building_scene_by_cell.get(cell_key) as Node2D
		if building_node == null:
			continue
		var metadata := building_metadata_by_cell.get(cell_key, {})
		var building_id := str(metadata.get("type", "")) if metadata is Dictionary else ""
		if building_id.is_empty():
			continue
		var data := _get_building_data(building_id)
		var glow_value: Variant = data.get("glow", {})
		ContentGlowRuntime.apply_glow(building_node, glow_value if glow_value is Dictionary else {}, 24)
	_refresh_build_menu()
