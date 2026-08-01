extends "res://tools/sprite_pose_lab/scripts/SpritePoseStudioInteraction.gd"

func _request_load_texture() -> void:
	file_action = FileAction.LOAD_TEXTURE
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar sprite do bone", ["*.png ; PNG"])


func _clear_texture() -> void:
	_record_history()
	pose_project.set_texture(pose_project.current_direction, selected_bone_id, "")
	pose_canvas.clear_texture_cache()
	_mark_changed("Sprite removido desta direção.")


func _request_save_project() -> void:
	file_action = FileAction.SAVE_PROJECT
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar projeto de pose", ["*.json ; JSON"], "%s.pose.json" % pose_project.character_name)


func _request_load_project() -> void:
	file_action = FileAction.LOAD_PROJECT
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Abrir projeto de pose", ["*.json ; JSON"])


func _request_export_frame() -> void:
	file_action = FileAction.EXPORT_FRAME
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar frame", ["*.png ; PNG"], _frame_filename(selected_frame))


func _request_export_all() -> void:
	file_action = FileAction.EXPORT_ALL
	_open_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Exportar sequência PNG", [])


func _request_export_sheet() -> void:
	file_action = FileAction.EXPORT_SHEET
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar sprite sheet", ["*.png ; PNG"], _sheet_filename())


func _open_dialog(mode: int, title_text: String, filters: Array, suggested: String = "") -> void:
	file_dialog.file_mode = mode
	file_dialog.title = title_text
	file_dialog.filters = PackedStringArray(filters)
	file_dialog.current_dir = ProjectSettings.globalize_path(DATA_DIR)
	file_dialog.current_file = suggested
	file_dialog.popup_centered_ratio(0.78)


func _on_file_selected(path: String) -> void:
	match file_action:
		FileAction.LOAD_TEXTURE:
			_load_texture_path(path)
		FileAction.SAVE_PROJECT:
			_write_json(_ensure_extension(path, "json"), pose_project.to_document())
		FileAction.LOAD_PROJECT:
			_load_project(path)
		FileAction.EXPORT_FRAME:
			await _export_frame(_ensure_extension(path, "png"))
		FileAction.EXPORT_SHEET:
			await _export_sheet(_ensure_extension(path, "png"))
	file_action = FileAction.NONE


func _on_directory_selected(path: String) -> void:
	if file_action == FileAction.EXPORT_ALL:
		await _export_all(path)
	file_action = FileAction.NONE


func _load_texture_path(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		_set_status("Não foi possível carregar o PNG.", true)
		return
	var project_root := ProjectSettings.globalize_path("res://")
	var stored_path := ProjectSettings.localize_path(path) if path.begins_with(project_root) else path
	_record_history()
	pose_project.set_texture(pose_project.current_direction, selected_bone_id, stored_path)
	pose_canvas.clear_texture_cache()
	_mark_changed("PNG associado ao bone nesta direção.")


func _load_project(path: String) -> void:
	var document := _read_json(path)
	if document.is_empty():
		return
	_record_history()
	if not pose_project.load_document(document):
		_set_status("Documento incompatível ou inválido.", true)
		return
	selected_frame = 0
	selected_bone_id = "torso" if not pose_project.bone_by_id("torso").is_empty() else str(pose_project.bones[0].get("id", "root"))
	pose_canvas.clear_texture_cache()
	_rebuild_everything()
	_set_status("Projeto carregado.")


func _write_autosave() -> void:
	_write_json(AUTOSAVE_PATH, pose_project.to_document(), false)


func _write_json(path: String, document: Dictionary, report: bool = true) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		if report:
			_set_status("Não foi possível salvar o arquivo.", true)
		return
	file.store_string(JSON.stringify(document, "\t", false))
	file.close()
	if report:
		_set_status("Salvo: %s" % path)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Não foi possível abrir o arquivo.", true)
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_set_status("JSON inválido.", true)
		return {}
	return parsed


func _render_frame(frame_number: int) -> Image:
	pose_canvas.set_export_mode(true)
	pose_canvas.apply_frame(frame_number, selected_bone_id)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := render_viewport.get_texture().get_image()
	pose_canvas.set_export_mode(false)
	pose_canvas.apply_frame(selected_frame, selected_bone_id)
	return image


func _export_frame(path: String) -> void:
	var image := await _render_frame(selected_frame)
	var error := image.save_png(path)
	_set_status("Frame exportado: %s" % path if error == OK else "Falha ao exportar frame.", error != OK)


func _export_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var failures := 0
	for frame_number in range(pose_project.frame_count()):
		var image := await _render_frame(frame_number)
		if image.save_png(directory.path_join(_frame_filename(frame_number))) != OK:
			failures += 1
	_set_status("Sequência exportada." if failures == 0 else "%d falhas na exportação." % failures, failures > 0)


func _export_sheet(path: String) -> void:
	var frame_size := pose_project.canvas_size
	var sheet := Image.create_empty(frame_size.x * pose_project.frame_count(), frame_size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for frame_number in range(pose_project.frame_count()):
		var image := await _render_frame(frame_number)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(frame_number * frame_size.x, 0))
	var error := sheet.save_png(path)
	_set_status("Sprite sheet exportada: %s" % path if error == OK else "Falha ao exportar sprite sheet.", error != OK)


func _frame_filename(frame_number: int) -> String:
	return "%s_%s_%s_%02d.png" % [
		_safe_name(pose_project.character_name, "character"),
		_safe_name(pose_project.current_clip, "animation"),
		_safe_name(pose_project.current_direction, "south"),
		frame_number + 1,
	]


func _sheet_filename() -> String:
	return "%s_%s_%s_sheet.png" % [
		_safe_name(pose_project.character_name, "character"),
		_safe_name(pose_project.current_clip, "animation"),
		_safe_name(pose_project.current_direction, "south"),
	]


func _record_history() -> void:
	if history_suspended:
		return
	undo_stack.append(pose_project.to_document())
	if undo_stack.size() > 50:
		undo_stack.pop_front()
	redo_stack.clear()


func _undo() -> void:
	if undo_stack.is_empty():
		_set_status("Nada para desfazer.")
		return
	redo_stack.append(pose_project.to_document())
	var document: Dictionary = undo_stack.pop_back()
	_history_load(document)
	_set_status("Desfeito.")


func _redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nada para refazer.")
		return
	undo_stack.append(pose_project.to_document())
	var document: Dictionary = redo_stack.pop_back()
	_history_load(document)
	_set_status("Refeito.")


func _history_load(document: Dictionary) -> void:
	history_suspended = true
	pose_project.load_document(document)
	selected_frame = clampi(selected_frame, 0, pose_project.frame_count() - 1)
	if pose_project.bone_by_id(selected_bone_id).is_empty():
		selected_bone_id = "root"
	pose_canvas.clear_texture_cache()
	_rebuild_everything()
	history_suspended = false


func _mark_changed(message: String = "") -> void:
	autosave_timer.start()
	_refresh_ui()
	if not message.is_empty():
		_set_status(message)
