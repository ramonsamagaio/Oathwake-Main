extends "res://tools/sprite_pose_lab/scripts/WyrdframeStudioPanels.gd"


func _rebuild_everything() -> void:
	selected_frame = clampi(selected_frame, 0, maxi(0, pose_project.frame_count() - 1))
	if pose_project.bone_by_id(selected_bone_id).is_empty():
		selected_bone_id = "torso" if not pose_project.bone_by_id("torso").is_empty() else str(pose_project.bones[0].get("id", "root"))
	_rebuild_project_tree()
	_rebuild_rig_tree()
	_rebuild_action_option()
	_rebuild_parent_option()
	timeline.set_project(pose_project)
	_refresh_ui()


func _refresh_ui() -> void:
	updating_ui = true
	project_name_edit.text = pose_project.project_name
	asset_name_edit.text = pose_project.asset_name
	_select_option_metadata(entity_type_option, pose_project.entity_type)
	_select_option_metadata(direction_option, pose_project.current_direction)
	_select_option_metadata(action_option, pose_project.current_action)
	var action_data := pose_project.current_action_data()
	action_name_edit.text = str(action_data.get("name", pose_project.current_action))
	fps_spin.value = pose_project.fps
	_select_option_metadata(loop_option, pose_project.loop_mode)
	use_frame_duration_check.button_pressed = pose_project.use_frame_durations
	frame_duration_spin.value = float(pose_project.frame_at(selected_frame).get("duration", 0.125))
	frame_duration_spin.editable = pose_project.use_frame_durations
	canvas_width_spin.value = pose_project.canvas_size.x
	canvas_height_spin.value = pose_project.canvas_size.y
	feet_y_spin.max_value = pose_project.canvas_size.y - 1
	feet_y_spin.value = pose_project.feet_y
	frame_label.text = "Frame %d / %d" % [selected_frame + 1, pose_project.frame_count()]
	play_button.text = "Pausar" if playing else "Play"
	_refresh_inspector()
	updating_ui = false
	timeline.set_selection(selected_frame, selected_bone_id)
	timeline.refresh()
	_apply_canvas()
	_update_window_title()


func _update_window_title() -> void:
	var marker := " *" if dirty else ""
	get_window().title = "%s  •  %s%s" % [PROGRAM_NAME, pose_project.project_name, marker]


func _refresh_inspector() -> void:
	var bone := pose_project.bone_by_id(selected_bone_id)
	if bone.is_empty():
		return
	var transform_data := pose_project.resolved_transform(selected_frame, selected_bone_id)
	var position_value := _vector_from(transform_data.get("position", [0.0, 0.0]))
	var pivot_value := _vector_from(transform_data.get("pivot", [0.0, 0.0]))
	bone_name_edit.text = str(bone.get("name", selected_bone_id))
	_select_option_metadata(parent_option, str(bone.get("parent", "")))
	position_x_spin.value = position_value.x
	position_y_spin.value = position_value.y
	rotation_spin.value = float(transform_data.get("rotation_degrees", 0.0))
	pivot_x_spin.value = pivot_value.x
	pivot_y_spin.value = pivot_value.y
	z_order_spin.value = int(transform_data.get("z_index", 0))
	visible_check.button_pressed = bool(transform_data.get("visible", true))
	locked_check.button_pressed = bool(bone.get("locked", false))
	var constraints: Dictionary = bone.get("constraints", {})
	rotation_min_spin.value = float(constraints.get("rotation_min", -180.0))
	rotation_max_spin.value = float(constraints.get("rotation_max", 180.0))
	foot_contact_check.button_pressed = bool(constraints.get("foot_contact", false))
	keyed_label.text = "● Keyframe neste quadro" if pose_project.is_keyed(selected_frame, selected_bone_id) else "○ Herdando pose anterior"
	var path := pose_project.texture_path(pose_project.current_direction, selected_bone_id)
	texture_path_label.text = "Sem PNG nesta ação/direção: placeholder ativo" if path.is_empty() else path


