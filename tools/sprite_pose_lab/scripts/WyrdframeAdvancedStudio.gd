extends "res://tools/sprite_pose_lab/scripts/WyrdframeStudio.gd"

const AdvancedCanvasScript: Script = preload("res://tools/sprite_pose_lab/scripts/WyrdframeAdvancedCanvas.gd")

var grid_check: CheckBox
var layers_tree: Tree
var bone_color_picker: ColorPickerButton
var bone_thickness_spin: SpinBox
var bone_length_spin: SpinBox
var bone_angle_spin: SpinBox
var parent_endpoint_option: OptionButton
var self_endpoint_option: OptionButton

var _active_render_scale: float = 1.0
var _render_refresh_active: bool = false
var _pick_candidates: Array[String] = []
var _pick_cycle_index: int = 0
var _last_pick_canvas: Vector2 = Vector2(INF, INF)


func _build_left_panel() -> Control:
	var tabs: TabContainer = super._build_left_panel() as TabContainer
	var layers_tab: VBoxContainer = VBoxContainer.new()
	layers_tab.name = "Camadas"
	layers_tab.add_theme_constant_override("separation", 7)
	layers_tab.add_child(_section_label("ORDEM VISUAL DOS SPRITES"))
	var explanation: Label = Label.new()
	explanation.text = "Arraste as camadas. O item mais alto aparece na frente do personagem."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.67, 0.75, 0.82)
	layers_tab.add_child(explanation)
	layers_tree = Tree.new()
	layers_tree.hide_root = true
	layers_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layers_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layers_tree.custom_minimum_size.y = 300
	layers_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
	layers_tree.item_selected.connect(Callable(self, "_on_layer_selected"))
	layers_tree.set_drag_forwarding(
		Callable(self, "_layer_get_drag_data"),
		Callable(self, "_layer_can_drop_data"),
		Callable(self, "_layer_drop_data")
	)
	layers_tab.add_child(layers_tree)
	var layer_note: Label = Label.new()
	layer_note.text = "A ordem é do bone inteiro: o PNG ligado a ele acompanha esta camada em todos os frames."
	layer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer_note.modulate = Color(0.58, 0.69, 0.77)
	layers_tab.add_child(layer_note)
	tabs.add_child(layers_tab)
	return tabs


func _build_preview_panel() -> Control:
	var result: Control = super._build_preview_panel()
	var column: VBoxContainer = result as VBoxContainer
	var advanced_row: HBoxContainer = HBoxContainer.new()
	advanced_row.add_theme_constant_override("separation", 8)
	grid_check = _check("Grid", false, Callable(self, "_on_view_setting_changed"))
	grid_check.tooltip_text = "Liga o grid de pixels. Em zoom baixo, mostra apenas divisões maiores para não poluir."
	advanced_row.add_child(grid_check)
	var vector_note: Label = Label.new()
	vector_note.text = "Bones vetoriais em alta resolução"
	vector_note.modulate = Color(0.55, 0.82, 0.94)
	advanced_row.add_child(vector_note)
	column.add_child(advanced_row)
	column.move_child(advanced_row, 1)
	return result


