extends Control
class_name AlabasterBoneStudio

const RigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeImportable.gd")
const Importer := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationImporter.gd")
const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const ALABASTER_TICK_RATE := 60.0

const MASTER_DIRECTIONS := {
	"North": Vector2.UP,
	"North-East": Vector2(1, -1).normalized(),
	"East": Vector2.RIGHT,
	"South-East": Vector2(1, 1).normalized(),
	"South": Vector2.DOWN,
}

var rig: Node2D
var preview_world: Node2D
var file_dialog: FileDialog
var status_label: Label
var source_path_label: Label
var source_clip_option: OptionButton
var import_name_edit: LineEdit
var mapping_container: VBoxContainer
var mapping_controls: Dictionary = {}
var source_path := ""
var source_bones: Array[String] = []

var import_fps: SpinBox
var import_loop: CheckBox
var import_reference_pose: CheckBox
var import_yaw: SpinBox
var import_pitch: SpinBox
var import_roll: SpinBox
var import_root_motion: SpinBox

var opacity_slider: HSlider
var facing_option: OptionButton
var bone_visibility_check: CheckBox

var manual_name_edit: LineEdit
var manual_bone_option: OptionButton
var manual_frame_spin: SpinBox
var manual_fps_spin: SpinBox
var manual_loop_check: CheckBox
var manual_yaw: SpinBox
var manual_pitch: SpinBox
var manual_roll: SpinBox
var manual_x: SpinBox
var manual_y: SpinBox
var manual_z: SpinBox
var manual_spline: OptionButton
var manual_key_list: ItemList
var manual_keys: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_preview()
	_set_status("Bone Studio ready. Choose a Godot-imported FBX/GLB/GLTF/TSCN scene to begin.")


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = "ALABASTER BONE STUDIO · RETARGET + MANUAL ANIMATOR"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 590
	root.add_child(split)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 600)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(tabs)
	_build_import_tab(tabs)
	_build_manual_tab(tabs)

	var preview_panel := VBoxContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_panel)
	_build_preview_controls(preview_panel)
	_build_preview_container(preview_panel)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray([
		"*.glb, *.gltf ; glTF Scenes",
		"*.fbx ; FBX Scenes",
		"*.tscn ; Godot Scenes",
	])
	file_dialog.file_selected.connect(_on_source_selected)
	add_child(file_dialog)


func _build_import_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Import_Retarget"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "1 · Source animation")
	var browse := Button.new()
	browse.text = "Choose imported FBX / GLB / GLTF / TSCN"
	browse.pressed.connect(func() -> void: file_dialog.popup_centered_ratio(0.75))
	box.add_child(browse)
	source_path_label = Label.new()
	source_path_label.text = "No source selected"
	source_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(source_path_label)
	source_clip_option = OptionButton.new()
	_add_row(box, "Animation clip", source_clip_option)
	import_name_edit = LineEdit.new()
	import_name_edit.placeholder_text = "e.g. OW_run_custom"
	_add_row(box, "Save as", import_name_edit)

	_add_heading(box, "2 · Top-down retarget")
	import_fps = _make_spin(60, 1, 120, 1)
	_add_row(box, "Sample FPS", import_fps)
	import_loop = CheckBox.new()
	import_loop.button_pressed = true
	_add_row(box, "Loop", import_loop)
	import_reference_pose = CheckBox.new()
	import_reference_pose.button_pressed = true
	import_reference_pose.tooltip_text = "Recommended: removes the source character rest pose and keeps only animation delta before applying it to Juno."
	_add_row(box, "Remove source reference pose", import_reference_pose)
	import_yaw = _make_spin(0, -180, 180, 1)
	_add_row(box, "Yaw correction", import_yaw)
	import_pitch = _make_spin(0, -180, 180, 1)
	_add_row(box, "Pitch correction", import_pitch)
	import_roll = _make_spin(0, -180, 180, 1)
	_add_row(box, "Roll correction", import_roll)
	import_root_motion = _make_spin(0, 0, 4, 0.01)
	import_root_motion.tooltip_text = "0 keeps Oathwake CharacterBody2D movement authoritative. Increase only when deliberately importing root motion."
	_add_row(box, "Root translation scale", import_root_motion)

	_add_heading(box, "3 · Bone correlation")
	var note := Label.new()
	note.text = "Auto mapping handles common Mixamo names. Every source bone can be redirected manually if a custom skeleton uses different names or the automatic match deforms the pose."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	mapping_container = VBoxContainer.new()
	box.add_child(mapping_container)

	_add_heading(box, "4 · Test / save")
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var preview := Button.new()
	preview.text = "Preview Retarget"
	preview.pressed.connect(_preview_import)
	actions.add_child(preview)
	var save := Button.new()
	save.text = "Save to Animation Bank"
	save.pressed.connect(_save_import)
	actions.add_child(save)


