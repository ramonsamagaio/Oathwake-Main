extends "res://tools/sprite_pose_lab/scripts/WyrdframeRender.gd"

func _on_project_tree_selected() -> void:
	if rebuilding_trees:
		return
	var item: TreeItem = project_tree.get_selected()
	if item == null:
		return
	var metadata_value: Variant = item.get_metadata(0)
	if not (metadata_value is Dictionary):
		return
	var metadata: Dictionary = metadata_value as Dictionary
	var kind: String = str(metadata.get("kind", ""))
	if kind == "action":
		current_action = str(metadata.get("action", current_action))
		current_frame = 0
	elif kind == "direction":
		current_action = str(metadata.get("action", current_action))
		current_direction = str(metadata.get("direction", current_direction))
		current_frame = 0
	else:
		return
	_refresh_context()

func _on_rig_tree_selected() -> void:
	if rebuilding_trees:
		return
	var item: TreeItem = rig_tree.get_selected()
	if item != null:
		_select_bone(str(item.get_metadata(0)))

func _on_timeline_cell_input(event: InputEvent, frame_index_value: int, bone_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	current_frame = frame_index_value
	selected_bone = bone_id
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_record_history()
		var keys: Dictionary = _frame_data(frame_index_value).get("keys", {}) as Dictionary
		keys.erase(bone_id)
		_mark_changed("Key removida.", false)
	else:
		_refresh_context()

func _on_timeline_scroll_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.ctrl_pressed or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		timeline_cell_width_spin.value = minf(128.0, timeline_cell_width_spin.value + 4.0)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		timeline_cell_width_spin.value = maxf(24.0, timeline_cell_width_spin.value - 4.0)
		get_viewport().set_input_as_handled()

func _on_timeline_cell_width_changed(_value: float) -> void:
	_rebuild_timeline()

func _select_bone(bone_id: String) -> void:
	if _bone_by_id(bone_id).is_empty():
		return
	selected_bone = bone_id
	_rebuild_parent_option()
	_refresh_controls()
	_apply_render()

func _select_frame(frame_index_value: int) -> void:
	current_frame = clampi(frame_index_value, 0, maxi(0, _frames().size() - 1))
	_refresh_controls()
	_rebuild_timeline()
	_apply_render()
	call("_schedule_playback")

func _first_frame() -> void:
	_select_frame(0)

func _previous_frame() -> void:
	_select_frame(current_frame - 1)

func _next_frame() -> void:
	_select_frame(current_frame + 1)

func _last_frame() -> void:
	_select_frame(_frames().size() - 1)

func _add_frame() -> void:
	_record_history()
	var frames_value: Array = _frames()
	frames_value.insert(current_frame + 1, _new_frame())
	current_frame += 1
	_mark_changed("Quadro adicionado.", false)

func _duplicate_frame() -> void:
	_record_history()
	var duplicate_frame: Dictionary = _new_frame()
	var keys: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		keys[bone_id] = _resolved_transform(current_frame, bone_id)
	duplicate_frame["keys"] = keys
	duplicate_frame["duration"] = float(_frame_data(current_frame).get("duration", 0.125))
	_frames().insert(current_frame + 1, duplicate_frame)
	current_frame += 1
	_mark_changed("Quadro duplicado.", false)

func _remove_frame() -> void:
	if _frames().size() <= 1:
		_set_status("A direção precisa manter pelo menos um quadro.", true)
		return
	_record_history()
	_frames().remove_at(current_frame)
	current_frame = mini(current_frame, _frames().size() - 1)
	_mark_changed("Quadro removido.", false)

func _move_frame_left() -> void:
	if current_frame <= 0:
		return
	_record_history()
	var frame_value: Variant = _frames().pop_at(current_frame)
	_frames().insert(current_frame - 1, frame_value)
	current_frame -= 1
	_mark_changed("Quadro movido para a esquerda.", false)

func _move_frame_right() -> void:
	if current_frame >= _frames().size() - 1:
		return
	_record_history()
	var frame_value: Variant = _frames().pop_at(current_frame)
	_frames().insert(current_frame + 1, frame_value)
	current_frame += 1
	_mark_changed("Quadro movido para a direita.", false)

func _add_custom_action() -> void:
	_record_history()
	current_action = _add_action_data("custom", "nova_acao", false)
	current_frame = 0
	_mark_changed("Ação custom criada.", true)

func _add_preset_action() -> void:
	var preset_id: String = str(action_preset_option.get_selected_metadata())
	_record_history()
	current_action = _add_action_data(preset_id, preset_id, false)
	current_frame = 0
	_mark_changed("Preset adicionado como ação editável.", true)

func _remove_current_action() -> void:
	if _actions().size() <= 1:
		_set_status("O projeto precisa manter pelo menos uma ação.", true)
		return
	_record_history()
	_actions().erase(current_action)
	current_action = str(_actions().keys()[0])
	current_frame = 0
	_mark_changed("Ação removida.", true)

func _rename_current_action(new_name: String) -> void:
	if new_name.strip_edges().is_empty():
		return
	_record_history()
	_action_data()["name"] = new_name.strip_edges()
	_mark_changed("Ação renomeada.", true)

func _add_bone() -> void:
	_record_history()
	var existing_ids: Array = []
	for bone_value: Variant in _bones():
		existing_ids.append(str((bone_value as Dictionary).get("id", "")))
	var bone_id: String = _unique_id("novo_bone", existing_ids, "bone")
	_bones().append(_bone(bone_id, "Novo Bone", selected_bone, true, Vector2.ZERO, 0))
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_id: String in DIRECTIONS:
			var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
			var textures: Dictionary = direction_data.get("textures", {}) as Dictionary
			textures[bone_id] = ""
	selected_bone = bone_id
	_mark_changed("Bone custom criado.", true)

func _remove_bone() -> void:
	if selected_bone == "root":
		_set_status("O Root não pode ser removido.", true)
		return
	_record_history()
	var parent_id: String = str(_bone_by_id(selected_bone).get("parent", "root"))
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if str(bone_data.get("parent", "")) == selected_bone:
			bone_data["parent"] = parent_id
	for index: int in range(_bones().size() - 1, -1, -1):
		var bone_data: Dictionary = _bones()[index] as Dictionary
		if str(bone_data.get("id", "")) == selected_bone:
			_bones().remove_at(index)
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_id: String in DIRECTIONS:
			var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
			var textures: Dictionary = direction_data.get("textures", {}) as Dictionary
			textures.erase(selected_bone)
			var frames_value: Array = direction_data.get("frames", []) as Array
			for frame_value: Variant in frames_value:
				var frame_data: Dictionary = frame_value as Dictionary
				var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
				keys.erase(selected_bone)
	selected_bone = "root"
	_mark_changed("Bone removido.", true)

func _rename_bone(new_name: String) -> void:
	if new_name.strip_edges().is_empty():
		return
	_record_history()
	_bone_by_id(selected_bone)["name"] = new_name.strip_edges()
	_mark_changed("Bone renomeado.", true)

func _on_parent_selected(_index: int) -> void:
	if updating_ui or selected_bone == "root":
		return
	var new_parent: String = str(parent_option.get_selected_metadata())
	if new_parent == selected_bone or _would_create_cycle(selected_bone, new_parent):
		_set_status("Parent inválido: criaria ciclo.", true)
		_refresh_controls()
		return
	_record_history()
	_bone_by_id(selected_bone)["parent"] = new_parent
	_mark_changed("Parent atualizado.", true)

func _would_create_cycle(bone_id: String, candidate_parent: String) -> bool:
	var cursor: String = candidate_parent
	var guard: int = 0
	while not cursor.is_empty() and guard < 128:
		guard += 1
		if cursor == bone_id:
			return true
		cursor = str(_bone_by_id(cursor).get("parent", ""))
	return false

func _create_key() -> void:
	_record_history()
	_ensure_key(current_frame, selected_bone)
	_mark_changed("Key criada.", false)

func _remove_key() -> void:
	_record_history()
	var keys: Dictionary = _frame_data(current_frame).get("keys", {}) as Dictionary
	keys.erase(selected_bone)
	_mark_changed("Key removida.", false)

func _on_transform_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	if bool(bone_data.get("locked", false)):
		_refresh_controls()
		return
	_record_history()
	var position_value: Vector2 = Vector2(position_x_spin.value, position_y_spin.value)
	var pivot_value: Vector2 = Vector2(pivot_x_spin.value, pivot_y_spin.value)
	if pixel_snap_check.button_pressed:
		position_value = position_value.round()
		pivot_value = pivot_value.round()
	var transform_data: Dictionary = _transform_dict(position_value, rotation_spin.value, pivot_value, int(z_spin.value), visible_check.button_pressed)
	var keys: Dictionary = _frame_data(current_frame).get("keys", {}) as Dictionary
	keys[selected_bone] = transform_data
	_mark_changed("", false)

func _on_locked_changed(value: bool) -> void:
	if updating_ui:
		return
	_record_history()
	_bone_by_id(selected_bone)["locked"] = value
	_mark_changed("Bloqueio do bone atualizado.", true)

func _on_bone_editor_visibility_changed(value: bool) -> void:
	if updating_ui:
		return
	_record_history()
	_bone_by_id(selected_bone)["editor_visible"] = value
	_mark_changed("Visibilidade do bone no overlay atualizada.", true)
