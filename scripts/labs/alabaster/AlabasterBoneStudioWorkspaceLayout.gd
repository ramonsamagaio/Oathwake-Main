extends "res://scripts/labs/alabaster/AlabasterBoneStudioImportSourceFix.gd"

# Bone Studio workspace layout layer.
# The project viewport is now genuinely 1920x1080, and this layer spends that
# space like a desktop DCC tool rather than centering a 1600x900-era panel.

const STUDIO_SIZE := Vector2i(1920, 1080)
const LEFT_MIN_WIDTH := 1040.0
const RIGHT_MIN_WIDTH := 780.0
const WORKSPACE_LEFT_RATIO := 0.58
const JUNO_BONE_PANEL_WIDTH := 250.0

const JUNO_BONE_ORDER := [
	"root", "bottom", "top", "head",
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
	"hipL", "legL", "footL", "toeL",
	"hipR", "legR", "footR", "toeR",
]

var _workspace_tabs: TabContainer = null
var _main_split: HSplitContainer = null
var _preview_panel: Control = null
var _preview_holder: SubViewportContainer = null
var _preview_viewport: SubViewport = null
var _preview_bone_split: HSplitContainer = null
var _juno_bone_list: ItemList = null
var _juno_bone_filter: LineEdit = null
var _juno_bone_detail: Label = null
var _juno_overlay: Control = null
var _layout_installed := false
var _last_rig_instance_id := 0
var _juno_refresh_accumulator := 0.0


func _ready() -> void:
	_configure_studio_window()
	super._ready()
	call_deferred("_install_workspace_layout")


func _process(delta: float) -> void:
	if not _layout_installed:
		return
	_juno_refresh_accumulator += delta
	if _juno_refresh_accumulator < 0.35:
		return
	_juno_refresh_accumulator = 0.0
	var current_id := 0
	if rig != null and rig is Object and is_instance_valid(rig):
		current_id = (rig as Object).get_instance_id()
	if current_id != _last_rig_instance_id:
		_last_rig_instance_id = current_id
		_refresh_juno_bone_list()
		call_deferred("_connect_juno_overlay")


func _configure_studio_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window != null:
		window.content_scale_size = STUDIO_SIZE
		# In a detached run this requests the real desktop window size. In Godot's
		# embedded game view the project.godot viewport size is authoritative.
		if not window.is_embedded():
			window.size = STUDIO_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _install_workspace_layout() -> void:
	if _layout_installed:
		return
	_workspace_tabs = _find_tabs(self)
	if _workspace_tabs == null:
		push_error("Bone Studio layout: could not locate workspace TabContainer.")
		return
	_main_split = _workspace_tabs.get_parent() as HSplitContainer
	if _main_split == null:
		push_error("Bone Studio layout: workspace tabs are not inside the expected HSplitContainer.")
		return

	var tab_index := _workspace_tabs.get_index()
	if tab_index + 1 < _main_split.get_child_count():
		_preview_panel = _main_split.get_child(tab_index + 1) as Control

	_layout_installed = true
	set_process(true)
	_workspace_tabs.custom_minimum_size = Vector2(LEFT_MIN_WIDTH, 820.0)
	if _preview_panel != null:
		_preview_panel.custom_minimum_size = Vector2(RIGHT_MIN_WIDTH, 820.0)
	_main_split.add_theme_constant_override("separation", 14)

	_preview_holder = _find_subviewport_container(_preview_panel)
	if _preview_holder != null:
		# We resize the viewport explicitly because Bone Studio also owns an input
		# overlay. Disabling stretch avoids Godot's repeated "can't change size"
		# warnings and makes the viewport geometry deterministic.
		_preview_holder.stretch = false
		_preview_holder.custom_minimum_size = Vector2(500.0, 720.0)
		_preview_viewport = _preview_holder.get_child(0) as SubViewport if _preview_holder.get_child_count() > 0 else null
		_install_juno_bone_inspector()
		if not _preview_holder.resized.is_connected(_resize_juno_preview):
			_preview_holder.resized.connect(_resize_juno_preview)

	_polish_controls(self)
	if not resized.is_connected(_apply_responsive_layout):
		resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_resize_juno_preview()
	_refresh_juno_bone_list()
	call_deferred("_connect_juno_overlay")


func _apply_responsive_layout() -> void:
	if _main_split == null:
		return
	var available_width := maxf(size.x - 42.0, LEFT_MIN_WIDTH + RIGHT_MIN_WIDTH + 14.0)
	var desired_left := available_width * WORKSPACE_LEFT_RATIO
	var maximum_left := maxf(LEFT_MIN_WIDTH, available_width - RIGHT_MIN_WIDTH - 14.0)
	_main_split.split_offset = int(clampf(desired_left, LEFT_MIN_WIDTH, maximum_left))
	if _preview_bone_split != null:
		var preview_width := maxf(_preview_bone_split.size.x, 500.0 + JUNO_BONE_PANEL_WIDTH + 12.0)
		_preview_bone_split.split_offset = int(maxf(500.0, preview_width - JUNO_BONE_PANEL_WIDTH - 12.0))