func _build_manual_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Manual_Animator"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "Animation")
	manual_name_edit = LineEdit.new()
	manual_name_edit.text = "OW_manual_animation"
	_add_row(box, "Name", manual_name_edit)
	manual_fps_spin = _make_spin(30, 1, 120, 1)
	manual_fps_spin.tooltip_text = "The studio converts this value to Juno's 60-tick runtime clock when saving."
	_add_row(box, "Timeline FPS", manual_fps_spin)
	manual_loop_check = CheckBox.new()
	manual_loop_check.button_pressed = true
	_add_row(box, "Loop", manual_loop_check)

	_add_heading(box, "Keyframe editor")
	manual_bone_option = OptionButton.new()
	_add_row(box, "Bone", manual_bone_option)
	manual_frame_spin = _make_spin(0, 0, 9999, 1)
	_add_row(box, "Frame", manual_frame_spin)
	manual_yaw = _make_spin(0, -360, 360, 0.5)
	_add_row(box, "Yaw", manual_yaw)
	manual_pitch = _make_spin(0, -360, 360, 0.5)
	_add_row(box, "Pitch", manual_pitch)
	manual_roll = _make_spin(0, -360, 360, 0.5)
	_add_row(box, "Roll", manual_roll)
	manual_x = _make_spin(0, -8, 8, 0.01)
	_add_row(box, "Translate X", manual_x)
	manual_y = _make_spin(0, -8, 8, 0.01)
	_add_row(box, "Translate Y", manual_y)
	manual_z = _make_spin(0, -8, 8, 0.01)
	_add_row(box, "Translate Z", manual_z)
	manual_spline = OptionButton.new()
	for spline in ["LINEAR", "EASE_IN", "EASE_OUT", "EASE_IN_OUT", "EASE_IN_STRONG", "EASE_OUT_STRONG"]:
		manual_spline.add_item(spline)
		manual_spline.set_item_metadata(manual_spline.item_count - 1, spline)
	_add_row(box, "Tween to this key", manual_spline)

	var key_actions := HBoxContainer.new()
	box.add_child(key_actions)
	var add_key := Button.new()
	add_key.text = "Add / Update Key"
	add_key.pressed.connect(_manual_add_key)
	key_actions.add_child(add_key)
	var remove_key := Button.new()
	remove_key.text = "Delete Selected Key"
	remove_key.pressed.connect(_manual_delete_key)
	key_actions.add_child(remove_key)

	manual_key_list = ItemList.new()
	manual_key_list.custom_minimum_size = Vector2(0, 220)
	manual_key_list.item_selected.connect(_manual_select_key)
	box.add_child(manual_key_list)

	var preview_actions := HBoxContainer.new()
	box.add_child(preview_actions)
	var preview := Button.new()
	preview.text = "Preview Manual Animation"
	preview.pressed.connect(_preview_manual)
	preview_actions.add_child(preview)
	var save := Button.new()
	save.text = "Save Manual Animation to Bank"
	save.pressed.connect(_save_manual)
	preview_actions.add_child(save)
	var clear := Button.new()
	clear.text = "Clear Timeline"
	clear.pressed.connect(func() -> void:
		manual_keys.clear()
		_refresh_manual_key_list()
	)
	preview_actions.add_child(clear)

	var hint := Label.new()
	hint.text = "Sprites stay attached to the bones while you pose them. Lower Sprite Opacity on the right to inspect the skeleton. Tweening uses the same quaternion interpolation path as the runtime, not pixel-frame morphing."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