func _build_inspector() -> Control:
	var result: Control = super._build_inspector()
	var scroll: ScrollContainer = result as ScrollContainer
	var column: VBoxContainer = scroll.get_child(0) as VBoxContainer
	column.add_child(HSeparator.new())
	column.add_child(_section_label("GEOMETRIA REAL DO BONE"))
	var geometry_grid: GridContainer = GridContainer.new()
	geometry_grid.columns = 2
	bone_length_spin = _spin_row(geometry_grid, "Comprimento", 0.0, 2048.0, 0.5)
	bone_length_spin.suffix = " px"
	bone_angle_spin = _spin_row(geometry_grid, "Ângulo da haste", -720.0, 720.0, 0.5)
	bone_angle_spin.suffix = "°"
	column.add_child(geometry_grid)
	bone_length_spin.value_changed.connect(Callable(self, "_on_bone_geometry_changed"))
	bone_angle_spin.value_changed.connect(Callable(self, "_on_bone_geometry_changed"))
	parent_endpoint_option = OptionButton.new()
	parent_endpoint_option.add_item("Início do parent")
	parent_endpoint_option.set_item_metadata(0, "start")
	parent_endpoint_option.add_item("Fim do parent")
	parent_endpoint_option.set_item_metadata(1, "end")
	parent_endpoint_option.item_selected.connect(Callable(self, "_on_attachment_changed"))
	column.add_child(_labeled("Ponta usada no parent", parent_endpoint_option))
	self_endpoint_option = OptionButton.new()
	self_endpoint_option.add_item("Início deste bone")
	self_endpoint_option.set_item_metadata(0, "start")
	self_endpoint_option.add_item("Fim deste bone")
	self_endpoint_option.set_item_metadata(1, "end")
	self_endpoint_option.item_selected.connect(Callable(self, "_on_attachment_changed"))
	column.add_child(_labeled("Ponta deste bone que gruda", self_endpoint_option))
	var endpoint_note: Label = Label.new()
	endpoint_note.text = "O padrão de rig é início → fim: o começo do bone filho gruda na ponta final do parent. As quatro combinações continuam disponíveis."
	endpoint_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	endpoint_note.modulate = Color(0.62, 0.72, 0.8)
	column.add_child(endpoint_note)
	column.add_child(HSeparator.new())
	column.add_child(_section_label("APARÊNCIA DO BONE NO EDITOR"))
	bone_color_picker = ColorPickerButton.new()
	bone_color_picker.custom_minimum_size.y = 32
	bone_color_picker.color_changed.connect(Callable(self, "_on_bone_color_changed"))
	column.add_child(_labeled("Cor", bone_color_picker))
	bone_thickness_spin = _spin(2.0, 32.0, 0.5)
	bone_thickness_spin.suffix = " px"
	bone_thickness_spin.value_changed.connect(Callable(self, "_on_bone_thickness_changed"))
	column.add_child(_labeled("Espessura na tela", bone_thickness_spin))
	return result


func _build_rendering() -> void:
	render_viewport = SubViewport.new()
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	render_viewport.msaa_2d = Viewport.MSAA_DISABLED
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(render_viewport)
	canvas_renderer = AdvancedCanvasScript.new()
	render_viewport.add_child(canvas_renderer)
	preview.texture = render_viewport.get_texture()
	_apply_render()


func _view_settings() -> Dictionary:
	var settings: Dictionary = super._view_settings()
	settings["grid"] = grid_check != null and grid_check.button_pressed
	settings["display_scale"] = _active_render_scale
	return settings


func _apply_render() -> void:
	if canvas_renderer == null or render_viewport == null:
		return
	_ensure_advanced_editor_data()
	var canvas_data: Dictionary = _canvas_section()
	var native_size: Vector2i = Vector2i(
		maxi(1, int(canvas_data.get("width", 64))),
		maxi(1, int(canvas_data.get("height", 64)))
	)
	var zoom_value: int = 1
	if zoom_option != null:
		zoom_value = maxi(1, zoom_option.get_selected_id())
	var export_active: bool = bool(canvas_renderer.export_mode)
	var render_scale: int = 1 if export_active else zoom_value
	_active_render_scale = float(render_scale)
	_render_refresh_active = true
	render_viewport.size = native_size * render_scale
	canvas_renderer.scale = Vector2(float(render_scale), float(render_scale))
	canvas_renderer.configure(
		document,
		current_action,
		current_direction,
		current_frame,
		selected_bone,
		_view_settings()
	)
	var preview_size: Vector2 = Vector2(render_viewport.size)
	preview.custom_minimum_size = preview_size
	preview.size = preview_size
	_render_refresh_active = false


func _update_preview_size() -> void:
	if _render_refresh_active:
		return
	_apply_render()


func _rebuild_structure() -> void:
	_ensure_advanced_editor_data()
	super._rebuild_structure()
	_rebuild_layers_tree()


func _refresh_context() -> void:
	_ensure_advanced_editor_data()
	super._refresh_context()
	_rebuild_layers_tree()


