class_name WyrdframePixelStudio
extends "res://tools/sprite_pose_lab/scripts/WyrdframeAdvancedStudio.gd"

const PixelCanvasScript: Script = preload("res://tools/sprite_pose_lab/scripts/WyrdframePixelCanvas.gd")

var preserve_thickness_check: CheckBox
var preserve_outline_check: CheckBox
var show_sprite_pins_check: CheckBox
var pin_enabled_check: CheckBox
var pin_sync_length_check: CheckBox
var pin_start_x_spin: SpinBox
var pin_start_y_spin: SpinBox
var pin_end_x_spin: SpinBox
var pin_end_y_spin: SpinBox
var pin_status_label: Label
var pin_pick_start_button: Button
var pin_pick_end_button: Button
var pin_auto_button: Button
var pin_swap_button: Button

var _pin_pick_mode: String = ""


func _build_left_panel() -> Control:
	var tabs: TabContainer = super._build_left_panel() as TabContainer
	var pins_tab: VBoxContainer = VBoxContainer.new()
	pins_tab.name = "Pins"
	pins_tab.add_theme_constant_override("separation", 7)
	pins_tab.add_child(_section_label("PINS DO BONE NO SPRITE"))

	var explanation: Label = Label.new()
	explanation.text = "O pin azul é o início do bone; o laranja é a ponta. Marque, por exemplo, joelho e tornozelo diretamente no PNG da canela."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.68, 0.76, 0.83)
	pins_tab.add_child(explanation)

	pin_enabled_check = _check("Usar dois pins neste sprite", true, Callable(self, "_on_pin_enabled_changed"))
	pin_enabled_check.tooltip_text = "Quando ligado, o sprite é preso ao bone pelos dois pontos escolhidos, em vez de usar apenas um pivô central."
	pins_tab.add_child(pin_enabled_check)

	pin_sync_length_check = _check("Comprimento do bone segue os pins", true, Callable(self, "_on_pin_sync_length_changed"))
	pin_sync_length_check.tooltip_text = "Mantém as duas pontas exatamente coincidentes sem esticar o PNG. A distância entre os pins vira o comprimento real do bone."
	pins_tab.add_child(pin_sync_length_check)

	show_sprite_pins_check = _check("Mostrar pins no canvas", true, Callable(self, "_on_view_setting_changed"))
	pins_tab.add_child(show_sprite_pins_check)

	var pin_grid: GridContainer = GridContainer.new()
	pin_grid.columns = 2
	pin_start_x_spin = _spin_row(pin_grid, "Início X", -4096.0, 4096.0, 0.5)
	pin_start_y_spin = _spin_row(pin_grid, "Início Y", -4096.0, 4096.0, 0.5)
	pin_end_x_spin = _spin_row(pin_grid, "Ponta X", -4096.0, 4096.0, 0.5)
	pin_end_y_spin = _spin_row(pin_grid, "Ponta Y", -4096.0, 4096.0, 0.5)
	for spin_value: Variant in [pin_start_x_spin, pin_start_y_spin, pin_end_x_spin, pin_end_y_spin]:
		var pin_spin: SpinBox = spin_value as SpinBox
		pin_spin.suffix = " px"
		pin_spin.value_changed.connect(Callable(self, "_on_pin_values_changed"))
	pins_tab.add_child(pin_grid)

	var pick_row: HBoxContainer = HBoxContainer.new()
	pin_pick_start_button = _button("Marcar início", Callable(self, "_begin_pick_start_pin"))
	pin_pick_end_button = _button("Marcar ponta", Callable(self, "_begin_pick_end_pin"))
	pick_row.add_child(pin_pick_start_button)
	pick_row.add_child(pin_pick_end_button)
	pins_tab.add_child(pick_row)

	var tools_row: HBoxContainer = HBoxContainer.new()
	pin_auto_button = _button("Detectar eixo", Callable(self, "_auto_detect_selected_pins"))
	pin_swap_button = _button("Inverter", Callable(self, "_swap_selected_pins"))
	tools_row.add_child(pin_auto_button)
	tools_row.add_child(pin_swap_button)
	pins_tab.add_child(tools_row)

	var auto_note: Label = Label.new()
	auto_note.text = "Detectar eixo usa a silhueta alfa do PNG e encontra o eixo principal. Depois você pode corrigir os dois pontos com clique ou números."
	auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_note.modulate = Color(0.58, 0.69, 0.77)
	pins_tab.add_child(auto_note)

	pin_status_label = Label.new()
	pin_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pin_status_label.modulate = Color(0.55, 0.82, 0.94)
	pins_tab.add_child(pin_status_label)

	tabs.add_child(pins_tab)
	return tabs


