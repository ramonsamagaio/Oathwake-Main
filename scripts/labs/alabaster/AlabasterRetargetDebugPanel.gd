extends VBoxContainer

# Screen-recording-friendly diagnostics for Mixamo -> Juno retargeting.
# Every important stage is surfaced as stable text/numbers so a captured video is
# enough to identify whether a defect comes from source hierarchy, REST axes,
# mapping, lost motion, discontinuity, root motion, or Juno's target axes.

const Diagnostics := preload("res://scripts/labs/alabaster/AlabasterRetargetDiagnostics.gd")

const CORE_BONES := [
	"root", "bottom", "top", "head",
	"armL", "handL", "fingerL",
	"armR", "handR", "fingerR",
	"legL", "footL", "toeL",
	"legR", "footR", "toeR",
]

const AXIS_PHASES := [
	"REST",
	"YAW +45",
	"YAW -45",
	"PITCH +45",
	"PITCH -45",
	"ROLL +45",
	"ROLL -45",
	"REST",
]

var host: Control = null
var last_audit: Dictionary = {}
var last_report_text := ""

var status_badge: Label = null
var source_summary: Label = null
var issues_list: ItemList = null
var motion_text: TextEdit = null
var target_text: TextEdit = null
var source_tree_text: TextEdit = null
var frame_spin: SpinBox = null
var frame_detail: TextEdit = null
var axis_bone_option: OptionButton = null
var axis_phase_label: Label = null
var save_path_label: Label = null
var limb_mode_option: OptionButton = null