func _apply_canvas() -> void:
	if pose_canvas == null:
		return
	render_viewport.size = pose_project.canvas_size
	pose_canvas.set_project(pose_project)
	pose_canvas.set_editor_settings(_view_settings())
	pose_canvas.apply_frame(selected_frame, selected_bone_id)
	_update_preview_size()


func _view_settings() -> Dictionary:
	return {
		"checkerboard": checker_check.button_pressed,
		"grid": grid_check.button_pressed,
		"axis": axis_check.button_pressed,
		"feet_line": feet_line_check.button_pressed,
		"gizmo": gizmo_check.button_pressed,
		"pixel_snap": pixel_snap_check.button_pressed,
		"previous_enabled": previous_check.button_pressed,
		"next_enabled": next_check.button_pressed,
		"previous_opacity": previous_opacity.value,
		"next_opacity": next_opacity.value,
	}


func _rebuild_project_tree() -> void:
	project_tree.clear()
	var hidden_root := project_tree.create_item()
	var project_item := project_tree.create_item(hidden_root)
	project_item.set_text(0, "%s  [%s]" % [pose_project.project_name, ENTITY_LABELS.get(pose_project.entity_type, pose_project.entity_type)])
	project_item.set_metadata(0, {"kind": "project"})
	for action_id in pose_project.action_ids():
		var action: Dictionary = pose_project.actions[action_id]
		var action_item := project_tree.create_item(project_item)
		action_item.set_text(0, str(action.get("name", action_id)))
		action_item.set_metadata(0, {"kind": "action", "action": str(action_id)})
		for direction in pose_project.DIRECTIONS:
			var direction_item := project_tree.create_item(action_item)
			direction_item.set_text(0, DIRECTION_LABELS.get(direction, direction))
			direction_item.set_metadata(0, {
				"kind": "direction",
				"action": str(action_id),
				"direction": direction,
			})
			if str(action_id) == pose_project.current_action and direction == pose_project.current_direction:
				direction_item.select(0)
	project_item.set_collapsed(false)


func _rebuild_rig_tree() -> void:
	rig_tree.clear()
	var hidden_root := rig_tree.create_item()
	var item_map: Dictionary = {"": hidden_root}
	var pending := pose_project.bones.duplicate(true)
	var guard := 0
	while not pending.is_empty() and guard < pose_project.bones.size() * 3:
		guard += 1
		for index in range(pending.size() - 1, -1, -1):
			var bone: Dictionary = pending[index]
			var bone_id := str(bone.get("id", ""))
			var parent_id := str(bone.get("parent", ""))
			if not item_map.has(parent_id):
				continue
			var item := rig_tree.create_item(item_map[parent_id])
			item.set_text(0, str(bone.get("name", bone_id)))
			item.set_metadata(0, bone_id)
			item_map[bone_id] = item
			pending.remove_at(index)
	if item_map.has(selected_bone_id):
		item_map[selected_bone_id].select(0)


func _rebuild_parent_option() -> void:
	parent_option.clear()
	parent_option.add_item("Sem parent")
	parent_option.set_item_metadata(0, "")
	for bone in pose_project.bones:
		var bone_id := str(bone.get("id", ""))
		if bone_id == selected_bone_id:
			continue
		parent_option.add_item(str(bone.get("name", bone_id)))
		parent_option.set_item_metadata(parent_option.item_count - 1, bone_id)


func _rebuild_action_option() -> void:
	action_option.clear()
	for action_id in pose_project.action_ids():
		var action: Dictionary = pose_project.actions[action_id]
		action_option.add_item(str(action.get("name", action_id)))
		action_option.set_item_metadata(action_option.item_count - 1, str(action_id))


func _new_project() -> void:
	var kind := str(entity_type_option.get_selected_metadata()) if entity_type_option != null else "character"
	pose_project.reset_project(kind)
	selected_bone_id = "torso"
	selected_frame = 0
	current_project_path = ""
	undo_stack.clear()
	redo_stack.clear()
	dirty = false
	_rebuild_everything()
	_update_window_title()
	_set_status("Novo projeto %s criado." % ENTITY_LABELS.get(kind, kind))