func _resize_juno_preview() -> void:
	if _preview_holder == null or _preview_viewport == null:
		return
	var holder_size := _preview_holder.size
	if holder_size.x < 4.0 or holder_size.y < 4.0:
		return
	_preview_viewport.size = Vector2i(maxi(int(holder_size.x), 4), maxi(int(holder_size.y), 4))
	if preview_world != null:
		preview_world.position = Vector2(holder_size.x * 0.5, holder_size.y * 0.53)
	if rig != null and rig is Node2D:
		var fit := clampf(minf(holder_size.x, holder_size.y) / 180.0, 3.4, 5.8)
		(rig as Node2D).scale = Vector2.ONE * fit
	if _juno_overlay != null:
		_juno_overlay.position = Vector2.ZERO
		_juno_overlay.size = holder_size
		if _juno_overlay.has_method("set_preview_origin") and preview_world != null:
			_juno_overlay.call("set_preview_origin", preview_world.position)


func _install_juno_bone_inspector() -> void:
	if _preview_holder == null or _preview_holder.get_parent() == null or _preview_bone_split != null:
		return
	var original_parent := _preview_holder.get_parent() as Control
	if original_parent == null:
		return
	var holder_index := _preview_holder.get_index()
	original_parent.remove_child(_preview_holder)

	_preview_bone_split = HSplitContainer.new()
	_preview_bone_split.name = "JunoPreviewAndBoneList"
	_preview_bone_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_bone_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_bone_split.add_theme_constant_override("separation", 12)
	original_parent.add_child(_preview_bone_split)
	original_parent.move_child(_preview_bone_split, holder_index)
	_preview_bone_split.add_child(_preview_holder)

	var inspector := VBoxContainer.new()
	inspector.name = "JunoBoneInspector"
	inspector.custom_minimum_size = Vector2(JUNO_BONE_PANEL_WIDTH, 720.0)
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 7)
	_preview_bone_split.add_child(inspector)

	var title := Label.new()
	title.text = "JUNO BONES"
	title.add_theme_font_size_override("font_size", 17)
	inspector.add_child(title)

	var hint := Label.new()
	hint.text = "Click a Juno bone to highlight it on the character. This is the target-side equivalent of the source bone list."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.78))
	inspector.add_child(hint)

	_juno_bone_filter = LineEdit.new()
	_juno_bone_filter.placeholder_text = "Filter Juno bones..."
	_juno_bone_filter.custom_minimum_size.y = 38.0
	_juno_bone_filter.text_changed.connect(_on_juno_bone_filter_changed)
	inspector.add_child(_juno_bone_filter)

	_juno_bone_list = ItemList.new()
	_juno_bone_list.name = "JunoBoneList"
	_juno_bone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_juno_bone_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_juno_bone_list.custom_minimum_size = Vector2(JUNO_BONE_PANEL_WIDTH, 560.0)
	_juno_bone_list.select_mode = ItemList.SELECT_SINGLE
	_juno_bone_list.item_selected.connect(_on_juno_bone_selected)
	inspector.add_child(_juno_bone_list)

	_juno_bone_detail = Label.new()
	_juno_bone_detail.text = "Select a bone"
	_juno_bone_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_juno_bone_detail.custom_minimum_size.y = 48.0
	inspector.add_child(_juno_bone_detail)

	if not _preview_bone_split.resized.is_connected(_apply_responsive_layout):
		_preview_bone_split.resized.connect(_apply_responsive_layout)


func _refresh_juno_bone_list() -> void:
	if _juno_bone_list == null:
		return
	var previous := _selected_juno_bone_from_list()
	_juno_bone_list.clear()
	if rig == null or not rig.has_method("get_bone_names"):
		return
	var names_value: Variant = rig.call("get_bone_names")
	if not names_value is Array:
		return
	var names: Array[String] = []
	for name_value in names_value:
		names.append(str(name_value))
	var ordered := _ordered_juno_bones(names)
	var filter_text := _juno_bone_filter.text.strip_edges().to_lower() if _juno_bone_filter != null else ""
	var parent_map := {}
	if rig.has_method("get_bone_parent_map"):
		var parent_value: Variant = rig.call("get_bone_parent_map")
		if parent_value is Dictionary:
			parent_map = parent_value as Dictionary
	for bone_name in ordered:
		if not filter_text.is_empty() and not bone_name.to_lower().contains(filter_text):
			continue
		var parent := str(parent_map.get(bone_name, ""))
		var display := bone_name
		if not parent.is_empty():
			display = "%s   ← %s" % [bone_name, parent]
		_juno_bone_list.add_item(display)
		var index := _juno_bone_list.item_count - 1
		_juno_bone_list.set_item_metadata(index, bone_name)
		_juno_bone_list.set_item_tooltip(index, "%s · parent: %s" % [bone_name, parent if not parent.is_empty() else "<root>"])
		if bone_name == previous:
			_juno_bone_list.select(index)