func setup(owner: Control) -> void:
	host = owner
	name = "RETARGET DEBUG"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	var tabs := _find_tabs(owner)
	if tabs == null:
		return
	tabs.add_child(self)
	_refresh_target_structure()
	_refresh_source_header()
	set_process(true)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_axis_phase()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "RETARGET DEBUG V8 · MIXAMO → JUNO"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	var intro := Label.new()
	intro.text = "This tab is read-only diagnostics. RUN DEEP AUDIT checks source REST/hierarchy/tracks, semantic mapping, motion loss, one-frame jumps and the final Juno output. Numbers stay visible so a screen recording is enough for remote diagnosis."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	status_badge = Label.new()
	status_badge.text = "STATUS: NOT RUN"
	status_badge.add_theme_font_size_override("font_size", 18)
	box.add_child(status_badge)

	source_summary = Label.new()
	source_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(source_summary)

	var solver_row := HBoxContainer.new()
	box.add_child(solver_row)
	var solver_label := Label.new()
	solver_label.text = "Limb solve"
	solver_label.custom_minimum_size = Vector2(120.0, 0.0)
	solver_row.add_child(solver_label)
	limb_mode_option = OptionButton.new()
	limb_mode_option.add_item("V8 Full global delta · preserves twist")
	limb_mode_option.set_item_metadata(0, "full_global_delta")
	limb_mode_option.add_item("V7 Segment swing · 2DOF fallback")
	limb_mode_option.set_item_metadata(1, "segment_swing")
	limb_mode_option.item_selected.connect(_on_limb_mode_selected)
	solver_row.add_child(limb_mode_option)

	var actions := HBoxContainer.new()
	box.add_child(actions)

	var audit_button := Button.new()
	audit_button.text = "RUN DEEP AUDIT"
	audit_button.tooltip_text = "Inspect the selected source and compute a fresh Mixamo → Juno V8 diagnostic report."
	audit_button.pressed.connect(_run_deep_audit)
	actions.add_child(audit_button)

	var preview_button := Button.new()
	preview_button.text = "PREVIEW V8 + AUDIT"
	preview_button.tooltip_text = "Preview the current retarget in the visible Juno rig, then run the same deep audit."
	preview_button.pressed.connect(_preview_and_audit)
	actions.add_child(preview_button)

	var copy_button := Button.new()
	copy_button.text = "COPY REPORT"
	copy_button.pressed.connect(_copy_report)
	actions.add_child(copy_button)

	var save_button := Button.new()
	save_button.text = "SAVE REPORT"
	save_button.pressed.connect(_save_report)
	actions.add_child(save_button)

	save_path_label = Label.new()
	save_path_label.text = "Reports save to user://bonelab_retarget_debug_report.txt + .json"
	save_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(save_path_label)

	_add_heading(box, "Problems found")
	issues_list = ItemList.new()
	issues_list.custom_minimum_size = Vector2(0.0, 180.0)
	issues_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(issues_list)

	_add_heading(box, "Motion transfer · source vs Juno")
	motion_text = _make_readonly_text(230.0)
	box.add_child(motion_text)

	_add_heading(box, "Frame microscope")
	var frame_row := HBoxContainer.new()
	box.add_child(frame_row)
	var frame_label := Label.new()
	frame_label.text = "Audit frame"
	frame_row.add_child(frame_label)
	frame_spin = SpinBox.new()
	frame_spin.min_value = 0
	frame_spin.max_value = 0
	frame_spin.step = 1
	frame_spin.custom_minimum_size = Vector2(120.0, 0.0)
	frame_spin.value_changed.connect(_on_debug_frame_changed)
	frame_row.add_child(frame_spin)
	var hint := Label.new()
	hint.text = "source swing → Juno yaw/pitch/roll + effective parent"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame_row.add_child(hint)
	frame_detail = _make_readonly_text(250.0)
	box.add_child(frame_detail)

	_add_heading(box, "Juno target structure")
	var refresh_target := Button.new()
	refresh_target.text = "REFRESH JUNO TARGET"
	refresh_target.pressed.connect(_refresh_target_structure)
	box.add_child(refresh_target)
	target_text = _make_readonly_text(240.0)
	box.add_child(target_text)

	_add_heading(box, "Source Skeleton3D hierarchy")
	var refresh_source := Button.new()
	refresh_source.text = "READ SOURCE HIERARCHY"
	refresh_source.pressed.connect(_refresh_source_hierarchy)
	box.add_child(refresh_source)
	source_tree_text = _make_readonly_text(260.0)
	box.add_child(source_tree_text)

	_add_heading(box, "Juno axis probe · independent of FBX")
	var axis_info := Label.new()
	axis_info.text = "This synthetic runtime-only animation isolates Juno's own axes. If an axis behaves unexpectedly here, the problem is target semantics rather than Mixamo/FBX."
	axis_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(axis_info)

	var axis_row := HBoxContainer.new()
	box.add_child(axis_row)
	axis_bone_option = OptionButton.new()
	axis_bone_option.custom_minimum_size = Vector2(180.0, 0.0)
	axis_row.add_child(axis_bone_option)

	var run_axis := Button.new()
	run_axis.text = "RUN AXIS PROBE"
	run_axis.pressed.connect(_run_axis_probe)
	axis_row.add_child(run_axis)

	var stop_axis := Button.new()
	stop_axis.text = "RESTORE IDLE"
	stop_axis.pressed.connect(_restore_idle)
	axis_row.add_child(stop_axis)

	axis_phase_label = Label.new()
	axis_phase_label.text = "AXIS PHASE: idle"
	axis_phase_label.add_theme_font_size_override("font_size", 16)
	box.add_child(axis_phase_label)


func _on_limb_mode_selected(index: int) -> void:
	if limb_mode_option == null or index < 0 or index >= limb_mode_option.item_count:
		return
	var mode := str(limb_mode_option.get_item_metadata(index))
	if host != null and host.has_method("set_retarget_limb_mode"):
		host.call("set_retarget_limb_mode", mode)
	_refresh_source_header()


func _run_deep_audit() -> void:
	_refresh_source_header()
	var source_path := _source_path()
	var clip_name := _selected_clip()
	if source_path.is_empty() or clip_name.is_empty():
		_set_local_status("FAIL", "Select a source file and animation clip in Import_Retarget first.")
		return

	var settings := _import_settings()
	var fps := _import_fps()
	var loop := _import_loop()
	var root_scale := float(settings.get("root_translation_scale", 0.0))
	last_audit = Diagnostics.audit_source(
		source_path,
		clip_name,
		fps,
		loop,
		root_scale,
		settings
	)
	_render_audit()


func _preview_and_audit() -> void:
	if host != null and host.has_method("ensure_juno_retarget_target"):
		host.call("ensure_juno_retarget_target")
	if host != null and host.has_method("_preview_import"):
		host.call("_preview_import")
	_run_deep_audit()