func _on_project_name_changed(value: String) -> void:
	if updating_ui:
		return
	pose_project.project_name = value.strip_edges() if not value.strip_edges().is_empty() else "Projeto sem nome"
	_rebuild_project_tree()
	_mark_changed()


func _on_asset_name_changed(value: String) -> void:
	if updating_ui:
		return
	pose_project.asset_name = value.strip_edges() if not value.strip_edges().is_empty() else "asset"
	_mark_changed()


func _on_entity_type_selected(_index: int) -> void:
	if updating_ui:
		return
	pose_project.entity_type = str(entity_type_option.get_selected_metadata())
	_mark_changed("Tipo alterado. Use 'Adicionar estrutura sugerida' sem apagar suas ações existentes.")


func _apply_entity_starter() -> void:
	_record_history()
	pose_project.apply_entity_template(str(entity_type_option.get_selected_metadata()), true)
	_rebuild_everything()
	_mark_changed("Ações sugeridas adicionadas sem remover as ações custom existentes.")


func _on_project_tree_selected() -> void:
	var item := project_tree.get_selected()
	if item == null:
		return
	var metadata_value: Variant = item.get_metadata(0)
	if not (metadata_value is Dictionary):
		return
	var data: Dictionary = metadata_value
	var kind := str(data.get("kind", ""))
	if kind == "action" or kind == "direction":
		pose_project.current_action = str(data.get("action", pose_project.current_action))
		if kind == "direction":
			pose_project.current_direction = str(data.get("direction", pose_project.current_direction))
		selected_frame = 0
		_rebuild_action_option()
		_refresh_ui()


func _add_preset_action() -> void:
	_record_history()
	var preset_id := str(action_preset_option.get_selected_metadata())
	pose_project.current_action = pose_project.add_action_from_preset(preset_id, "", pose_project.current_action)
	selected_frame = 0
	_rebuild_everything()
	_mark_changed("Ação preset criada com quatro direções e sprites clonados da ação anterior.")


func _add_custom_action() -> void:
	_record_history()
	pose_project.current_action = pose_project.add_custom_action("Nova ação custom", true)
	selected_frame = 0
	_rebuild_everything()
	_mark_changed("Ação custom criada com quatro direções.")


func _remove_action() -> void:
	_record_history()
	var old_action := pose_project.current_action
	if not pose_project.remove_action(old_action):
		_set_status("O projeto precisa manter pelo menos uma ação.", true)
		return
	selected_frame = 0
	_rebuild_everything()
	_mark_changed("Ação removida.")


func _on_action_name_changed(value: String) -> void:
	if updating_ui:
		return
	pose_project.rename_action(pose_project.current_action, value)
	_rebuild_action_option()
	_rebuild_project_tree()
	_mark_changed()


func _apply_preset_all_directions() -> void:
	_record_history()
	var preset_id := str(action_preset_option.get_selected_metadata())
	var original_direction := pose_project.current_direction
	for direction in pose_project.DIRECTIONS:
		pose_project.current_direction = direction
		pose_project.apply_animation_preset(preset_id, false)
	pose_project.current_direction = original_direction
	selected_frame = 0
	_rebuild_everything()
	_mark_changed("Preset aplicado às quatro direções da ação atual.")


func _on_action_selected(_index: int) -> void:
	if updating_ui:
		return
	pose_project.current_action = str(action_option.get_selected_metadata())
	selected_frame = 0
	_rebuild_project_tree()
	_refresh_ui()


func _on_direction_selected(_index: int) -> void:
	if updating_ui:
		return
	pose_project.current_direction = str(direction_option.get_selected_metadata())
	selected_frame = 0
	_rebuild_project_tree()
	_refresh_ui()