func _refresh_inspector() -> void:
	super._refresh_inspector()
	if bone_color_picker == null:
		return
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	if bone_data.is_empty():
		return
	bone_color_picker.color = Color.from_string(str(bone_data.get("editor_color", "#5ccdf8")), Color(0.36, 0.82, 0.98))
	bone_thickness_spin.value = float(bone_data.get("editor_thickness", 6.0))
	bone_length_spin.value = float(bone_data.get("length", 12.0))
	bone_angle_spin.value = float(bone_data.get("bone_angle_degrees", 0.0))
	var attachment: Dictionary = bone_data.get("attachment", {}) as Dictionary
	_select_option_by_metadata(parent_endpoint_option, str(attachment.get("parent_endpoint", "start")))
	_select_option_by_metadata(self_endpoint_option, str(attachment.get("self_endpoint", "start")))
	var has_parent: bool = not str(bone_data.get("parent", "")).is_empty()
	parent_endpoint_option.disabled = not has_parent
	self_endpoint_option.disabled = not has_parent
	z_spin.editable = false
	z_spin.tooltip_text = "A ordem visual é controlada somente arrastando os itens na aba Camadas."


func _select_bone(bone_id: String) -> void:
	super._select_bone(bone_id)
	_rebuild_layers_tree()


func _add_bone() -> void:
	super._add_bone()
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	if bone_data.is_empty():
		return
	bone_data["length"] = 16.0
	bone_data["bone_angle_degrees"] = 0.0
	bone_data["attachment"] = {
		"parent_endpoint": "end",
		"self_endpoint": "start",
	}
	bone_data["editor_color"] = _default_bone_color(selected_bone)
	bone_data["editor_thickness"] = 6.0
	_ensure_advanced_editor_data()
	_apply_layer_order_to_z()
	_mark_changed("Bone criado com duas pontas e ligação início → fim.", true)


func _on_bone_color_changed(value: Color) -> void:
	if updating_ui:
		return
	_record_history()
	_bone_by_id(selected_bone)["editor_color"] = value.to_html()
	_mark_changed("Cor do bone atualizada.", false)


func _on_bone_thickness_changed(value: float) -> void:
	if updating_ui:
		return
	_record_history()
	_bone_by_id(selected_bone)["editor_thickness"] = clampf(value, 2.0, 32.0)
	_mark_changed("Espessura do bone atualizada.", false)


func _on_bone_geometry_changed(_value: float) -> void:
	if updating_ui:
		return
	_record_history()
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	bone_data["length"] = maxf(0.0, bone_length_spin.value)
	bone_data["bone_angle_degrees"] = bone_angle_spin.value
	_mark_changed("Geometria do bone atualizada.", false)


func _on_attachment_changed(_index: int) -> void:
	if updating_ui or selected_bone == "root":
		return
	_record_history()
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	bone_data["attachment"] = {
		"parent_endpoint": str(parent_endpoint_option.get_selected_metadata()),
		"self_endpoint": str(self_endpoint_option.get_selected_metadata()),
	}
	_mark_changed("Ligação entre as pontas dos bones atualizada.", true)


func _ensure_advanced_editor_data() -> void:
	if document.is_empty():
		return
	var rig_data: Dictionary = _rig_section()
	var palette_index: int = 0
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		if not bone_data.has("editor_color"):
			bone_data["editor_color"] = _default_bone_color(bone_id, palette_index)
		if not bone_data.has("editor_thickness"):
			bone_data["editor_thickness"] = 6.0
		if not bone_data.has("length") or not bone_data.has("bone_angle_degrees"):
			var geometry: Dictionary = _derive_bone_geometry(bone_id)
			if not bone_data.has("length"):
				bone_data["length"] = float(geometry.get("length", 12.0))
			if not bone_data.has("bone_angle_degrees"):
				bone_data["bone_angle_degrees"] = float(geometry.get("angle", 0.0))
		if not bone_data.has("attachment"):
			# Legacy projects keep their exact positions. The user can switch either endpoint explicitly.
			bone_data["attachment"] = {
				"parent_endpoint": "start",
				"self_endpoint": "start",
			}
		palette_index += 1
	var current_order: Array = rig_data.get("layer_order", []) as Array
	var valid_ids: Array[String] = []
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if bool(bone_data.get("has_sprite", true)):
			valid_ids.append(str(bone_data.get("id", "")))
	var clean_order: Array[String] = []
	for order_value: Variant in current_order:
		var bone_id: String = str(order_value)
		if valid_ids.has(bone_id) and not clean_order.has(bone_id):
			clean_order.append(bone_id)
	for bone_id: String in _ids_sorted_by_current_z(valid_ids):
		if not clean_order.has(bone_id):
			clean_order.append(bone_id)
	rig_data["layer_order"] = clean_order