func _render_audit() -> void:
	var status := str(last_audit.get("status", "FAIL"))
	_set_status_badge(status)
	issues_list.clear()

	var issues_value: Variant = last_audit.get("issues", [])
	if issues_value is Array:
		for issue_value in issues_value:
			if not issue_value is Dictionary:
				continue
			var issue: Dictionary = issue_value
			var severity := str(issue.get("severity", "INFO"))
			var code := str(issue.get("code", ""))
			var message := str(issue.get("message", ""))
			issues_list.add_item("[%s] %s · %s" % [severity, code, message])
	if issues_list.item_count == 0:
		issues_list.add_item("[PASS] No structural warning was detected by the current audit.")

	_refresh_source_header()
	_render_motion_table()
	_render_frame_controls()
	_refresh_target_structure()
	last_report_text = _build_report_text()


func _render_motion_table() -> void:
	if motion_text == null:
		return
	var source_value: Variant = last_audit.get("source_motion", {})
	var output_value: Variant = last_audit.get("output", {})
	var source: Dictionary = source_value if source_value is Dictionary else {}
	var twist_value: Variant = last_audit.get("source_twist_residual", {})
	var twist: Dictionary = twist_value if twist_value is Dictionary else {}
	var output: Dictionary = output_value if output_value is Dictionary else {}
	var spans_value: Variant = output.get("motion_span_deg", {})
	var steps_value: Variant = output.get("max_step_deg", {})
	var step_frames_value: Variant = output.get("max_step_frame", {})
	var spans: Dictionary = spans_value if spans_value is Dictionary else {}
	var steps: Dictionary = steps_value if steps_value is Dictionary else {}
	var step_frames: Dictionary = step_frames_value if step_frames_value is Dictionary else {}

	var lines: PackedStringArray = PackedStringArray()
	lines.append("TARGET | SOURCE SWING | EXTRA ORIENTATION/TWIST | JUNO SPAN | MAX 1-FRAME STEP")
	lines.append("--------------------------------------------------------------------------------")
	for target in CORE_BONES:
		if target == "root" or target == "bottom" or target == "top" or target == "head":
			var out_span := float(spans.get(target, 0.0))
			var step := float(steps.get(target, 0.0))
			lines.append("%s | body frame | n/a | %.2f° | %.2f° @ %d" % [
				target,
				out_span,
				step,
				int(step_frames.get(target, -1)),
			])
		else:
			var src := float(source.get(target, 0.0))
			var extra := float(twist.get(target, 0.0))
			var out := float(spans.get(target, 0.0))
			var step := float(steps.get(target, 0.0))
			lines.append("%s | %.2f° | %.2f° | %.2f° | %.2f° @ %d" % [
				target,
				src,
				extra,
				out,
				step,
				int(step_frames.get(target, -1)),
			])
	lines.append("")
	lines.append("Max root translation: %.4f" % float(output.get("max_root_translation", 0.0)))
	motion_text.text = "\n".join(lines)


func _render_frame_controls() -> void:
	var frames_value: Variant = last_audit.get("frame_diagnostics", [])
	if not frames_value is Array or (frames_value as Array).is_empty():
		frame_spin.min_value = 0
		frame_spin.max_value = 0
		frame_spin.value = 0
		frame_detail.text = "No per-frame diagnostic data. A full Skeleton3D source is required."
		return

	var frames: Array = frames_value
	frame_spin.min_value = 0
	frame_spin.max_value = frames.size() - 1
	frame_spin.value = clampi(int(frame_spin.value), 0, frames.size() - 1)
	_render_frame_detail(int(frame_spin.value))


func _on_debug_frame_changed(value: float) -> void:
	_render_frame_detail(int(value))