func _build_preview_controls(parent: VBoxContainer) -> void:
	_add_heading(parent, "Live Juno Preview")
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0.0
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.05
	opacity_slider.value = 0.40
	opacity_slider.value_changed.connect(_on_opacity_changed)
	_add_row(parent, "Sprite opacity", opacity_slider)
	bone_visibility_check = CheckBox.new()
	bone_visibility_check.button_pressed = true
	bone_visibility_check.toggled.connect(_on_bones_toggled)
	_add_row(parent, "Show bones", bone_visibility_check)
	facing_option = OptionButton.new()
	for label in MASTER_DIRECTIONS.keys():
		facing_option.add_item(label)
		facing_option.set_item_metadata(facing_option.item_count - 1, MASTER_DIRECTIONS[label])
	facing_option.select(4)
	facing_option.item_selected.connect(_on_facing_selected)
	_add_row(parent, "View direction", facing_option)


func _build_preview_container(parent: VBoxContainer) -> void:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(620, 620)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.stretch = true
	parent.add_child(holder)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(620, 620)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	holder.add_child(viewport)
	preview_world = Node2D.new()
	preview_world.position = Vector2(310, 335)
	viewport.add_child(preview_world)


func _build_preview() -> void:
	rig = RigScript.new()
	rig.name = "JunoBoneStudioRig"
	preview_world.add_child(rig)
	rig.scale = Vector2.ONE * 3.2
	rig.call_deferred("set_sprite_opacity", opacity_slider.value)
	rig.call_deferred("set_debug_enabled", true)
	rig.call_deferred("set_facing_from_vector", Vector2.DOWN)
	call_deferred("_populate_manual_bones")


func _on_source_selected(path: String) -> void:
	source_path = path
	source_path_label.text = path
	var info := Importer.inspect_scene(path)
	if not bool(info.get("ok", false)):
		_set_status(str(info.get("error", "Could not inspect source.")), true)
		return
	source_clip_option.clear()
	for clip in info.get("clips", []):
		source_clip_option.add_item(str(clip))
		source_clip_option.set_item_metadata(source_clip_option.item_count - 1, str(clip))
	source_bones.clear()
	for bone in info.get("bones", []):
		source_bones.append(str(bone))
	_rebuild_mapping_table()
	if source_clip_option.item_count > 0:
		import_name_edit.text = "OW_%s" % _sanitize_name(str(source_clip_option.get_item_metadata(0)))
	_set_status("Loaded %d clips and %d source bones." % [source_clip_option.item_count, source_bones.size()])


func _rebuild_mapping_table() -> void:
	mapping_controls.clear()
	for child in mapping_container.get_children():
		child.queue_free()
	var targets: Array = []
	if rig != null and rig.has_method("get_bone_names"):
		var runtime_names: Variant = rig.call("get_bone_names")
		if runtime_names is Array:
			targets = (runtime_names as Array).duplicate()
	var auto := Importer.make_auto_retarget(source_bones)
	for source_bone in source_bones:
		var option := OptionButton.new()
		option.add_item("-- Ignore --")
		option.set_item_metadata(0, "")
		var selected := 0
		for target_value in targets:
			var target := str(target_value)
			option.add_item(target)
			option.set_item_metadata(option.item_count - 1, target)
			if target == str(auto.get(source_bone, "")):
				selected = option.item_count - 1
		option.select(selected)
		_add_row(mapping_container, source_bone, option)
		mapping_controls[source_bone] = option


func _preview_import() -> void:
	var data := _build_import_animation()
	if data.is_empty():
		return
	if not rig.install_runtime_animation("__import_preview", data):
		_set_status("Could not install imported preview.", true)
		return
	rig.set_animation("__import_preview")
	_set_status("Retarget preview running. Adjust mapping/corrections and preview again until it sits naturally on Juno.")


func _save_import() -> void:
	var data := _build_import_animation()
	if data.is_empty():
		return
	var animation_name := _sanitize_name(import_name_edit.text)
	if animation_name.is_empty():
		_set_status("Choose a name for the imported animation.", true)
		return
	var meta := {
		"type": "retarget_import",
		"source_path": source_path,
		"source_clip": _selected_clip(),
		"mapping": _get_mapping(),
		"settings": _get_import_settings(),
	}
	if not Library.save_custom_animation(animation_name, data, meta):
		_set_status("Could not save animation bank. Run the Bone Studio from the editable project, not an exported build.", true)
		return
	rig.install_runtime_animation(animation_name, data)
	rig.set_animation(animation_name)
	_set_status("Saved '%s' to %s." % [animation_name, Library.CUSTOM_BANK_PATH])


