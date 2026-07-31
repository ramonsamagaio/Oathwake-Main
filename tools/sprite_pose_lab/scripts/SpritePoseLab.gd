extends "res://tools/sprite_pose_lab/scripts/SpritePoseLabInteraction.gd"


func request_load_part() -> void:
	file_action = FileAction.LOAD_PART
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar PNG", ["*.png ; PNG"])


func clear_part_texture() -> void:
	var direction_name := str(model.frames[frame_index].get("direction", "south"))
	model.part_library[direction_name][model.PARTS[part_index]] = ""
	pose_canvas.clear_texture_cache()
	refresh_all()


func request_save_pose() -> void:
	file_action = FileAction.SAVE_POSE
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar pose", ["*.json ; JSON"], model.pose_filename(frame_index))


func request_load_pose() -> void:
	file_action = FileAction.LOAD_POSE
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar pose", ["*.json ; JSON"])


func request_save_cycle() -> void:
	file_action = FileAction.SAVE_CYCLE
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar ciclo", ["*.json ; JSON"], model.cycle_filename())


func request_load_cycle() -> void:
	file_action = FileAction.LOAD_CYCLE
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar ciclo", ["*.json ; JSON"])


func request_export_frame() -> void:
	file_action = FileAction.EXPORT_FRAME
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar frame", ["*.png ; PNG"], model.frame_filename(frame_index))


func request_export_all() -> void:
	file_action = FileAction.EXPORT_ALL
	_open_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Pasta dos frames", [])


func request_export_sheet() -> void:
	file_action = FileAction.EXPORT_SHEET
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar sprite sheet", ["*.png ; PNG"], model.sheet_filename())


func _open_dialog(mode: int, dialog_title: String, filters: Array, suggested_name: String = "") -> void:
	file_dialog.file_mode = mode
	file_dialog.title = dialog_title
	file_dialog.filters = PackedStringArray(filters)
	file_dialog.current_dir = ProjectSettings.globalize_path(DATA_DIR)
	file_dialog.current_file = suggested_name
	file_dialog.popup_centered_ratio(0.78)


func on_file_dialog_canceled() -> void:
	file_action = FileAction.NONE


func on_file_selected(path: String) -> void:
	match file_action:
		FileAction.LOAD_PART:
			_load_part(path)
		FileAction.SAVE_POSE:
			_save_json(path, model.pose_document(frame_index))
		FileAction.LOAD_POSE:
			_load_pose(path)
		FileAction.SAVE_CYCLE:
			_sync_names()
			_save_json(path, model.cycle_document())
		FileAction.LOAD_CYCLE:
			_load_cycle(path)
		FileAction.EXPORT_FRAME:
			_sync_names()
			await _export_frame(path)
		FileAction.EXPORT_SHEET:
			_sync_names()
			await _export_sheet(path)
	file_action = FileAction.NONE


func on_directory_selected(path: String) -> void:
	if file_action == FileAction.EXPORT_ALL:
		_sync_names()
		await _export_all(path)
	file_action = FileAction.NONE


func _sync_names() -> void:
	model.character_name = character_edit.text
	model.animation_name = animation_edit.text


func _load_part(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		set_status("Não foi possível abrir o PNG.", true)
		return
	var direction_name := str(model.frames[frame_index].get("direction", "south"))
	model.part_library[direction_name][model.PARTS[part_index]] = path
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("PNG carregado para %s / %s." % [direction_name, model.PARTS[part_index]])


func _save_json(path: String, data: Dictionary) -> void:
	var final_path := _ensure_extension(path, "json")
	var file := FileAccess.open(final_path, FileAccess.WRITE)
	if file == null:
		set_status("Não foi possível salvar o arquivo.", true)
		return
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	set_status("Salvo: %s" % final_path)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		set_status("Não foi possível abrir o arquivo.", true)
		return {}
	var parsed_data := JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed_data is Dictionary):
		set_status("JSON inválido.", true)
		return {}
	return parsed_data


func _load_pose(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty() or not model.apply_pose_document(data, frame_index):
		set_status("Pose inválida.", true)
		return
	_apply_model_canvas()
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("Pose carregada no frame atual.")


func _load_cycle(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty() or not model.apply_cycle_document(data):
		set_status("Ciclo inválido.", true)
		return
	frame_index = 0
	_apply_model_canvas()
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("Ciclo carregado com %d frames." % model.frames.size())


func _apply_model_canvas() -> void:
	render_viewport.size = model.canvas_size
	pose_canvas.configure(model.canvas_size, model.feet_y)
	update_preview_size()


func _export_frame(path: String) -> void:
	var final_path := _ensure_extension(path, "png")
	var image: Image = await _render_frame(frame_index)
	var save_result := image.save_png(final_path)
	_restore_preview()
	if save_result == OK:
		set_status("Frame exportado: %s" % final_path)
	else:
		set_status("Falha ao exportar frame.", true)


func _export_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var original_frame := frame_index
	var failures := 0
	for index in range(model.frames.size()):
		var image: Image = await _render_frame(index)
		if image.save_png(directory.path_join(model.frame_filename(index))) != OK:
			failures += 1
	frame_index = original_frame
	_restore_preview()
	if failures == 0:
		set_status("%d frames exportados." % model.frames.size())
	else:
		set_status("Exportação concluída com %d falhas." % failures, true)


func _export_sheet(path: String) -> void:
	var final_path := _ensure_extension(path, "png")
	var original_frame := frame_index
	var frame_size: Vector2i = model.canvas_size
	var sheet := Image.create_empty(frame_size.x * model.frames.size(), frame_size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for index in range(model.frames.size()):
		var image: Image = await _render_frame(index)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(index * frame_size.x, 0))
	frame_index = original_frame
	var save_result := sheet.save_png(final_path)
	_restore_preview()
	if save_result == OK:
		set_status("Sprite sheet exportada: %s" % final_path)
	else:
		set_status("Falha ao exportar sprite sheet.", true)


func _render_frame(index: int) -> Image:
	var previous_frame_data: Dictionary = {}
	if index > 0:
		previous_frame_data = model.frames[index - 1]
	pose_canvas.set_pixel_perfect(pixel_preview_check.button_pressed)
	pose_canvas.set_selection("", false)
	pose_canvas.set_export_mode(true)
	pose_canvas.apply_pose(model.frames[index], model.part_library, previous_frame_data, false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return render_viewport.get_texture().get_image()


func _restore_preview() -> void:
	pose_canvas.set_export_mode(false)
	refresh_all()


func _ensure_extension(path: String, extension: String) -> String:
	if path.get_extension().to_lower() == extension:
		return path
	return "%s.%s" % [path, extension]