func _build_preview_panel() -> Control:
	var result: Control = super._build_preview_panel()
	var column: VBoxContainer = result as VBoxContainer
	if column.get_child_count() > 0:
		var toolbar_scroll: ScrollContainer = column.get_child(0) as ScrollContainer
		if toolbar_scroll != null and toolbar_scroll.get_child_count() > 0:
			var toolbar: HBoxContainer = toolbar_scroll.get_child(0) as HBoxContainer
			preserve_thickness_check = _check("Espessura estável", false, Callable(self, "_on_view_setting_changed"))
			preserve_thickness_check.tooltip_text = "Rotação raster com cobertura subpixel. Recoloca somente pixels sustentados pela silhueta original para evitar braços e pernas afinando em ângulos diagonais."
			preserve_outline_check = _check("Outline estável", false, Callable(self, "_on_view_setting_changed"))
			preserve_outline_check.tooltip_text = "Detecta o contorno escuro real do PNG e reconstrói falhas após a rotação. Não aplica stroke preto genérico."
			toolbar.add_child(preserve_thickness_check)
			toolbar.add_child(preserve_outline_check)
			var pixel_index: int = toolbar.get_children().find(pixel_snap_check)
			if pixel_index >= 0:
				toolbar.move_child(preserve_thickness_check, pixel_index + 1)
				toolbar.move_child(preserve_outline_check, pixel_index + 2)
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
	canvas_renderer = PixelCanvasScript.new()
	render_viewport.add_child(canvas_renderer)
	preview.texture = render_viewport.get_texture()
	_apply_render()


func _view_settings() -> Dictionary:
	var settings: Dictionary = super._view_settings()
	settings["preserve_pixel_thickness"] = preserve_thickness_check != null and preserve_thickness_check.button_pressed
	settings["preserve_sprite_outline"] = preserve_outline_check != null and preserve_outline_check.button_pressed
	settings["show_sprite_pins"] = show_sprite_pins_check == null or show_sprite_pins_check.button_pressed
	return settings


func _ensure_advanced_editor_data() -> void:
	super._ensure_advanced_editor_data()
	if document.is_empty():
		return
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_value: Variant in directions.values():
			var direction_data: Dictionary = direction_value as Dictionary
			if not direction_data.has("sprite_pins") or not (direction_data.get("sprite_pins") is Dictionary):
				direction_data["sprite_pins"] = {}


func _refresh_inspector() -> void:
	super._refresh_inspector()
	_refresh_pin_controls()