func _on_tree_selected() -> void:
	var item := rig_tree.get_selected()
	if item != null:
		_select_bone(str(item.get_metadata(0)))


func _select_bone(bone_id: String) -> void:
	if pose_project.bone_by_id(bone_id).is_empty():
		return
	selected_bone_id = bone_id
	_rebuild_parent_option()
	_refresh_ui()


func _select_frame(frame_number: int) -> void:
	selected_frame = clampi(frame_number, 0, maxi(0, pose_project.frame_count() - 1))
	_refresh_ui()
	_schedule_playback()


func _on_timeline_cell_selected(frame_number: int, bone_id: String) -> void:
	selected_frame = frame_number
	selected_bone_id = bone_id
	_rebuild_parent_option()
	_rebuild_rig_tree()
	_refresh_ui()


func _on_timeline_remove_key(frame_number: int, bone_id: String) -> void:
	_record_history()
	pose_project.remove_key(frame_number, bone_id)
	_mark_changed("Keyframe removido.")


func _apply_humanoid_preset() -> void:
	_record_history()
	pose_project.create_humanoid_basic()
	selected_bone_id = "torso"
	selected_frame = 0
	_rebuild_everything()
	_mark_changed("Preset Humanoid Basic aplicado sem apagar ações.")


func _add_bone() -> void:
	_record_history()
	var parent_id := selected_bone_id if not pose_project.bone_by_id(selected_bone_id).is_empty() else "root"
	selected_bone_id = pose_project.add_custom_bone("Novo Bone", parent_id, true)
	_rebuild_everything()
	_mark_changed("Bone custom criado. Renomeie-o no Inspector.")


func _remove_bone() -> void:
	if selected_bone_id == "root":
		_set_status("O Root não pode ser removido.", true)
		return
	_record_history()
	if pose_project.remove_bone(selected_bone_id):
		selected_bone_id = "root"
		_rebuild_everything()
		_mark_changed("Bone removido; filhos foram ligados ao parent anterior.")


func _on_bone_name_changed(value: String) -> void:
	if updating_ui:
		return
	pose_project.rename_bone(selected_bone_id, value)
	_rebuild_rig_tree()
	_mark_changed()


func _on_parent_changed(_index: int) -> void:
	if updating_ui:
		return
	var parent_id := str(parent_option.get_selected_metadata())
	_record_history()
	if not pose_project.set_bone_parent(selected_bone_id, parent_id):
		_set_status("Parent inválido ou criaria uma hierarquia circular.", true)
	_rebuild_everything()
	_mark_changed()


func _on_transform_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	var bone := pose_project.bone_by_id(selected_bone_id)
	if bool(bone.get("locked", false)):
		_set_status("Este bone está bloqueado.", true)
		_refresh_ui()
		return
	_record_history()
	var transform_data := {
		"position": [position_x_spin.value, position_y_spin.value],
		"rotation_degrees": rotation_spin.value,
		"pivot": [pivot_x_spin.value, pivot_y_spin.value],
		"z_index": int(z_order_spin.value),
		"visible": visible_check.button_pressed,
	}
	if pixel_snap_check.button_pressed:
		transform_data["position"] = [roundf(position_x_spin.value), roundf(position_y_spin.value)]
		transform_data["pivot"] = [roundf(pivot_x_spin.value), roundf(pivot_y_spin.value)]
	pose_project.set_transform(selected_frame, selected_bone_id, transform_data)
	_mark_changed()


func _on_bone_settings_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	_record_history()
	var bone := pose_project.bone_by_id(selected_bone_id)
	if bone.is_empty():
		return
	bone["locked"] = locked_check.button_pressed
	bone["constraints"] = {
		"rotation_min": rotation_min_spin.value,
		"rotation_max": rotation_max_spin.value,
		"foot_contact": foot_contact_check.button_pressed,
	}
	_rebuild_rig_tree()
	_mark_changed()


func _create_key() -> void:
	_record_history()
	pose_project.ensure_key(selected_frame, selected_bone_id)
	_mark_changed("Keyframe criado.")