func _build_import_animation() -> Dictionary:
	if source_path.is_empty() or source_clip_option.item_count <= 0:
		_set_status("Choose a source scene and animation clip first.", true)
		return {}
	return Importer.import_scene_clip(
		source_path,
		_selected_clip(),
		import_fps.value,
		import_loop.button_pressed,
		0.0,
		_get_mapping(),
		_get_import_settings()
	)


func _selected_clip() -> String:
	if source_clip_option.selected < 0:
		return ""
	return str(source_clip_option.get_item_metadata(source_clip_option.selected))


func _get_mapping() -> Dictionary:
	var result := {}
	for source_bone in mapping_controls.keys():
		var option := mapping_controls[source_bone] as OptionButton
		if option == null or option.selected < 0:
			result[source_bone] = ""
		else:
			result[source_bone] = str(option.get_item_metadata(option.selected))
	return result


func _get_import_settings() -> Dictionary:
	return {
		"remove_reference_pose": import_reference_pose.button_pressed,
		"top_down_mode": true,
		"yaw_correction_degrees": import_yaw.value,
		"pitch_correction_degrees": import_pitch.value,
		"roll_correction_degrees": import_roll.value,
		"root_translation_scale": import_root_motion.value,
		"category": "DEFAULT",
		"spline": "LINEAR",
	}


func _populate_manual_bones() -> void:
	manual_bone_option.clear()
	if rig == null or not rig.has_method("get_bone_names"):
		return
	var runtime_names: Variant = rig.call("get_bone_names")
	if not runtime_names is Array:
		return
	for bone_name in runtime_names as Array:
		manual_bone_option.add_item(str(bone_name))
		manual_bone_option.set_item_metadata(manual_bone_option.item_count - 1, str(bone_name))


func _manual_add_key() -> void:
	if manual_bone_option.item_count <= 0 or manual_bone_option.selected < 0:
		return
	var frame := int(manual_frame_spin.value)
	var bone := str(manual_bone_option.get_item_metadata(manual_bone_option.selected))
	if not manual_keys.has(frame):
		manual_keys[frame] = {"spline": _manual_spline_value(), "nodeXfm": {}}
	var frame_data: Dictionary = manual_keys[frame]
	frame_data["spline"] = _manual_spline_value()
	var xfm: Dictionary = frame_data.get("nodeXfm", {})
	xfm[bone] = {
		"rot": [manual_yaw.value, manual_pitch.value, manual_roll.value],
		"trans": [manual_x.value, manual_y.value, manual_z.value],
		"scale": 1.0,
	}
	frame_data["nodeXfm"] = xfm
	manual_keys[frame] = frame_data
	_refresh_manual_key_list()
	_set_status("Keyed %s at frame %d." % [bone, frame])


func _manual_delete_key() -> void:
	var selected := manual_key_list.get_selected_items()
	if selected.is_empty():
		return
	var meta: Dictionary = manual_key_list.get_item_metadata(selected[0])
	var frame := int(meta.get("frame", -1))
	var bone := str(meta.get("bone", ""))
	if not manual_keys.has(frame):
		return
	var frame_data: Dictionary = manual_keys[frame]
	var xfm: Dictionary = frame_data.get("nodeXfm", {})
	xfm.erase(bone)
	if xfm.is_empty():
		manual_keys.erase(frame)
	else:
		frame_data["nodeXfm"] = xfm
		manual_keys[frame] = frame_data
	_refresh_manual_key_list()


func _manual_select_key(index: int) -> void:
	var meta: Dictionary = manual_key_list.get_item_metadata(index)
	var frame := int(meta.get("frame", 0))
	var bone := str(meta.get("bone", ""))
	manual_frame_spin.value = frame
	_select_option_metadata(manual_bone_option, bone)
	var frame_data: Dictionary = manual_keys.get(frame, {})
	var frame_xfm_value: Variant = frame_data.get("nodeXfm", {})
	var frame_xfm: Dictionary = frame_xfm_value as Dictionary if frame_xfm_value is Dictionary else {}
	var bone_xfm_value: Variant = frame_xfm.get(bone, {})
	var bone_xfm: Dictionary = bone_xfm_value as Dictionary if bone_xfm_value is Dictionary else {}
	var rot: Array = bone_xfm.get("rot", [0.0, 0.0, 0.0])
	var trans: Array = bone_xfm.get("trans", [0.0, 0.0, 0.0])
	manual_yaw.value = float(rot[0])
	manual_pitch.value = float(rot[1])
	manual_roll.value = float(rot[2])
	manual_x.value = float(trans[0])
	manual_y.value = float(trans[1])
	manual_z.value = float(trans[2])


