extends "res://tools/sprite_pose_lab/scripts/WyrdframeInteractionCore.gd"

func _on_project_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["name"] = value
	_mark_changed("", true)

func _on_asset_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["asset_name"] = value
	_mark_changed("", false)

func _on_entity_selected(_index: int) -> void:
	if updating_ui:
		return
	_project_section()["entity_type"] = str(entity_option.get_selected_metadata())
	_mark_changed("Tipo de projeto atualizado. Estrutura custom preservada.", false)

func _on_direction_selected(_index: int) -> void:
	if updating_ui:
		return
	current_direction = str(direction_option.get_selected_metadata())
	current_frame = 0
	_refresh_context()
	_select_current_project_tree_item()

func _on_fps_changed(value: float) -> void:
	if updating_ui:
		return
	_playback_section()["fps"] = value
	_mark_changed("", false)

func _on_loop_selected(_index: int) -> void:
	if updating_ui:
		return
	_playback_section()["loop_mode"] = str(loop_option.get_selected_metadata())
	_mark_changed("", false)

func _on_duration_mode_changed(value: bool) -> void:
	if updating_ui:
		return
	_playback_section()["use_frame_durations"] = value
	_mark_changed("", false)

func _on_frame_duration_changed(value: float) -> void:
	if updating_ui:
		return
	_frame_data(current_frame)["duration"] = maxf(0.01, value)
	_mark_changed("", false)

func _on_view_setting_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	_apply_render()

func _on_zoom_selected(_index: int) -> void:
	_update_preview_size()

func _select_current_project_tree_item() -> void:
	var root_item: TreeItem = project_tree.get_root()
	if root_item == null:
		return
	var project_item: TreeItem = root_item.get_first_child()
	if project_item == null:
		return
	var action_item: TreeItem = project_item.get_first_child()
	while action_item != null:
		var action_meta_value: Variant = action_item.get_metadata(0)
		if action_meta_value is Dictionary:
			var action_meta: Dictionary = action_meta_value as Dictionary
			if str(action_meta.get("action", "")) == current_action:
				var direction_item: TreeItem = action_item.get_first_child()
				while direction_item != null:
					var direction_meta_value: Variant = direction_item.get_metadata(0)
					if direction_meta_value is Dictionary:
						var direction_meta: Dictionary = direction_meta_value as Dictionary
						if str(direction_meta.get("direction", "")) == current_direction:
							rebuilding_trees = true
							direction_item.select(0)
							rebuilding_trees = false
							return
					direction_item = direction_item.get_next()
		action_item = action_item.get_next()

func _on_preview_input(event: InputEvent) -> void:
	var zoom_value: float = float(maxi(1, zoom_option.get_selected_id()))
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		var canvas_position: Vector2 = mouse_event.position / zoom_value
		if mouse_event.pressed:
			var hit_bone: String = str(canvas_renderer.hit_test_bone(canvas_position))
			if not hit_bone.is_empty():
				selected_bone = hit_bone
				_refresh_controls()
				_rebuild_rig_tree()
				_apply_render()
			drag_active = true
			drag_history_recorded = false
			drag_start_canvas = canvas_position
			drag_start_position = _vec(_resolved_transform(current_frame, selected_bone).get("position", [0.0, 0.0]))
		else:
			drag_active = false
			drag_history_recorded = false
	elif event is InputEventMouseMotion and drag_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var canvas_position: Vector2 = motion_event.position / zoom_value
		if not drag_history_recorded:
			_record_history()
			drag_history_recorded = true
		var canvas_delta: Vector2 = canvas_position - drag_start_canvas
		var local_delta: Vector2 = canvas_renderer.parent_local_delta(selected_bone, canvas_delta) as Vector2
		var new_position: Vector2 = drag_start_position + local_delta
		if pixel_snap_check.button_pressed:
			new_position = new_position.round()
		var transform_data: Dictionary = _ensure_key(current_frame, selected_bone)
		transform_data["position"] = [new_position.x, new_position.y]
		dirty = true
		autosave_timer.start()
		_refresh_controls()
		_apply_render()

func _toggle_playback() -> void:
	playing = not playing
	playback_direction = 1
	if not playing:
		playback_timer.stop()
	_refresh_controls()
	_schedule_playback()

func _schedule_playback() -> void:
	playback_timer.stop()
	if not playing:
		return
	var playback_data: Dictionary = _playback_section()
	var wait_time: float = 1.0 / maxf(1.0, float(playback_data.get("fps", 8.0)))
	if bool(playback_data.get("use_frame_durations", false)):
		wait_time = maxf(0.01, float(_frame_data(current_frame).get("duration", 0.125)))
	playback_timer.start(wait_time)

func _on_playback_timeout() -> void:
	if not playing:
		return
	var last_index: int = _frames().size() - 1
	var loop_mode: String = str(_playback_section().get("loop_mode", "loop"))
	if loop_mode == "pingpong":
		if current_frame >= last_index:
			playback_direction = -1
		elif current_frame <= 0:
			playback_direction = 1
		_select_frame(current_frame + playback_direction)
	elif loop_mode == "once":
		if current_frame >= last_index:
			playing = false
			_refresh_controls()
		else:
			_select_frame(current_frame + 1)
	else:
		_select_frame(posmod(current_frame + 1, _frames().size()))

func _on_new_project_type_selected(menu_id: int) -> void:
	var entity_ids: Array[String] = ["character", "monster", "boss", "custom"]
	var entity_type: String = "character"
	if menu_id >= 0 and menu_id < entity_ids.size():
		entity_type = entity_ids[menu_id]
	_create_new_document(entity_type)
	_rebuild_structure()
	_set_status("Novo projeto de %s criado." % ENTITY_LABELS.get(entity_type, entity_type))