func _derive_bone_geometry(bone_id: String) -> Dictionary:
	for bone_value: Variant in _bones():
		var child_data: Dictionary = bone_value as Dictionary
		if str(child_data.get("parent", "")) != bone_id:
			continue
		var child_rest: Dictionary = child_data.get("rest", {}) as Dictionary
		var child_position: Vector2 = _vec(child_rest.get("position", [0.0, 0.0]))
		if child_position.length() > 0.5:
			return {
				"length": child_position.length(),
				"angle": rad_to_deg(child_position.angle()),
			}
	var fallback_length: float = 18.0 if bone_id.contains("torso") else 12.0
	if bone_id.contains("head"):
		fallback_length = 9.0
	elif bone_id.contains("hand") or bone_id.contains("foot"):
		fallback_length = 7.0
	return {"length": fallback_length, "angle": -90.0 if bone_id.contains("torso") else 0.0}


func _ids_sorted_by_current_z(ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for bone_id: String in ids:
		var bone_data: Dictionary = _bone_by_id(bone_id)
		var rest_data: Dictionary = bone_data.get("rest", {}) as Dictionary
		var z_value: int = int(rest_data.get("z_index", 0))
		var inserted: bool = false
		for index: int in range(result.size()):
			var other_data: Dictionary = _bone_by_id(result[index])
			var other_rest: Dictionary = other_data.get("rest", {}) as Dictionary
			if z_value < int(other_rest.get("z_index", 0)):
				result.insert(index, bone_id)
				inserted = true
				break
		if not inserted:
			result.append(bone_id)
	return result


func _default_bone_color(bone_id: String, palette_index: int = -1) -> String:
	var palette: Array[String] = [
		"#5ccdf8", "#ffb347", "#8ee68e", "#d79cff", "#ff7f91",
		"#6fe3cf", "#f4d35e", "#9fb8ff", "#f59ad3", "#91d7ff",
	]
	var index_value: int = palette_index
	if index_value < 0:
		index_value = absi(bone_id.hash())
	return palette[index_value % palette.size()]


func _rebuild_layers_tree() -> void:
	if layers_tree == null:
		return
	rebuilding_trees = true
	layers_tree.clear()
	var hidden_root: TreeItem = layers_tree.create_item()
	var display_order: Array[String] = _layer_display_order()
	for index: int in range(display_order.size()):
		var bone_id: String = display_order[index]
		var bone_data: Dictionary = _bone_by_id(bone_id)
		if bone_data.is_empty():
			continue
		var item: TreeItem = layers_tree.create_item(hidden_root)
		item.set_text(0, "%02d  %s" % [index + 1, str(bone_data.get("name", bone_id))])
		item.set_metadata(0, bone_id)
		item.set_tooltip_text(0, "Arraste para mudar quem aparece por cima.")
		item.set_custom_color(0, Color.from_string(str(bone_data.get("editor_color", "#5ccdf8")), Color.WHITE))
		if bone_id == selected_bone:
			item.select(0)
	rebuilding_trees = false


func _layer_display_order() -> Array[String]:
	var rig_data: Dictionary = _rig_section()
	var back_to_front: Array = rig_data.get("layer_order", []) as Array
	var result: Array[String] = []
	for index: int in range(back_to_front.size() - 1, -1, -1):
		result.append(str(back_to_front[index]))
	return result


func _on_layer_selected() -> void:
	if rebuilding_trees or layers_tree == null:
		return
	var item: TreeItem = layers_tree.get_selected()
	if item != null:
		_select_bone(str(item.get_metadata(0)))


func _layer_get_drag_data(at_position: Vector2) -> Variant:
	var item: TreeItem = layers_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var bone_id: String = str(item.get_metadata(0))
	if bone_id.is_empty():
		return null
	var preview_label: Label = Label.new()
	preview_label.text = str(_bone_by_id(bone_id).get("name", bone_id))
	preview_label.add_theme_stylebox_override("normal", _style_box(Color(0.1, 0.2, 0.26), Color(0.35, 0.75, 0.92), 1))
	layers_tree.set_drag_preview(preview_label)
	return {"kind": "wyrdframe_layer", "bone_id": bone_id}


func _layer_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("kind", "")) == "wyrdframe_layer"