func _render_frame_detail(frame_index: int) -> void:
	if frame_detail == null:
		return
	var frames_value: Variant = last_audit.get("frame_diagnostics", [])
	if not frames_value is Array:
		frame_detail.text = ""
		return
	var frames: Array = frames_value
	if frame_index < 0 or frame_index >= frames.size():
		frame_detail.text = ""
		return
	var row_value: Variant = frames[frame_index]
	if not row_value is Dictionary:
		frame_detail.text = ""
		return
	var row: Dictionary = row_value
	var targets_value: Variant = row.get("targets", {})
	var targets: Dictionary = targets_value if targets_value is Dictionary else {}

	var lines: PackedStringArray = PackedStringArray()
	lines.append("FRAME %d  |  time %.4fs" % [int(row.get("frame", frame_index)), float(row.get("time", 0.0))])
	lines.append("TARGET | SRC SWING | EXTRA ORIENTATION/TWIST | YAW | PITCH | ROLL | EFFECTIVE PARENT")
	lines.append("--------------------------------------------------------------------------------")
	for target in CORE_BONES:
		if not targets.has(target):
			continue
		var data: Dictionary = targets[target]
		lines.append("%s | src %.2f° | extra %.2f° | yaw %.2f | pitch %.2f | roll %.2f | parent %s" % [
			target,
			float(data.get("source_swing_deg", 0.0)),
			float(data.get("source_twist_residual_deg", 0.0)),
			float(data.get("yaw", 0.0)),
			float(data.get("pitch", 0.0)),
			float(data.get("roll", 0.0)),
			str(data.get("parent", "")),
		])
	frame_detail.text = "\n".join(lines)


func _refresh_target_structure() -> void:
	if target_text == null or axis_bone_option == null:
		return
	var rig := _juno_reference_rig()
	if rig == null:
		target_text.text = "Juno reference rig is not available."
		return

	var bone_names: Array = []
	var parent_map := {}
	if rig.has_method("get_bone_names"):
		var names_value: Variant = rig.call("get_bone_names")
		if names_value is Array:
			bone_names = (names_value as Array).duplicate()
	if rig.has_method("get_bone_parent_map"):
		var map_value: Variant = rig.call("get_bone_parent_map")
		if map_value is Dictionary:
			parent_map = (map_value as Dictionary).duplicate(true)

	var screen_poses := {}
	if rig.has_method("get_all_bone_screen_poses"):
		var pose_value: Variant = rig.call("get_all_bone_screen_poses")
		if pose_value is Dictionary:
			screen_poses = pose_value

	var lines: PackedStringArray = PackedStringArray()
	lines.append("JUNO CANONICAL TARGET · %d nodes" % bone_names.size())
	lines.append("node                 parent               world position")
	lines.append("----------------------------------------------------------------")
	for bone_value in bone_names:
		var bone := str(bone_value)
		var parent := str(parent_map.get(bone, ""))
		var world_text := "-"
		if screen_poses.has(bone):
			var pose: Dictionary = screen_poses[bone]
			world_text = str(pose.get("world_position", Vector3.ZERO))
		lines.append("%s <- %s | world %s" % [bone, parent, world_text])
	target_text.text = "\n".join(lines)

	var previous := ""
	if axis_bone_option.selected >= 0:
		previous = str(axis_bone_option.get_item_metadata(axis_bone_option.selected))
	axis_bone_option.clear()
	var select_index := 0
	for target in CORE_BONES:
		if not bone_names.has(target):
			continue
		axis_bone_option.add_item(target)
		axis_bone_option.set_item_metadata(axis_bone_option.item_count - 1, target)
		if target == previous:
			select_index = axis_bone_option.item_count - 1
	if axis_bone_option.item_count > 0:
		axis_bone_option.select(select_index)


func _refresh_source_hierarchy() -> void:
	if source_tree_text == null:
		return
	var source_path := _source_path()
	if source_path.is_empty():
		source_tree_text.text = "Select a source first."
		return
	var info := Diagnostics.list_source_hierarchy(source_path)
	if not bool(info.get("ok", false)):
		source_tree_text.text = str(info.get("error", "Could not read source hierarchy."))
		return

	var rows_value: Variant = info.get("rows", [])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SOURCE SKELETON · %d bones · %s" % [
		int(info.get("bone_count", 0)),
		str(info.get("resource_kind", "unknown")),
	])
	lines.append("index   bone                              parent")
	lines.append("----------------------------------------------------------------")
	if rows_value is Array:
		for row_value in rows_value:
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			lines.append("%d | %s | parent %s" % [
				int(row.get("index", -1)),
				str(row.get("name", "")),
				str(row.get("parent", "<ROOT>")) if not str(row.get("parent", "")).is_empty() else "<ROOT>",
			])
	source_tree_text.text = "\n".join(lines)


