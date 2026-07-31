extends "res://tools/sprite_pose_lab/scripts/SpritePoseLabInteraction.gd"


func request_load_part() -> void:
	file_action = FileAction.LOAD_PART
	open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar PNG", ["*.png ; PNG"])


func clear_part_texture() -> void:
	var direction := str(model.frames[frame_index].get("direction", "south"))
	model.part_library[direction][model.PARTS[part_index]] = ""
	pose_canvas.clear_texture_cache()
	refresh_all()


func request_save_pose() -> void:
	file_action = FileAction.SAVE_POSE
	open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar pose", ["*.json ; JSON"], model.pose_filename(frame_index))


func request_load_pose() -> void:
	file_action = FileAction.LOAD_POSE
	open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar pose", ["*.json ; JSON"])


func request_save_cycle() -> void:
	file_action = FileAction.SAVE_CYCLE
	open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar ciclo", ["*.json ; JSON"], model.cycle_filename())


func request_load_cycle() -> void:
	file_action = FileAction.LOAD_CYCLE
	open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar ciclo", ["*.json ; JSON"])


func request_export_frame() -> void:
	file_action = FileAction.EXPORT_FRAME
	open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar frame", ["*.png ; PNG"], model.frame_filename(frame_index))


func request_export_all() -> void:
	file_action = FileAction.EXPORT_ALL
	open_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Pasta dos frames", [])


func request_export_sheet() -> void:
	file_action = FileAction.EXPORT_SHEET
	open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar sprite sheet", ["*.png ; PNG"], model.sheet_filename())


func open_dialog(mode: int, title: String, filters: Array, suggested: String = "") -> void:
	file_dialog.file_mode = mode
	file_dialog.title = title
	file_dialog.filters = PackedStringArray(filters)
	file_dialog.current_dir = ProjectSettings.globalize_path(DATA_DIR)
	file_dialog.current_file = suggested
	file_dialog.popup_centered_ratio(0.78)


func on_file_dialog_canceled() -> void:
	file_action = FileAction.NONE


func on_file_selected(path: String) -> void:
	match file_action:
		FileAction.LOAD_PART:
			load_part(path)
		FileAction.SAVE_POSE:
			save_json(path, model.pose_document(frame_index))
		FileAction.LOAD_POSE:
			load_pose(path)
		FileAction.SAVE_CYCLE:
			sync_names()
			save_json(path, model.cycle_document())
		FileAction.LOAD_CYCLE:
			load_cycle(path)
		FileAction.EXPORT_FRAME:
			sync_names()
			await export_frame(path)
		FileAction.EXPORT_SHEET:
			sync_names()
			await export_sheet(path)
	file_action = FileAction.NONE


func on_directory_selected(path: String) -> void:
	if file_action == FileAction.EXPORT_ALL:
		sync_names()
		await export_all(path)
	file_action = FileAction.NONE


func sync_names() -> void:
	model.character_name = character_edit.text
	model.animation_name = animation_edit.text


func load_part(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		set_status("Não foi possível abrir o PNG.", true)
		return
	var direction := str(model.frames[frame_index].get("direction", "south"))
	model.part_library[direction][model.PARTS[part_index]] = path
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("PNG carregado para %s / %s." % [direction, model.PARTS[part_index]])


func save_json(path: String, data: Dictionary) -> void:
	path = ensure_extension(path, "json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		set_status("Não foi possível salvar o arquivo.", true)
		return
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	set_status("Salvo: %s" % path)


func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		set_status("Não foi possível abrir o arquivo.", true)
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		set_status("JSON inválido.", true)
		return {}
	return parsed


func load_pose(path: String) -> void:
	var data := read_json(path)
	if data.is_empty() or not model.apply_pose_document(data, frame_index):
		set_status("Pose inválida.", true)
		return
	apply_model_canvas()
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("Pose carregada no frame atual.")


func load_cycle(path: String) -> void:
	var data := read_json(path)
	if data.is_empty() or not model.apply_cycle_document(data):
		set_status("Ciclo inválido.", true)
		return
	frame_index = 0
	apply_model_canvas()
	pose_canvas.clear_texture_cache()
	refresh_all()
	set_status("Ciclo carregado com %d frames." % model.frames.size())


func apply_model_canvas() -> void:
	viewport.size = model.canvas_size
	pose_canvas.configure(model.canvas_size, model.feet_y)
	update_preview_size()


func export_frame(path: String) -> void:
	path = ensure_extension(path, "png")
	var image := await render_frame(frame_index)
	var error := image.save_png(path)
	restore_preview()
	set_status("Frame exportado: %s" % path if error == OK else "Falha ao exportar frame.", error != OK)


func export_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var original := frame_index
	var failures := 0
	for index in range(model.frames.size()):
		var image := await render_frame(index)
		if image.save_png(directory.path_join(model.frame_filename(index))) != OK:
			failures += 1
	frame_index = original
	restore_preview()
	if failures == 0:
		set_status("%d frames exportados." % model.frames.size())
	else:
		set_status("Exportação concluída com %d falhas." % failures, true)


func export_sheet(path: String) -> void:
	path = ensure_extension(path, "png")
	var original := frame_index
	var size: Vector2i = model.canvas_size
	var sheet := Image.create_empty(size.x * model.frames.size(), size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for index in range(model.frames.size()):
		var image := await render_frame(index)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, size), Vector2i(index * size.x, 0))
	frame_index = original
	var error := sheet.save_png(path)
	restore_preview()
	set_status("Sprite sheet exportada: %s" % path if error == OK else "Falha ao exportar sprite sheet.", error != OK)


func render_frame(index: int) -> Image:
	var previous: Dictionary = {}
	if index > 0:
		previous = model.frames[index - 1]
	pose_canvas.apply_pose(model.frames[index], model.part_library, previous, false)
	pose_canvas.set_export_mode(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func restore_preview() -> void:
	pose_canvas.set_export_mode(false)
	refresh_all()


func ensure_extension(path: String, extension: String) -> String:
	if path.get_extension().to_lower() == extension:
		return path
	return "%s.%s" % [path, extension]