func _layer_drop_data(at_position: Vector2, data: Variant) -> void:
	if not _layer_can_drop_data(at_position, data):
		return
	var source_id: String = str((data as Dictionary).get("bone_id", ""))
	var display_order: Array[String] = _layer_display_order()
	if not display_order.has(source_id):
		return
	var target_item: TreeItem = layers_tree.get_item_at_position(at_position)
	var target_id: String = ""
	if target_item != null:
		target_id = str(target_item.get_metadata(0))
	_record_history()
	display_order.erase(source_id)
	if target_id.is_empty() or not display_order.has(target_id):
		display_order.append(source_id)
	else:
		var target_index: int = display_order.find(target_id)
		var drop_section: int = layers_tree.get_drop_section_at_position(at_position)
		if drop_section > 0:
			target_index += 1
		display_order.insert(clampi(target_index, 0, display_order.size()), source_id)
	var back_to_front: Array[String] = display_order.duplicate()
	back_to_front.reverse()
	_rig_section()["layer_order"] = back_to_front
	_apply_layer_order_to_z()
	selected_bone = source_id
	_mark_changed("Ordem das camadas atualizada por arraste.", false)
	_rebuild_layers_tree()
	_apply_render()


func _apply_layer_order_to_z() -> void:
	var order_value: Array = _rig_section().get("layer_order", []) as Array
	var z_by_bone: Dictionary = {}
	for index: int in range(order_value.size()):
		z_by_bone[str(order_value[index])] = index * 10
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		if not z_by_bone.has(bone_id):
			continue
		var rest_data: Dictionary = bone_data.get("rest", {}) as Dictionary
		rest_data["z_index"] = int(z_by_bone[bone_id])
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_value: Variant in directions.values():
			var direction_data: Dictionary = direction_value as Dictionary
			var frames_value: Array = direction_data.get("frames", []) as Array
			for frame_value: Variant in frames_value:
				var frame_data: Dictionary = frame_value as Dictionary
				var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
				for bone_id: String in z_by_bone.keys():
					if keys.has(bone_id):
						var key_data: Dictionary = keys[bone_id] as Dictionary
						key_data["z_index"] = int(z_by_bone[bone_id])


func _on_preview_input(event: InputEvent) -> void:
	var zoom_value: float = float(maxi(1, zoom_option.get_selected_id()))
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		var canvas_position: Vector2 = mouse_event.position / zoom_value
		if mouse_event.pressed:
			var candidates: Array[String] = canvas_renderer.hit_test_bones(canvas_position)
			if candidates.is_empty():
				drag_active = false
				return
			var same_pick: bool = canvas_position.distance_to(_last_pick_canvas) <= 3.0 / zoom_value and candidates == _pick_candidates
			if same_pick:
				_pick_cycle_index = (_pick_cycle_index + 1) % candidates.size()
			else:
				_pick_candidates = candidates
				_pick_cycle_index = 0
				_last_pick_canvas = canvas_position
			selected_bone = candidates[_pick_cycle_index]
			_refresh_controls()
			_rebuild_rig_tree()
			_rebuild_layers_tree()
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
