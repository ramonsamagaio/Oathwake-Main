extends "res://tools/sprite_pose_lab/scripts/WyrdframeInteractionView.gd"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	_create_new_document("character")
	_build_theme()
	_build_ui()
	_build_rendering()
	_build_runtime_helpers()
	_restore_layout()
	_rebuild_structure()
	_configure_window()
	_set_status("Wyrdframe pronto. Projeto novo criado.")
	if OS.has_environment("WYRD_FRAME_SMOKE_TEST"):
		call_deferred("_run_smoke_test")

func _exit_tree() -> void:
	_save_layout()

func _configure_window() -> void:
	var app_window: Window = get_window()
	app_window.title = PROGRAM_NAME
	app_window.unresizable = false
	app_window.min_size = Vector2i(1120, 700)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed and key_event.keycode == KEY_S:
		_request_save_project()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_O:
		_request_load_project()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Z:
		_undo()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Y:
		_redo()
	elif key_event.alt_pressed and key_event.keycode == KEY_D:
		_duplicate_frame()
	elif key_event.keycode == KEY_INSERT:
		_add_frame()
	elif key_event.keycode == KEY_DELETE:
		_remove_frame()
	elif key_event.keycode == KEY_LEFT:
		_select_frame(current_frame - 1)
	elif key_event.keycode == KEY_RIGHT:
		_select_frame(current_frame + 1)
	elif key_event.keycode == KEY_SPACE:
		_toggle_playback()
		get_viewport().set_input_as_handled()

func _write_project(path: String) -> void:
	var safe_path: String = _ensure_extension(path, FILE_EXTENSION)
	if _write_document(safe_path, document, true):
		current_project_path = safe_path
		dirty = false
		_update_window_title()

func _load_project(path: String) -> void:
	var loaded_document: Dictionary = _read_document(path)
	if loaded_document.is_empty():
		return
	if str(loaded_document.get("format", "")) != FORMAT_NAME:
		_set_status("Formato incompatível. Abra um projeto .wyrd válido.", true)
		return
	_record_history()
	document = loaded_document.duplicate(true)
	_normalize_document()
	current_project_path = path if path.get_extension().to_lower() == FILE_EXTENSION else ""
	var action_keys: Array = _actions().keys()
	current_action = str(action_keys[0]) if not action_keys.is_empty() else "custom"
	current_direction = "south"
	current_frame = 0
	selected_bone = "torso" if not _bone_by_id("torso").is_empty() else "root"
	dirty = false
	canvas_renderer.clear_texture_cache()
	_rebuild_structure()
	_set_status("Projeto carregado.")

func _normalize_document() -> void:
	if not document.has("project"):
		document["project"] = {"name": "Projeto", "asset_name": "asset", "entity_type": "custom"}
	if not document.has("canvas"):
		document["canvas"] = {"width": 64, "height": 64, "feet_y": 60}
	if not document.has("playback"):
		document["playback"] = {"fps": 8.0, "loop_mode": "loop", "use_frame_durations": false}
	if not document.has("rig"):
		document["rig"] = {"bones": _default_bones()}
	if _bones().is_empty():
		_rig_section()["bones"] = _default_bones()
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if not bone_data.has("editor_visible"):
			bone_data["editor_visible"] = true
	if not document.has("actions"):
		document["actions"] = {}
	if _actions().is_empty():
		_add_action_data("custom", "custom", false)
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		action_data["directions"] = directions
		for direction_id: String in DIRECTIONS:
			if not directions.has(direction_id):
				directions[direction_id] = {"frames": [_new_frame()], "textures": {}}
			var direction_data: Dictionary = directions[direction_id] as Dictionary
			var frames_value: Array = direction_data.get("frames", []) as Array
			direction_data["frames"] = frames_value
			if frames_value.is_empty():
				frames_value.append(_new_frame())
			var textures: Dictionary = direction_data.get("textures", {}) as Dictionary
			direction_data["textures"] = textures
			for bone_value: Variant in _bones():
				var bone_data: Dictionary = bone_value as Dictionary
				var bone_id: String = str(bone_data.get("id", ""))
				if not textures.has(bone_id):
					textures[bone_id] = ""
	document["format"] = FORMAT_NAME
	document["version"] = FORMAT_VERSION

func _write_autosave() -> void:
	_write_document(AUTOSAVE_PATH, document, false)

func _write_document(path: String, data: Dictionary, report: bool) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		if report:
			_set_status("Não foi possível salvar o arquivo.", true)
		return false
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	if report:
		_set_status("Salvo: %s" % path)
	return true

