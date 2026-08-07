extends "res://scripts/labs/alabaster/AlabasterBoneStudio.gd"
class_name AlabasterBoneStudioPro

const ProductionRigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd")
const TimelineScript := preload("res://scripts/labs/alabaster/AlabasterBoneTimeline.gd")
const ViewportEditorScript := preload("res://scripts/labs/alabaster/AlabasterBoneViewportEditor.gd")

const BASE_PREVIEW_SCALE := 3.2

var preview_stage: Control
var preview_viewport: SubViewport
var viewport_editor: Control
var timeline: Control
var auto_key_check: CheckBox
var tween_enabled_check: CheckBox
var camera_lock_check: CheckBox
var zoom_slider: HSlider
var transform_mode_option: OptionButton
var maximize_button: Button
var timeline_length_spin: SpinBox
var playback_button: Button

var preview_yaw_degrees := 180.0
var preview_pitch_degrees := -45.0
var preview_zoom := 1.0
var _suppress_auto_key := false
var _manual_playing := false


func _ready() -> void:
	super._ready()
	_configure_studio_window()
	_build_pro_timeline()
	_connect_auto_key_controls()
	_sync_pro_timeline()
	call_deferred("_maximize_studio_window")


func _configure_studio_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	var window := get_window()
	if window != null:
		window.min_size = Vector2i(1180, 720)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		window.size_changed.connect(_on_studio_window_resized)


func _maximize_studio_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	call_deferred("_on_studio_window_resized")


func _build_preview_controls(parent: VBoxContainer) -> void:
	super._build_preview_controls(parent)
	_add_heading(parent, "3D Bone Editing")

	transform_mode_option = OptionButton.new()
	transform_mode_option.add_item("Move (W)")
	transform_mode_option.set_item_metadata(0, "move")
	transform_mode_option.add_item("Rotate (E)")
	transform_mode_option.set_item_metadata(1, "rotate")
	transform_mode_option.select(1)
	transform_mode_option.item_selected.connect(_on_transform_mode_selected)
	_add_row(parent, "Gizmo", transform_mode_option)

	camera_lock_check = CheckBox.new()
	camera_lock_check.button_pressed = true
	camera_lock_check.text = "Locked"
	camera_lock_check.tooltip_text = "Unlock and right-drag the preview to orbit. Horizontal orbit changes facing; vertical orbit changes editor camera pitch."
	camera_lock_check.toggled.connect(_on_camera_lock_toggled)
	_add_row(parent, "Orbit camera", camera_lock_check)

	zoom_slider = HSlider.new()
	zoom_slider.min_value = 0.35
	zoom_slider.max_value = 4.0
	zoom_slider.step = 0.05
	zoom_slider.value = 1.0
	zoom_slider.value_changed.connect(_on_preview_zoom_changed)
	_add_row(parent, "Preview zoom", zoom_slider)

	var help := Label.new()
	help.text = "LEFT drag selected bone = active gizmo · ALT+Move = X/Y depth plane · SHIFT+Rotate = Roll · RIGHT drag = orbit when unlocked · Mouse wheel = zoom · W/E switch Move/Rotate"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(help)

	maximize_button = Button.new()
	maximize_button.text = "Maximize / Restore Window"
	maximize_button.pressed.connect(_toggle_maximize)
	parent.add_child(maximize_button)


func _build_preview_container(parent: VBoxContainer) -> void:
	preview_stage = Control.new()
	preview_stage.name = "BonePreviewStage"
	preview_stage.custom_minimum_size = Vector2(620, 420)
	preview_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_stage.clip_contents = true
	parent.add_child(preview_stage)

	var holder := SubViewportContainer.new()
	holder.name = "BonePreviewViewportContainer"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.stretch = true
	preview_stage.add_child(holder)

	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(620, 420)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.transparent_bg = false
	preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	holder.add_child(preview_viewport)

	preview_world = Node2D.new()
	preview_world.name = "PreviewWorld"
	preview_viewport.add_child(preview_world)

	viewport_editor = ViewportEditorScript.new()
	viewport_editor.name = "DirectBoneEditorOverlay"
	viewport_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_editor.bone_selected.connect(_on_viewport_bone_selected)
	viewport_editor.bone_transform_delta.connect(_on_viewport_bone_transform_delta)
	viewport_editor.orbit_delta.connect(_on_viewport_orbit_delta)
	viewport_editor.zoom_requested.connect(_on_viewport_zoom_requested)
	preview_stage.add_child(viewport_editor)
	preview_stage.resized.connect(_on_preview_stage_resized)
	call_deferred("_on_preview_stage_resized")