func _remove_current_key() -> void:
	_record_history()
	pose_project.remove_key(selected_frame, selected_bone_id)
	_mark_changed("Keyframe removido.")


func _add_frame() -> void:
	_record_history()
	selected_frame = pose_project.insert_frame(selected_frame, false)
	_mark_changed("Quadro vazio adicionado.")


func _duplicate_frame() -> void:
	_record_history()
	selected_frame = pose_project.insert_frame(selected_frame, true)
	_mark_changed("Quadro duplicado como pose completa.")


func _remove_frame() -> void:
	_record_history()
	var before := pose_project.frame_count()
	selected_frame = pose_project.remove_frame(selected_frame)
	if before == 1:
		_set_status("Cada direção precisa manter pelo menos um quadro.", true)
	else:
		_mark_changed("Quadro removido.")


func _move_frame_left() -> void:
	if selected_frame <= 0:
		return
	_record_history()
	selected_frame = pose_project.move_frame(selected_frame, selected_frame - 1)
	_mark_changed("Quadro movido para a esquerda.")


func _move_frame_right() -> void:
	if selected_frame >= pose_project.frame_count() - 1:
		return
	_record_history()
	selected_frame = pose_project.move_frame(selected_frame, selected_frame + 1)
	_mark_changed("Quadro movido para a direita.")


func _on_fps_changed(value: float) -> void:
	if updating_ui:
		return
	pose_project.fps = value
	_schedule_playback()
	_mark_changed()


func _on_loop_changed(_index: int) -> void:
	if updating_ui:
		return
	pose_project.loop_mode = str(loop_option.get_selected_metadata())
	_mark_changed()


func _on_frame_duration_mode_changed(value: bool) -> void:
	if updating_ui:
		return
	pose_project.use_frame_durations = value
	_mark_changed()


func _on_frame_duration_changed(value: float) -> void:
	if updating_ui:
		return
	pose_project.frame_at(selected_frame)["duration"] = maxf(0.01, value)
	_schedule_playback()
	_mark_changed()


func _on_canvas_changed(_value: float) -> void:
	if updating_ui:
		return
	pose_project.canvas_size = Vector2i(int(canvas_width_spin.value), int(canvas_height_spin.value))
	pose_project.feet_y = clampi(int(feet_y_spin.value), 0, pose_project.canvas_size.y - 1)
	render_viewport.size = pose_project.canvas_size
	_mark_changed()


func _toggle_playback() -> void:
	playing = not playing
	playback_direction = 1
	if not playing:
		playback_timer.stop()
	_refresh_ui()
	_schedule_playback()


func _schedule_playback() -> void:
	playback_timer.stop()
	if not playing:
		return
	var wait_time := 1.0 / maxf(1.0, pose_project.fps)
	if pose_project.use_frame_durations:
		wait_time = maxf(0.01, float(pose_project.frame_at(selected_frame).get("duration", 0.125)))
	playback_timer.start(wait_time)


func _on_playback_timeout() -> void:
	if not playing:
		return
	var last := pose_project.frame_count() - 1
	if pose_project.loop_mode == "pingpong":
		if selected_frame >= last:
			playback_direction = -1
		elif selected_frame <= 0:
			playback_direction = 1
		_select_frame(selected_frame + playback_direction)
	elif pose_project.loop_mode == "once":
		if selected_frame >= last:
			playing = false
			_refresh_ui()
		else:
			_select_frame(selected_frame + 1)
	else:
		_select_frame(posmod(selected_frame + 1, pose_project.frame_count()))


func _on_view_setting_changed(_value: Variant = null) -> void:
	if not updating_ui:
		_apply_canvas()


func _on_zoom_changed(_index: int) -> void:
	_update_preview_size()


func _update_preview_size() -> void:
	if preview == null:
		return
	var zoom := 6
	if zoom_option != null:
		zoom = int(zoom_option.get_selected_id())
	preview.custom_minimum_size = Vector2(pose_project.canvas_size * zoom)
	preview.size = Vector2(pose_project.canvas_size * zoom)