func _read_document(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Não foi possível abrir o arquivo.", true)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_set_status("Arquivo inválido.", true)
		return {}
	return parsed as Dictionary

func _render_frame_image(frame_index_value: int) -> Image:
	var saved_frame: int = current_frame
	current_frame = frame_index_value
	canvas_renderer.set_export_mode(true)
	_apply_render()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = render_viewport.get_texture().get_image()
	canvas_renderer.set_export_mode(false)
	current_frame = saved_frame
	_apply_render()
	return image

func _export_frame(path: String) -> void:
	var image: Image = await _render_frame_image(current_frame)
	var save_error: Error = image.save_png(path)
	_set_status("Frame exportado: %s" % path if save_error == OK else "Falha ao exportar frame.", save_error != OK)

func _export_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var failures: int = 0
	for frame_index_value: int in range(_frames().size()):
		var image: Image = await _render_frame_image(frame_index_value)
		var save_path: String = directory.path_join(_frame_filename(frame_index_value))
		if image.save_png(save_path) != OK:
			failures += 1
	_set_status("Sequência exportada." if failures == 0 else "%d falhas na exportação." % failures, failures > 0)

func _export_sheet(path: String) -> void:
	var canvas_data: Dictionary = _canvas_section()
	var frame_size: Vector2i = Vector2i(
		maxi(1, int(canvas_data.get("width", 64))),
		maxi(1, int(canvas_data.get("height", 64)))
	)
	var sheet: Image = Image.create_empty(frame_size.x * _frames().size(), frame_size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for frame_index_value: int in range(_frames().size()):
		var image: Image = await _render_frame_image(frame_index_value)
		sheet.blit_rect(
			image,
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(frame_index_value * frame_size.x, 0)
		)
	var save_error: Error = sheet.save_png(path)
	_set_status("Sprite sheet exportada: %s" % path if save_error == OK else "Falha ao exportar sprite sheet.", save_error != OK)

func _undo() -> void:
	if undo_stack.is_empty():
		_set_status("Nada para desfazer.")
		return
	redo_stack.append(document.duplicate(true))
	document = undo_stack.pop_back()
	_normalize_document()
	_repair_selection()
	_rebuild_structure()
	_set_status("Desfeito.")

func _redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nada para refazer.")
		return
	undo_stack.append(document.duplicate(true))
	document = redo_stack.pop_back()
	_normalize_document()
	_repair_selection()
	_rebuild_structure()
	_set_status("Refeito.")

func _repair_selection() -> void:
	if not _actions().has(current_action):
		current_action = str(_actions().keys()[0])
	if not DIRECTIONS.has(current_direction):
		current_direction = "south"
	current_frame = clampi(current_frame, 0, maxi(0, _frames().size() - 1))
	if _bone_by_id(selected_bone).is_empty():
		selected_bone = "root"

func _project_filename() -> String:
	return "%s.%s" % [_safe_name(str(_project_section().get("asset_name", "asset")), "asset"), FILE_EXTENSION]

func _frame_filename(frame_index_value: int) -> String:
	return "%s_%s_%s_%02d.png" % [
		_safe_name(str(_project_section().get("asset_name", "asset")), "asset"),
		_safe_name(current_action, "action"),
		_safe_name(current_direction, "south"),
		frame_index_value + 1,
	]

func _sheet_filename() -> String:
	return "%s_%s_%s_sheet.png" % [
		_safe_name(str(_project_section().get("asset_name", "asset")), "asset"),
		_safe_name(current_action, "action"),
		_safe_name(current_direction, "south"),
	]

func _safe_name(value: String, fallback: String) -> String:
	var result: String = value.strip_edges().to_lower().to_snake_case()
	var regex: RegEx = RegEx.new()
	regex.compile("[^a-z0-9_]+")
	result = regex.sub(result, "_", true)
	return fallback if result.is_empty() else result

func _ensure_extension(path: String, extension: String) -> String:
	return path if path.get_extension().to_lower() == extension else "%s.%s" % [path, extension]

func _save_layout() -> void:
	if root_split == null or main_split == null or center_split == null:
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("layout", "root_split", root_split.split_offset)
	config.set_value("layout", "main_split", main_split.split_offset)
	config.set_value("layout", "center_split", center_split.split_offset)
	if timeline_cell_width_spin != null:
		config.set_value("layout", "timeline_cell_width", timeline_cell_width_spin.value)
	var app_window: Window = get_window()
	config.set_value("window", "size_x", app_window.size.x)
	config.set_value("window", "size_y", app_window.size.y)
	config.set_value("window", "position_x", app_window.position.x)
	config.set_value("window", "position_y", app_window.position.y)
	config.save(LAYOUT_PATH)

func _restore_layout() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(LAYOUT_PATH) != OK:
		return
	root_split.split_offset = int(config.get_value("layout", "root_split", 560))
	main_split.split_offset = int(config.get_value("layout", "main_split", 300))
	center_split.split_offset = int(config.get_value("layout", "center_split", 830))
	if timeline_cell_width_spin != null:
		timeline_cell_width_spin.value = float(config.get_value("layout", "timeline_cell_width", 44.0))
	var app_window: Window = get_window()
	var saved_width: int = int(config.get_value("window", "size_x", app_window.size.x))
	var saved_height: int = int(config.get_value("window", "size_y", app_window.size.y))
	app_window.size = Vector2i(maxi(1120, saved_width), maxi(700, saved_height))
	var position_x: int = int(config.get_value("window", "position_x", app_window.position.x))
	var position_y: int = int(config.get_value("window", "position_y", app_window.position.y))
	app_window.position = Vector2i(position_x, position_y)

func _run_smoke_test() -> void:
	await get_tree().process_frame
	if _actions().has("walk"):
		current_action = "walk"
	current_direction = "west"
	current_frame = 0
	_refresh_context()
	_select_current_project_tree_item()
	_add_frame()
	_remove_frame()
	selected_bone = "left_arm" if not _bone_by_id("left_arm").is_empty() else "root"
	_refresh_context()
	print("WYRD_FRAME_SMOKE_TEST_OK")
	get_tree().quit()