func _refresh_pin_controls() -> void:
	if pin_enabled_check == null:
		return
	var has_texture: bool = not _texture_path(selected_bone).is_empty()
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	var usable: bool = has_texture and not bone_data.is_empty() and bool(bone_data.get("has_sprite", true))
	var pins: Dictionary = {}
	if usable:
		pins = _ensure_pin_data(selected_bone, false)
	var enabled: bool = usable and bool(pins.get("enabled", false))
	var start_pin: Vector2 = _vec(pins.get("start", [0.0, 0.0]))
	var end_pin: Vector2 = _vec(pins.get("end", [0.0, 0.0]))

	pin_enabled_check.disabled = not usable
	pin_enabled_check.button_pressed = enabled
	pin_sync_length_check.disabled = not usable or not enabled
	pin_sync_length_check.button_pressed = bool(pins.get("sync_length", true))
	for spin_value: Variant in [pin_start_x_spin, pin_start_y_spin, pin_end_x_spin, pin_end_y_spin]:
		var pin_spin: SpinBox = spin_value as SpinBox
		pin_spin.editable = usable and enabled
	pin_start_x_spin.value = start_pin.x
	pin_start_y_spin.value = start_pin.y
	pin_end_x_spin.value = end_pin.x
	pin_end_y_spin.value = end_pin.y
	pin_pick_start_button.disabled = not usable or not enabled
	pin_pick_end_button.disabled = not usable or not enabled
	pin_auto_button.disabled = not usable
	pin_swap_button.disabled = not usable or not enabled

	if not usable:
		pin_status_label.text = "Carregue um PNG no bone para editar os pins."
	elif _pin_pick_mode == "start":
		pin_status_label.text = "Clique no canvas onde o início azul deve prender no sprite."
	elif _pin_pick_mode == "end":
		pin_status_label.text = "Clique no canvas onde a ponta laranja deve prender no sprite."
	else:
		var distance: float = start_pin.distance_to(end_pin)
		pin_status_label.text = "Distância entre pins: %.2f px" % distance


func _pins_map(action_id: String = "", direction_id: String = "") -> Dictionary:
	var direction_data: Dictionary = _direction_data(action_id, direction_id)
	var pins_value: Variant = direction_data.get("sprite_pins", {})
	if not (pins_value is Dictionary):
		direction_data["sprite_pins"] = {}
	return direction_data.get("sprite_pins", {}) as Dictionary


func _ensure_pin_data(bone_id: String, sync_new_length: bool) -> Dictionary:
	var pins_map: Dictionary = _pins_map()
	if pins_map.has(bone_id) and pins_map[bone_id] is Dictionary:
		return pins_map[bone_id] as Dictionary
	var image: Image = _load_image_for_sprite(_texture_path(bone_id))
	if image == null or image.is_empty():
		return {}
	var data: Dictionary = _detect_pin_axis(image, bone_id, sync_new_length)
	pins_map[bone_id] = data
	if sync_new_length:
		_sync_bone_length_to_pins(bone_id, data)
	return data