func _ordered_juno_bones(names: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for preferred_value in JUNO_BONE_ORDER:
		var preferred := str(preferred_value)
		if names.has(preferred) and not result.has(preferred):
			result.append(preferred)
	var remainder := names.duplicate()
	remainder.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	)
	for name in remainder:
		if not result.has(name):
			result.append(name)
	return result


func _on_juno_bone_filter_changed(_text: String) -> void:
	_refresh_juno_bone_list()


func _on_juno_bone_selected(index: int) -> void:
	if _juno_bone_list == null or index < 0 or index >= _juno_bone_list.item_count:
		return
	var bone_name := str(_juno_bone_list.get_item_metadata(index))
	_select_juno_bone(bone_name, false)


func _select_juno_bone(bone_name: String, sync_list: bool = true) -> void:
	if bone_name.is_empty():
		return
	# Reuse Live Tuning's selection path when available so the green sprite tint,
	# overlay gizmo and tuning controls all agree on the same target bone.
	if _live_tuning_panel != null and is_instance_valid(_live_tuning_panel) and _live_tuning_panel.has_method("_on_workspace_bone_selected"):
		_live_tuning_panel.call("_on_workspace_bone_selected", bone_name)
	else:
		if rig != null and rig.has_method("set_selected_sprite_part"):
			rig.call("set_selected_sprite_part", bone_name)
		if _juno_overlay != null and _juno_overlay.has_method("set_selected_bone"):
			_juno_overlay.call("set_selected_bone", bone_name)

	if sync_list:
		_select_juno_bone_in_list(bone_name)
	if _juno_bone_detail != null:
		var parent := ""
		if rig != null and rig.has_method("get_bone_parent_map"):
			var parent_value: Variant = rig.call("get_bone_parent_map")
			if parent_value is Dictionary:
				parent = str((parent_value as Dictionary).get(bone_name, ""))
		_juno_bone_detail.text = "%s\nParent: %s" % [bone_name, parent if not parent.is_empty() else "<root>"]


func _connect_juno_overlay() -> void:
	if _preview_holder == null:
		return
	var found := _find_node_named(_preview_holder, "InteractiveBoneViewportOverlay") as Control
	if found == null:
		return
	_juno_overlay = found
	if _juno_overlay.has_signal("bone_selected"):
		var callback := Callable(self, "_on_juno_overlay_bone_selected")
		if not _juno_overlay.is_connected("bone_selected", callback):
			_juno_overlay.connect("bone_selected", callback)
	_resize_juno_preview()


func _on_juno_overlay_bone_selected(bone_name: String) -> void:
	_select_juno_bone_in_list(bone_name)
	if _juno_bone_detail != null:
		_select_juno_bone(bone_name, false)


func _select_juno_bone_in_list(bone_name: String) -> void:
	if _juno_bone_list == null:
		return
	for index in range(_juno_bone_list.item_count):
		if str(_juno_bone_list.get_item_metadata(index)) == bone_name:
			_juno_bone_list.select(index)
			_juno_bone_list.ensure_current_is_visible()
			return


func _selected_juno_bone_from_list() -> String:
	if _juno_bone_list == null:
		return ""
	var selected := _juno_bone_list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(_juno_bone_list.get_item_metadata(int(selected[0])))


func _polish_controls(node: Node) -> void:
	if node is Button:
		var button := node as Button
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 38.0)
		button.add_theme_font_size_override("font_size", 14)
	elif node is OptionButton:
		var option := node as OptionButton
		option.custom_minimum_size.y = maxf(option.custom_minimum_size.y, 38.0)
		option.add_theme_font_size_override("font_size", 14)
	elif node is LineEdit:
		var edit := node as LineEdit
		edit.custom_minimum_size.y = maxf(edit.custom_minimum_size.y, 38.0)
		edit.add_theme_font_size_override("font_size", 14)
	elif node is SpinBox:
		var spin := node as SpinBox
		spin.custom_minimum_size.y = maxf(spin.custom_minimum_size.y, 38.0)
	elif node is CheckBox:
		var check := node as CheckBox
		check.custom_minimum_size.y = maxf(check.custom_minimum_size.y, 34.0)
		check.add_theme_font_size_override("font_size", 14)
	elif node is Label:
		var label := node as Label
		if label.text.begins_with("ALABASTER BONE STUDIO"):
			label.add_theme_font_size_override("font_size", 24)

	for child_value in node.get_children():
		var child := child_value as Node
		if child != null:
			_polish_controls(child)


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


func _find_subviewport_container(node: Node) -> SubViewportContainer:
	if node == null:
		return null
	if node is SubViewportContainer:
		return node as SubViewportContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_subviewport_container(child)
		if found != null:
			return found
	return null


func _find_node_named(node: Node, target_name: String) -> Node:
	if str(node.name) == target_name:
		return node
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_node_named(child, target_name)
		if found != null:
			return found
	return null