func _build_preview() -> void:
	rig = ProductionRigScript.new()
	rig.name = "JunoBoneStudioProductionRig"
	preview_world.add_child(rig)
	rig.scale = Vector2.ONE * BASE_PREVIEW_SCALE
	rig.call_deferred("set_sprite_opacity", opacity_slider.value)
	rig.call_deferred("set_debug_enabled", false)
	rig.call_deferred("set_editor_camera_enabled", true)
	rig.call_deferred("set_editor_camera_pitch_degrees", preview_pitch_degrees)
	rig.call_deferred("set_editor_animation_paused", true)
	rig.call_deferred("set_facing_from_vector", Vector2.DOWN)
	if viewport_editor != null:
		viewport_editor.call_deferred("configure", rig, _preview_center())
		viewport_editor.call_deferred("set_camera_locked", true)
		viewport_editor.call_deferred("set_transform_mode", "rotate")
	call_deferred("_populate_manual_bones")


func _build_pro_timeline() -> void:
	var margin := get_child(0) as MarginContainer
	if margin == null or margin.get_child_count() <= 0:
		return
	var root := margin.get_child(0) as VBoxContainer
	if root == null:
		return

	var panel := PanelContainer.new()
	panel.name = "AfterEffectsBoneTimelinePanel"
	panel.custom_minimum_size = Vector2(0, 285)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)
	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)

	var title := Label.new()
	title.text = "BONE TIMELINE"
	title.custom_minimum_size = Vector2(125, 0)
	title.add_theme_font_size_override("font_size", 15)
	toolbar.add_child(title)

	var current_label := Label.new()
	current_label.name = "CurrentFrameLabel"
	current_label.text = "Frame 0"
	current_label.custom_minimum_size = Vector2(82, 0)
	toolbar.add_child(current_label)

	timeline_length_spin = SpinBox.new()
	timeline_length_spin.min_value = 1
	timeline_length_spin.max_value = 9999
	timeline_length_spin.step = 1
	timeline_length_spin.value = 120
	timeline_length_spin.tooltip_text = "Visible animation duration in frames. The timeline expands automatically past the last key."
	timeline_length_spin.value_changed.connect(func(_value: float) -> void: _sync_pro_timeline())
	toolbar.add_child(_small_label("Length"))
	toolbar.add_child(timeline_length_spin)

	auto_key_check = CheckBox.new()
	auto_key_check.text = "Auto-Key"
	auto_key_check.button_pressed = true
	auto_key_check.tooltip_text = "When enabled, dragging a bone or editing transform values writes a keyframe at the current frame automatically."
	toolbar.add_child(auto_key_check)

	tween_enabled_check = CheckBox.new()
	tween_enabled_check.text = "Tween"
	tween_enabled_check.button_pressed = false
	tween_enabled_check.tooltip_text = "Normal keys are orange. Tween-enabled keys are purple and use the selected spline."
	toolbar.add_child(tween_enabled_check)

	playback_button = Button.new()
	playback_button.text = "▶ Play"
	playback_button.pressed.connect(_toggle_manual_playback)
	toolbar.add_child(playback_button)

	var stop := Button.new()
	stop.text = "■ Stop"
	stop.pressed.connect(_stop_manual_playback)
	toolbar.add_child(stop)

	var prev_key := Button.new()
	prev_key.text = "◀ Key"
	prev_key.pressed.connect(func() -> void: _jump_key(-1))
	toolbar.add_child(prev_key)
	var next_key := Button.new()
	next_key.text = "Key ▶"
	next_key.pressed.connect(func() -> void: _jump_key(1))
	toolbar.add_child(next_key)

	timeline = TimelineScript.new()
	timeline.name = "BoneTimeline"
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.frame_changed.connect(_on_timeline_frame_changed)
	timeline.bone_selected.connect(_on_timeline_bone_selected)
	timeline.key_selected.connect(_on_timeline_key_selected)
	box.add_child(timeline)

	if manual_key_list != null:
		manual_key_list.visible = false
		manual_key_list.custom_minimum_size = Vector2.ZERO