func _load_image_for_sprite(path: String) -> Image:
	if path.is_empty():
		return null
	var image: Image = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				image = texture.get_image()
	else:
		var external_image: Image = Image.new()
		if external_image.load(path) == OK:
			image = external_image
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _detect_pin_axis(image: Image, bone_id: String, sync_length: bool) -> Dictionary:
	var weight_sum: float = 0.0
	var mean: Vector2 = Vector2.ZERO
	for y_value: int in range(image.get_height()):
		for x_value: int in range(image.get_width()):
			var alpha: float = image.get_pixel(x_value, y_value).a
			if alpha <= 0.05:
				continue
			var point: Vector2 = Vector2(float(x_value) + 0.5, float(y_value) + 0.5)
			mean += point * alpha
			weight_sum += alpha
	if weight_sum <= 0.001:
		var center: Vector2 = Vector2(image.get_size()) * 0.5
		return {
			"enabled": true,
			"start": [center.x, center.y],
			"end": [center.x + 1.0, center.y],
			"sync_length": sync_length,
		}
	mean /= weight_sum

	var covariance_xx: float = 0.0
	var covariance_xy: float = 0.0
	var covariance_yy: float = 0.0
	for y_value: int in range(image.get_height()):
		for x_value: int in range(image.get_width()):
			var alpha: float = image.get_pixel(x_value, y_value).a
			if alpha <= 0.05:
				continue
			var delta: Vector2 = Vector2(float(x_value) + 0.5, float(y_value) + 0.5) - mean
			covariance_xx += delta.x * delta.x * alpha
			covariance_xy += delta.x * delta.y * alpha
			covariance_yy += delta.y * delta.y * alpha
	covariance_xx /= weight_sum
	covariance_xy /= weight_sum
	covariance_yy /= weight_sum

	var bone_data: Dictionary = _bone_by_id(bone_id)
	var target_axis: Vector2 = Vector2(
		maxf(1.0, float(bone_data.get("length", 12.0))),
		0.0
	).rotated(deg_to_rad(float(bone_data.get("bone_angle_degrees", 0.0))))
	var eigen_angle: float = 0.5 * atan2(2.0 * covariance_xy, covariance_xx - covariance_yy)
	var axis: Vector2 = Vector2(cos(eigen_angle), sin(eigen_angle)).normalized()
	var anisotropy_numerator: float = sqrt(pow(covariance_xx - covariance_yy, 2.0) + 4.0 * covariance_xy * covariance_xy)
	var anisotropy: float = anisotropy_numerator / maxf(0.0001, covariance_xx + covariance_yy)
	if anisotropy < 0.18:
		axis = target_axis.normalized()
	if axis.dot(target_axis) < 0.0:
		axis = -axis

	var min_projection: float = INF
	var max_projection: float = -INF
	for y_value: int in range(image.get_height()):
		for x_value: int in range(image.get_width()):
			if image.get_pixel(x_value, y_value).a <= 0.05:
				continue
			var projection: float = Vector2(float(x_value) + 0.5, float(y_value) + 0.5).dot(axis)
			min_projection = minf(min_projection, projection)
			max_projection = maxf(max_projection, projection)
	var span: float = maxf(1.0, max_projection - min_projection)
	var inset: float = minf(2.0, span * 0.08)
	var mean_projection: float = mean.dot(axis)
	var start_pin: Vector2 = mean + axis * (min_projection + inset - mean_projection)
	var end_pin: Vector2 = mean + axis * (max_projection - inset - mean_projection)
	start_pin.x = clampf(start_pin.x, 0.0, float(image.get_width()))
	start_pin.y = clampf(start_pin.y, 0.0, float(image.get_height()))
	end_pin.x = clampf(end_pin.x, 0.0, float(image.get_width()))
	end_pin.y = clampf(end_pin.y, 0.0, float(image.get_height()))
	start_pin.x = snappedf(start_pin.x, 0.5)
	start_pin.y = snappedf(start_pin.y, 0.5)
	end_pin.x = snappedf(end_pin.x, 0.5)
	end_pin.y = snappedf(end_pin.y, 0.5)
	return {
		"enabled": true,
		"start": [start_pin.x, start_pin.y],
		"end": [end_pin.x, end_pin.y],
		"sync_length": sync_length,
	}


func _sync_bone_length_to_pins(bone_id: String, pin_data: Dictionary) -> void:
	if not bool(pin_data.get("sync_length", true)):
		return
	var start_pin: Vector2 = _vec(pin_data.get("start", [0.0, 0.0]))
	var end_pin: Vector2 = _vec(pin_data.get("end", [0.0, 0.0]))
	var distance: float = start_pin.distance_to(end_pin)
	if distance > 0.25:
		_bone_by_id(bone_id)["length"] = distance


func _on_pin_enabled_changed(value: bool) -> void:
	if updating_ui:
		return
	var pins: Dictionary = _ensure_pin_data(selected_bone, true)
	if pins.is_empty():
		return
	_record_history()
	pins["enabled"] = value
	_clear_smart_rotation_cache()
	_mark_changed("Pins do sprite ativados." if value else "Sprite voltou ao pivô tradicional.", false)


func _on_pin_sync_length_changed(value: bool) -> void:
	if updating_ui:
		return
	var pins: Dictionary = _ensure_pin_data(selected_bone, false)
	if pins.is_empty():
		return
	_record_history()
	pins["sync_length"] = value
	if value:
		_sync_bone_length_to_pins(selected_bone, pins)
	_clear_smart_rotation_cache()
	_mark_changed("Sincronização entre pins e comprimento atualizada.", false)