func _run_axis_probe() -> void:
	if host != null and host.has_method("ensure_juno_retarget_target"):
		host.call("ensure_juno_retarget_target")
	var rig := _visible_rig()
	if rig == null:
		_set_local_status("FAIL", "Visible Juno rig is unavailable.")
		return
	if axis_bone_option == null or axis_bone_option.item_count <= 0 or axis_bone_option.selected < 0:
		_set_local_status("FAIL", "Choose a Juno target bone for the axis probe.")
		return
	if not rig.has_method("install_runtime_animation") or not rig.has_method("set_animation"):
		_set_local_status("FAIL", "Visible rig cannot accept runtime probe animations.")
		return

	var bone := str(axis_bone_option.get_item_metadata(axis_bone_option.selected))
	var rotations := [
		[0.0, 0.0, 0.0],
		[45.0, 0.0, 0.0],
		[-45.0, 0.0, 0.0],
		[0.0, 45.0, 0.0],
		[0.0, -45.0, 0.0],
		[0.0, 0.0, 45.0],
		[0.0, 0.0, -45.0],
		[0.0, 0.0, 0.0],
	]
	var transforms: Array = []
	for index in range(rotations.size()):
		transforms.append({
			"frame": index * 12,
			"spline": "EASE_IN_OUT",
			"nodeXfm": {
				bone: {
					"rot": rotations[index],
					"trans": [0.0, 0.0, 0.0],
					"scale": 1.0,
				},
			},
		})
	var animation := {
		"category": "OTHER",
		"frameCnt": 96,
		"frameRepeat": 1.0,
		"animStart": 0,
		"loopStart": 0,
		"repeat": true,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {
			"bridge": "bonelab_juno_axis_probe",
			"target_bone": bone,
		},
	}
	if not bool(rig.call("install_runtime_animation", "__retarget_axis_probe", animation)):
		_set_local_status("FAIL", "Could not install Juno axis probe.")
		return
	rig.call("set_animation", "__retarget_axis_probe")
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", false)
	axis_phase_label.text = "AXIS PHASE: starting probe on %s" % bone


func _restore_idle() -> void:
	var rig := _visible_rig()
	if rig != null and rig.has_method("set_animation"):
		rig.call("set_animation", "idle")
	axis_phase_label.text = "AXIS PHASE: idle"


func _refresh_axis_phase() -> void:
	if axis_phase_label == null:
		return
	var rig := _visible_rig()
	if rig == null:
		return
	var summary := {}
	if rig.has_method("get_runtime_summary"):
		var summary_value: Variant = rig.call("get_runtime_summary")
		if summary_value is Dictionary:
			summary = summary_value
	if str(summary.get("animation", "")) != "__retarget_axis_probe":
		return
	if not rig.has_method("get_current_source_frame"):
		return
	var frame := int(round(float(rig.call("get_current_source_frame"))))
	var phase_index := clampi(int(floor(float(frame) / 12.0)), 0, AXIS_PHASES.size() - 1)
	var bone := ""
	if axis_bone_option != null and axis_bone_option.selected >= 0:
		bone = str(axis_bone_option.get_item_metadata(axis_bone_option.selected))
	axis_phase_label.text = "AXIS PHASE: %s · %s · frame %d" % [
		bone,
		str(AXIS_PHASES[phase_index]),
		frame,
	]