func _connect_auto_key_controls() -> void:
	for control in [manual_yaw, manual_pitch, manual_roll, manual_x, manual_y, manual_z]:
		if control != null:
			control.value_changed.connect(_on_manual_transform_value_changed)
	if manual_frame_spin != null:
		manual_frame_spin.value_changed.connect(_on_manual_frame_changed)
	if manual_bone_option != null:
		manual_bone_option.item_selected.connect(_on_manual_bone_option_selected)


func _manual_add_key() -> void:
	if manual_bone_option == null or manual_bone_option.item_count <= 0 or manual_bone_option.selected < 0:
		return
	var frame := int(manual_frame_spin.value)
	var bone := str(manual_bone_option.get_item_metadata(manual_bone_option.selected))
	if not manual_keys.has(frame):
		manual_keys[frame] = {"spline": "LINEAR", "tween_enabled": false, "nodeXfm": {}}
	var frame_data: Dictionary = manual_keys[frame]
	var tween_enabled := tween_enabled_check != null and tween_enabled_check.button_pressed
	frame_data["tween_enabled"] = tween_enabled
	frame_data["spline"] = _manual_spline_value() if tween_enabled else "LINEAR"
	var xfm: Dictionary = frame_data.get("nodeXfm", {})
	xfm[bone] = {
		"rot": [manual_yaw.value, manual_pitch.value, manual_roll.value],
		"trans": [manual_x.value, manual_y.value, manual_z.value],
		"scale": 1.0,
	}
	frame_data["nodeXfm"] = xfm
	manual_keys[frame] = frame_data
	_refresh_manual_key_list()
	_preview_current_manual_frame()
	_set_status("Auto-key %s @ frame %d" % [bone, frame])


func _refresh_manual_key_list() -> void:
	super._refresh_manual_key_list()
	_sync_pro_timeline()


func _on_manual_transform_value_changed(_value: float) -> void:
	if _suppress_auto_key or auto_key_check == null or not auto_key_check.button_pressed:
		return
	_manual_add_key()


func _on_manual_frame_changed(value: float) -> void:
	if _suppress_auto_key:
		return
	var frame := int(value)
	if timeline != null:
		timeline.set_current_frame(frame, true)
	_load_editor_values_for_bone_frame(_current_manual_bone(), frame)
	_preview_current_manual_frame()
	_update_frame_label(frame)


func _on_manual_bone_option_selected(_index: int) -> void:
	if _suppress_auto_key:
		return
	var bone := _current_manual_bone()
	if viewport_editor != null:
		viewport_editor.set_selected_bone(bone)
	if timeline != null:
		timeline.set_selected_bone(bone)
	_load_editor_values_for_bone_frame(bone, int(manual_frame_spin.value))


func _on_viewport_bone_selected(bone_name: String) -> void:
	_suppress_auto_key = true
	_select_option_metadata(manual_bone_option, bone_name)
	_suppress_auto_key = false
	if timeline != null:
		timeline.set_selected_bone(bone_name)
	_load_editor_values_for_bone_frame(bone_name, int(manual_frame_spin.value))


func _on_viewport_bone_transform_delta(bone_name: String, mode: String, delta_value: Vector3) -> void:
	if bone_name != _current_manual_bone():
		_on_viewport_bone_selected(bone_name)
	_suppress_auto_key = true
	if mode == "move":
		manual_x.value += delta_value.x
		manual_y.value += delta_value.y
		manual_z.value += delta_value.z
	else:
		manual_yaw.value += delta_value.x
		manual_pitch.value += delta_value.y
		manual_roll.value += delta_value.z
	_suppress_auto_key = false
	if auto_key_check != null and auto_key_check.button_pressed:
		_manual_add_key()
	else:
		_preview_current_manual_frame()


func _on_timeline_frame_changed(frame: int) -> void:
	_suppress_auto_key = true
	manual_frame_spin.value = frame
	_suppress_auto_key = false
	_load_editor_values_for_bone_frame(_current_manual_bone(), frame)
	_preview_current_manual_frame()
	_update_frame_label(frame)


func _on_timeline_bone_selected(bone_name: String) -> void:
	_on_viewport_bone_selected(bone_name)


func _on_timeline_key_selected(frame: int, bone_name: String) -> void:
	_on_viewport_bone_selected(bone_name)
	_on_timeline_frame_changed(frame)


func _load_editor_values_for_bone_frame(bone_name: String, frame: int) -> void:
	if bone_name.is_empty():
		return
	var data := _find_manual_bone_value_at_or_before(bone_name, frame)
	var rot: Array = data.get("rot", [0.0, 0.0, 0.0])
	var trans: Array = data.get("trans", [0.0, 0.0, 0.0])
	_suppress_auto_key = true
	manual_yaw.value = float(rot[0])
	manual_pitch.value = float(rot[1])
	manual_roll.value = float(rot[2])
	manual_x.value = float(trans[0])
	manual_y.value = float(trans[1])
	manual_z.value = float(trans[2])
	if tween_enabled_check != null:
		var frame_data: Dictionary = manual_keys.get(frame, {})
		tween_enabled_check.button_pressed = bool(frame_data.get("tween_enabled", str(frame_data.get("spline", "LINEAR")) != "LINEAR"))
	_suppress_auto_key = false


func _find_manual_bone_value_at_or_before(bone_name: String, frame: int) -> Dictionary:
	var frames: Array = manual_keys.keys()
	frames.sort()
	frames.reverse()
	for frame_value in frames:
		var key_frame := int(frame_value)
		if key_frame > frame:
			continue
		var frame_data_value: Variant = manual_keys[key_frame]
		if not frame_data_value is Dictionary:
			continue
		var xfm_value: Variant = (frame_data_value as Dictionary).get("nodeXfm", {})
		if xfm_value is Dictionary and (xfm_value as Dictionary).has(bone_name):
			var bone_value: Variant = (xfm_value as Dictionary)[bone_name]
			if bone_value is Dictionary:
				return (bone_value as Dictionary).duplicate(true)
	return {"rot": [0.0, 0.0, 0.0], "trans": [0.0, 0.0, 0.0], "scale": 1.0}


func _preview_current_manual_frame() -> void:
	if rig == null:
		return
	var data := _build_manual_animation()
	if data.is_empty():
		return
	rig.install_runtime_animation("__manual_editor", data)
	rig.set_animation("__manual_editor")
	if rig.has_method("set_editor_animation_paused"):
		rig.set_editor_animation_paused(true)
	if rig.has_method("seek_animation_frame"):
		rig.seek_animation_frame(float(manual_frame_spin.value))
	_manual_playing = false
	if playback_button != null:
		playback_button.text = "▶ Play"


func _preview_manual() -> void:
	var data := _build_manual_animation()
	if data.is_empty():
		return
	rig.install_runtime_animation("__manual_preview", data)
	rig.set_animation("__manual_preview")
	rig.set_editor_animation_paused(false)
	_manual_playing = true
	if playback_button != null:
		playback_button.text = "Ⅱ Pause"
	_set_status("Manual animation playing. Timeline editing remains available after Pause/Stop.")


func _toggle_manual_playback() -> void:
	if rig == null:
		return
	if _manual_playing:
		rig.set_editor_animation_paused(true)
		_manual_playing = false
		playback_button.text = "▶ Play"
		return
	_preview_manual()


func _stop_manual_playback() -> void:
	if rig == null:
		return
	_manual_playing = false
	rig.set_editor_animation_paused(true)
	playback_button.text = "▶ Play"
	_preview_current_manual_frame()


func _process(delta: float) -> void:
	super._process(delta)
	if _manual_playing and rig != null and rig.has_method("get_current_source_frame"):
		var frame := int(round(float(rig.get_current_source_frame())))
		_suppress_auto_key = true
		manual_frame_spin.value = frame
		_suppress_auto_key = false
		if timeline != null:
			timeline.set_current_frame(frame, false)
		_update_frame_label(frame)


func _sync_pro_timeline() -> void:
	if timeline == null or rig == null or not rig.has_method("get_bone_names"):
		return
	var max_key := 0
	for frame_value in manual_keys.keys():
		max_key = maxi(max_key, int(frame_value))
	var requested_length := int(timeline_length_spin.value) if timeline_length_spin != null else 120
	var length := maxi(requested_length, max_key + 20, int(manual_frame_spin.value) + 1)
	var bones_value: Variant = rig.get_bone_names()
	var bones: Array = bones_value if bones_value is Array else []
	timeline.set_timeline_data(bones, manual_keys, int(manual_frame_spin.value), length)
	if not _current_manual_bone().is_empty():
		timeline.set_selected_bone(_current_manual_bone())


func _jump_key(direction: int) -> void:
	if manual_keys.is_empty():
		return
	var frames: Array = manual_keys.keys()
	frames.sort()
	var current := int(manual_frame_spin.value)
	if direction < 0:
		for index in range(frames.size() - 1, -1, -1):
			if int(frames[index]) < current:
				_on_timeline_frame_changed(int(frames[index]))
				return
		_on_timeline_frame_changed(int(frames[0]))
	else:
		for frame_value in frames:
			if int(frame_value) > current:
				_on_timeline_frame_changed(int(frame_value))
				return
		_on_timeline_frame_changed(int(frames.back()))


func _on_transform_mode_selected(index: int) -> void:
	if transform_mode_option == null or viewport_editor == null:
		return
	viewport_editor.set_transform_mode(str(transform_mode_option.get_item_metadata(index)))


func _on_camera_lock_toggled(locked: bool) -> void:
	if camera_lock_check != null:
		camera_lock_check.text = "Locked" if locked else "Unlocked · RMB orbit"
	if viewport_editor != null:
		viewport_editor.set_camera_locked(locked)


func _on_viewport_orbit_delta(yaw_delta: float, pitch_delta: float) -> void:
	if camera_lock_check != null and camera_lock_check.button_pressed:
		return
	preview_yaw_degrees = fposmod(preview_yaw_degrees + yaw_delta, 360.0)
	preview_pitch_degrees = clampf(preview_pitch_degrees + pitch_delta, -80.0, -10.0)
	var yaw_rad := deg_to_rad(preview_yaw_degrees)
	var direction := Vector2(sin(yaw_rad), -cos(yaw_rad))
	rig.set_facing_from_vector(direction)
	if rig.has_method("set_editor_camera_pitch_degrees"):
		rig.set_editor_camera_pitch_degrees(preview_pitch_degrees)


func _on_viewport_zoom_requested(factor: float) -> void:
	if zoom_slider == null:
		return
	zoom_slider.value = clampf(zoom_slider.value * factor, zoom_slider.min_value, zoom_slider.max_value)


func _on_preview_zoom_changed(value: float) -> void:
	preview_zoom = value
	if rig != null:
		rig.scale = Vector2.ONE * BASE_PREVIEW_SCALE * preview_zoom
	if viewport_editor != null:
		viewport_editor.queue_redraw()


func _on_facing_selected(index: int) -> void:
	super._on_facing_selected(index)
	if facing_option == null or index < 0:
		return
	var direction_value: Variant = facing_option.get_item_metadata(index)
	if direction_value is Vector2:
		var direction := direction_value as Vector2
		preview_yaw_degrees = fposmod(rad_to_deg(atan2(direction.x, -direction.y)), 360.0)


func _on_preview_stage_resized() -> void:
	if preview_stage == null or preview_viewport == null or preview_world == null:
		return
	var resolved_size := preview_stage.size
	if resolved_size.x < 2.0 or resolved_size.y < 2.0:
		return
	preview_viewport.size = Vector2i(maxi(roundi(resolved_size.x), 2), maxi(roundi(resolved_size.y), 2))
	preview_world.position = resolved_size * 0.5 + Vector2(0.0, 18.0)
	if viewport_editor != null:
		viewport_editor.set_preview_origin(preview_world.position)


func _on_studio_window_resized() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	call_deferred("_on_preview_stage_resized")


func _toggle_maximize() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	call_deferred("_on_studio_window_resized")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_W and viewport_editor != null:
		transform_mode_option.select(0)
		viewport_editor.set_transform_mode("move")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E and viewport_editor != null:
		transform_mode_option.select(1)
		viewport_editor.set_transform_mode("rotate")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		_toggle_manual_playback()
		get_viewport().set_input_as_handled()


func _current_manual_bone() -> String:
	if manual_bone_option == null or manual_bone_option.item_count <= 0 or manual_bone_option.selected < 0:
		return ""
	return str(manual_bone_option.get_item_metadata(manual_bone_option.selected))


func _update_frame_label(frame: int) -> void:
	if timeline == null or timeline.get_parent() == null:
		return
	var toolbar := timeline.get_parent().get_child(0) as HBoxContainer
	if toolbar == null:
		return
	var label := toolbar.get_node_or_null("CurrentFrameLabel") as Label
	if label != null:
		label.text = "Frame %d" % frame


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