func _on_pin_values_changed(_value: float) -> void:
	if updating_ui:
		return
	var pins: Dictionary = _ensure_pin_data(selected_bone, false)
	if pins.is_empty():
		return
	_record_history()
	pins["start"] = [pin_start_x_spin.value, pin_start_y_spin.value]
	pins["end"] = [pin_end_x_spin.value, pin_end_y_spin.value]
	_sync_bone_length_to_pins(selected_bone, pins)
	_clear_smart_rotation_cache()
	_mark_changed("Pins do sprite atualizados.", false)


func _begin_pick_start_pin() -> void:
	_pin_pick_mode = "start"
	_refresh_pin_controls()


func _begin_pick_end_pin() -> void:
	_pin_pick_mode = "end"
	_refresh_pin_controls()


func _auto_detect_selected_pins() -> void:
	var image: Image = _load_image_for_sprite(_texture_path(selected_bone))
	if image == null:
		_set_status("Não foi possível analisar o PNG deste bone.", true)
		return
	_record_history()
	var pins: Dictionary = _detect_pin_axis(image, selected_bone, true)
	_pins_map()[selected_bone] = pins
	_sync_bone_length_to_pins(selected_bone, pins)
	_pin_pick_mode = ""
	_clear_smart_rotation_cache()
	_mark_changed("Eixo principal do sprite detectado e convertido em dois pins.", false)


func _swap_selected_pins() -> void:
	var pins: Dictionary = _ensure_pin_data(selected_bone, false)
	if pins.is_empty():
		return
	_record_history()
	var start_value: Variant = pins.get("start", [0.0, 0.0])
	pins["start"] = pins.get("end", [1.0, 0.0])
	pins["end"] = start_value
	_sync_bone_length_to_pins(selected_bone, pins)
	_clear_smart_rotation_cache()
	_mark_changed("Início e ponta dos pins invertidos.", false)


func _on_preview_input(event: InputEvent) -> void:
	if not _pin_pick_mode.is_empty() and event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var zoom_value: float = float(maxi(1, zoom_option.get_selected_id()))
			var canvas_position: Vector2 = mouse_event.position / zoom_value
			var sprite_position: Vector2 = canvas_renderer.canvas_to_sprite_pixel(
				selected_bone,
				current_frame,
				canvas_position
			)
			if is_inf(sprite_position.x) or is_inf(sprite_position.y):
				_pin_pick_mode = ""
				_set_status("Não foi possível converter o clique para o espaço do sprite.", true)
				return
			var texture_size: Vector2 = canvas_renderer.sprite_texture_size(selected_bone)
			sprite_position.x = clampf(sprite_position.x, 0.0, texture_size.x)
			sprite_position.y = clampf(sprite_position.y, 0.0, texture_size.y)
			if pixel_snap_check.button_pressed:
				sprite_position = sprite_position.round()
			var pins: Dictionary = _ensure_pin_data(selected_bone, false)
			if pins.is_empty():
				_pin_pick_mode = ""
				return
			_record_history()
			pins[_pin_pick_mode] = [sprite_position.x, sprite_position.y]
			_sync_bone_length_to_pins(selected_bone, pins)
			var picked_name: String = "início" if _pin_pick_mode == "start" else "ponta"
			_pin_pick_mode = ""
			_clear_smart_rotation_cache()
			_mark_changed("Pin de %s marcado no canvas." % picked_name, false)
			get_viewport().set_input_as_handled()
			return
	super._on_preview_input(event)


func _load_texture_path(path: String) -> void:
	var test_image: Image = Image.new()
	if test_image.load(path) != OK:
		_set_status("Não foi possível carregar o PNG.", true)
		return
	var project_root: String = ProjectSettings.globalize_path("res://")
	var stored_path: String = ProjectSettings.localize_path(path) if path.begins_with(project_root) else path
	_record_history()
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	textures[selected_bone] = stored_path
	var pins: Dictionary = _detect_pin_axis(test_image, selected_bone, true)
	_pins_map()[selected_bone] = pins
	_sync_bone_length_to_pins(selected_bone, pins)
	_pin_pick_mode = ""
	canvas_renderer.clear_texture_cache()
	_mark_changed(
		"PNG associado a %s / %s. Dois pins foram detectados automaticamente." % [
			_action_data().get("name", current_action),
			DIRECTION_LABELS[current_direction],
		],
		false
	)


func _clear_texture() -> void:
	_record_history()
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	textures[selected_bone] = ""
	_pins_map().erase(selected_bone)
	_pin_pick_mode = ""
	canvas_renderer.clear_texture_cache()
	_mark_changed("Sprite e pins removidos desta ação e direção.", false)


func _remove_bone() -> void:
	var removed_bone: String = selected_bone
	super._remove_bone()
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_value: Variant in directions.values():
			var direction_data: Dictionary = direction_value as Dictionary
			var pins_map: Dictionary = direction_data.get("sprite_pins", {}) as Dictionary
			pins_map.erase(removed_bone)
	_clear_smart_rotation_cache()


func _select_bone(bone_id: String) -> void:
	_pin_pick_mode = ""
	super._select_bone(bone_id)


func _clear_smart_rotation_cache() -> void:
	if canvas_renderer != null and canvas_renderer.has_method("clear_pixel_rotation_cache"):
		canvas_renderer.clear_pixel_rotation_cache()


func _run_smoke_test() -> void:
	await get_tree().process_frame
	var test_image: Image = Image.create_empty(9, 17, false, Image.FORMAT_RGBA8)
	test_image.fill(Color.TRANSPARENT)
	for y_value: int in range(1, 16):
		for x_value: int in range(2, 7):
			var border: bool = x_value == 2 or x_value == 6 or y_value == 1 or y_value == 15
			var pixel_color: Color = Color(0.06, 0.07, 0.08, 1.0) if border else Color(0.34, 0.62, 0.42, 1.0)
			test_image.set_pixel(x_value, y_value, pixel_color)

	var smoke_bone: String = "left_arm" if not _bone_by_id("left_arm").is_empty() else selected_bone
	var detected: Dictionary = _detect_pin_axis(test_image, smoke_bone, false)
	var detected_start: Vector2 = _vec(detected.get("start", [0.0, 0.0]))
	var detected_end: Vector2 = _vec(detected.get("end", [0.0, 0.0]))
	if detected_start.distance_to(detected_end) < 8.0:
		push_error("WYRD_FRAME_PIXEL_GUARDS_FAIL: pin axis was not detected")
		get_tree().quit(91)
		return

	var test_texture: Texture2D = ImageTexture.create_from_image(test_image)
	var rotated: Dictionary = canvas_renderer._smart_rotated_texture(
		test_texture,
		"wyrdframe_pixel_guard_smoke",
		deg_to_rad(33.0),
		true,
		true
	)
	var rotated_texture: Texture2D = rotated.get("texture") as Texture2D
	if rotated_texture == null:
		push_error("WYRD_FRAME_PIXEL_GUARDS_FAIL: smart rotation returned no texture")
		get_tree().quit(92)
		return
	var rotated_image: Image = rotated_texture.get_image()
	var opaque_count: int = 0
	var dark_count: int = 0
	for y_value: int in range(rotated_image.get_height()):
		for x_value: int in range(rotated_image.get_width()):
			var color_value: Color = rotated_image.get_pixel(x_value, y_value)
			if color_value.a <= 0.05:
				continue
			opaque_count += 1
			if color_value.get_luminance() <= 0.20:
				dark_count += 1
	if opaque_count < 55 or dark_count < 12:
		push_error("WYRD_FRAME_PIXEL_GUARDS_FAIL: rotated silhouette or outline was lost")
		get_tree().quit(93)
		return

	preserve_thickness_check.button_pressed = true
	preserve_outline_check.button_pressed = true
	_on_view_setting_changed()
	print("WYRD_FRAME_PIXEL_GUARDS_OK")
	await super._run_smoke_test()