func _refresh_manual_key_list() -> void:
	manual_key_list.clear()
	var frames: Array = manual_keys.keys()
	frames.sort()
	for frame_value in frames:
		var frame := int(frame_value)
		var frame_data: Dictionary = manual_keys[frame]
		var xfm: Dictionary = frame_data.get("nodeXfm", {})
		var bones: Array = xfm.keys()
		bones.sort()
		for bone_value in bones:
			var bone := str(bone_value)
			var bone_data: Dictionary = xfm[bone]
			manual_key_list.add_item("F%04d  %-12s  %s" % [frame, bone, str(bone_data.get("rot", []))])
			manual_key_list.set_item_metadata(manual_key_list.item_count - 1, {"frame": frame, "bone": bone})


func _build_manual_animation() -> Dictionary:
	if manual_keys.is_empty():
		_set_status("Add at least one manual keyframe first.", true)
		return {}
	var frames: Array = manual_keys.keys()
	frames.sort()
	var transforms := []
	for frame_value in frames:
		var frame := int(frame_value)
		var frame_data: Dictionary = manual_keys[frame]
		var node_xfm_value: Variant = frame_data.get("nodeXfm", {})
		var node_xfm: Dictionary = node_xfm_value as Dictionary if node_xfm_value is Dictionary else {}
		transforms.append({
			"frame": frame,
			"spline": str(frame_data.get("spline", "LINEAR")),
			"nodeXfm": node_xfm.duplicate(true),
		})
	var last_frame := int(frames.back())
	var timeline_fps := maxf(manual_fps_spin.value, 1.0)
	return {
		"category": "DEFAULT",
		"frameCnt": maxi(last_frame, 1),
		"frameRepeat": ALABASTER_TICK_RATE / timeline_fps,
		"animStart": 0,
		"loopStart": 0,
		"repeat": manual_loop_check.button_pressed,
		"transforms": transforms,
		"nodes": {},
		"manual_meta": {
			"timeline_fps": timeline_fps,
			"alabaster_frame_repeat": ALABASTER_TICK_RATE / timeline_fps,
			"studio": "AlabasterBoneStudio",
		},
	}


func _preview_manual() -> void:
	var data := _build_manual_animation()
	if data.is_empty():
		return
	rig.install_runtime_animation("__manual_preview", data)
	rig.set_animation("__manual_preview")
	_set_status("Manual animation preview running.")


func _save_manual() -> void:
	var data := _build_manual_animation()
	if data.is_empty():
		return
	var animation_name := _sanitize_name(manual_name_edit.text)
	if animation_name.is_empty():
		_set_status("Choose a manual animation name.", true)
		return
	if not Library.save_custom_animation(animation_name, data, {"type": "manual", "studio": "AlabasterBoneStudio"}):
		_set_status("Could not save custom animation bank.", true)
		return
	rig.install_runtime_animation(animation_name, data)
	rig.set_animation(animation_name)
	_set_status("Saved manual animation '%s' to the animation bank." % animation_name)


func _on_opacity_changed(value: float) -> void:
	if rig != null and rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", value)


func _on_bones_toggled(enabled: bool) -> void:
	if rig != null and rig.has_method("set_debug_enabled"):
		rig.call("set_debug_enabled", enabled)


func _on_facing_selected(index: int) -> void:
	if rig == null or index < 0:
		return
	var direction_value: Variant = facing_option.get_item_metadata(index)
	if direction_value is Vector2:
		rig.set_facing_from_vector(direction_value as Vector2)


func _manual_spline_value() -> String:
	if manual_spline.selected < 0:
		return "LINEAR"
	return str(manual_spline.get_item_metadata(manual_spline.selected))


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)


func _add_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(210, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _make_spin(value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	return spin


func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _sanitize_name(value: String) -> String:
	var result := value.strip_edges().replace(" ", "_").replace("-", "_")
	var clean := ""
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_"
	for character in result:
		var normalized := str(character).to_lower()
		if allowed.contains(normalized):
			clean += str(character)
	return clean


func _set_status(message: String, is_error := false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if is_error else Color(0.65, 0.95, 0.72))
	print("ALABASTER_BONE_STUDIO: %s" % message)