func _on_preview_input(event: InputEvent) -> void:
	if pose_canvas == null:
		return
	var zoom := float(zoom_option.get_selected_id())
	if zoom <= 0.0:
		zoom = 1.0
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var canvas_position := mouse_event.position / zoom
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var hit_bone := pose_canvas.hit_test_bone(canvas_position)
			if not hit_bone.is_empty() and hit_bone != selected_bone_id:
				_select_bone(hit_bone)
			var force_pivot := mouse_event.alt_pressed
			drag_mode = pose_canvas.hit_test_handle(canvas_position, force_pivot)
			if drag_mode.is_empty() and not hit_bone.is_empty():
				drag_mode = pose_canvas.HANDLE_MOVE
			if not drag_mode.is_empty():
				_record_history()
				drag_start_canvas = canvas_position
				drag_start_transform = pose_project.resolved_transform(selected_frame, selected_bone_id)
				var pivot_position := pose_canvas.bone_canvas_position(selected_bone_id)
				drag_start_angle = pivot_position.angle_to_point(canvas_position)
				accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			drag_mode = ""
			accept_event()
	elif event is InputEventMouseMotion and not drag_mode.is_empty():
		var motion := event as InputEventMouseMotion
		var canvas_position := motion.position / zoom
		_apply_gizmo_drag(canvas_position, motion.shift_pressed)
		accept_event()


func _apply_gizmo_drag(canvas_position: Vector2, angle_snap: bool) -> void:
	var transform_data := drag_start_transform.duplicate(true)
	var start_position := _vector_from(transform_data.get("position", [0.0, 0.0]))
	var start_pivot := _vector_from(transform_data.get("pivot", [0.0, 0.0]))
	var delta_canvas := canvas_position - drag_start_canvas
	if drag_mode == pose_canvas.HANDLE_MOVE:
		var local_delta := pose_canvas.canvas_delta_to_parent_local(selected_bone_id, delta_canvas)
		var result_position := start_position + local_delta
		if pixel_snap_check.button_pressed:
			result_position = result_position.round()
		transform_data["position"] = [result_position.x, result_position.y]
	elif drag_mode == pose_canvas.HANDLE_ROTATE:
		var pivot_position := pose_canvas.bone_canvas_position(selected_bone_id)
		var current_angle := pivot_position.angle_to_point(canvas_position)
		var result_rotation := float(drag_start_transform.get("rotation_degrees", 0.0)) + rad_to_deg(current_angle - drag_start_angle)
		if angle_snap:
			result_rotation = roundf(result_rotation / 15.0) * 15.0
		var bone := pose_project.bone_by_id(selected_bone_id)
		var constraints: Dictionary = bone.get("constraints", {})
		result_rotation = clampf(result_rotation, float(constraints.get("rotation_min", -720.0)), float(constraints.get("rotation_max", 720.0)))
		transform_data["rotation_degrees"] = result_rotation
	elif drag_mode == pose_canvas.HANDLE_PIVOT:
		var global_rotation := pose_canvas.selected_global_rotation()
		var pivot_delta_local := delta_canvas.rotated(-global_rotation)
		var result_pivot := start_pivot + pivot_delta_local
		if pixel_snap_check.button_pressed:
			result_pivot = result_pivot.round()
		var pivot_change := result_pivot - start_pivot
		var local_rotation := deg_to_rad(float(drag_start_transform.get("rotation_degrees", 0.0)))
		var result_position := start_position + pivot_change.rotated(local_rotation)
		if pixel_snap_check.button_pressed:
			result_position = result_position.round()
		transform_data["pivot"] = [result_pivot.x, result_pivot.y]
		transform_data["position"] = [result_position.x, result_position.y]
	pose_project.set_transform(selected_frame, selected_bone_id, transform_data)
	_mark_changed()