func _build_report_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("OATHWAKE BONELAB RETARGET DEBUG V8")
	lines.append("=================================")
	lines.append("STATUS: %s" % str(last_audit.get("status", "NOT RUN")))
	lines.append("SOURCE: %s" % str(last_audit.get("source_path", _source_path())))
	lines.append("RESOURCE: %s" % str(last_audit.get("resource_kind", "unknown")))
	lines.append("CLIP: %s" % str(last_audit.get("clip", _selected_clip())))
	lines.append("SKELETON3D: %s" % ("YES" if bool(last_audit.get("has_skeleton", false)) else "NO"))
	lines.append("SOURCE BONES: %d" % int(last_audit.get("source_bone_count", 0)))
	lines.append("ROT/POS/SCALE TRACKS: %d / %d / %d" % [
		int(last_audit.get("rotation_track_count", 0)),
		int(last_audit.get("position_track_count", 0)),
		int(last_audit.get("scale_track_count", 0)),
	])
	lines.append("")
	lines.append("ISSUES")
	lines.append("------")
	for issue_value in last_audit.get("issues", []):
		if issue_value is Dictionary:
			var issue: Dictionary = issue_value
			lines.append("[%s] %s · %s" % [
				str(issue.get("severity", "INFO")),
				str(issue.get("code", "")),
				str(issue.get("message", "")),
			])
	lines.append("")
	lines.append("MOTION")
	lines.append("------")
	lines.append(motion_text.text if motion_text != null else "")
	lines.append("")
	lines.append("TARGET VALIDATION")
	lines.append("-----------------")
	lines.append(str(last_audit.get("target_validation", {})))
	return "\n".join(lines)


func _copy_report() -> void:
	if last_report_text.is_empty():
		last_report_text = _build_report_text()
	DisplayServer.clipboard_set(last_report_text)
	save_path_label.text = "Report copied to clipboard."


func _save_report() -> void:
	if last_report_text.is_empty():
		last_report_text = _build_report_text()
	var text_path := "user://bonelab_retarget_debug_report.txt"
	var json_path := "user://bonelab_retarget_debug_report.json"
	var text_file := FileAccess.open(text_path, FileAccess.WRITE)
	if text_file != null:
		text_file.store_string(last_report_text)
		text_file.close()
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(JSON.stringify(last_audit, "\t"))
		json_file.close()
	save_path_label.text = "Saved: %s and %s" % [text_path, json_path]


func _refresh_source_header() -> void:
	if source_summary == null:
		return
	source_summary.text = "SOURCE: %s\nCLIP: %s\nTARGET: JUNO / BASESKIN semantics\nFPS: %.1f  |  root motion scale: %.3f  |  limb solve: %s" % [
		_source_path() if not _source_path().is_empty() else "<none>",
		_selected_clip() if not _selected_clip().is_empty() else "<none>",
		_import_fps(),
		float(_import_settings().get("root_translation_scale", 0.0)),
		str(_import_settings().get("retarget_limb_mode", "full_global_delta")),
	]


func _set_status_badge(status: String) -> void:
	if status_badge == null:
		return
	status_badge.text = "STATUS: %s" % status
	if status == "PASS":
		status_badge.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	elif status == "WARN":
		status_badge.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	else:
		status_badge.add_theme_color_override("font_color", Color(1.0, 0.35, 0.32))


func _set_local_status(status: String, message: String) -> void:
	last_audit = {
		"status": status,
		"issues": [{
			"severity": status,
			"code": "DEBUG_PANEL",
			"message": message,
		}],
	}
	_render_audit()


func _source_path() -> String:
	if host == null:
		return ""
	return str(host.get("source_path"))


func _selected_clip() -> String:
	if host == null:
		return ""
	var option := host.get("source_clip_option") as OptionButton
	if option == null or option.item_count <= 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _import_settings() -> Dictionary:
	if host != null and host.has_method("_get_import_settings"):
		var value: Variant = host.call("_get_import_settings")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}


func _import_fps() -> float:
	if host == null:
		return 60.0
	var spin := host.get("import_fps") as SpinBox
	return spin.value if spin != null else 60.0


func _import_loop() -> bool:
	if host == null:
		return true
	var check := host.get("import_loop") as CheckBox
	return check.button_pressed if check != null else true


func _visible_rig() -> Object:
	if host == null:
		return null
	var value: Variant = host.get("rig")
	return value as Object if value is Object else null


func _juno_reference_rig() -> Object:
	if host != null and host.has_method("get_retarget_reference_rig"):
		var value: Variant = host.call("get_retarget_reference_rig")
		if value is Object:
			return value as Object
	return _visible_rig()


func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_tabs(child)
		if found != null:
			return found
	return null


func _add_heading(box: VBoxContainer, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 15)
	box.add_child(label)


func _make_readonly_text(min_height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.editable = false
	edit.custom_minimum_size = Vector2(0.0, min_height)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit
