extends "res://scripts/labs/alabaster/AlabasterBoneStudioImportSourceFix.gd"

# Bone Studio workspace layout layer.
# Keeps editor-only sizing/responsiveness out of the gameplay rig and out of the
# retarget/import logic. The studio should feel like a desktop DCC tool, not a
# 1600x900 game menu squeezed into the middle of a large monitor.

const MIN_LOGICAL_SIZE := Vector2i(1920, 1080)
const MAX_LOGICAL_SIZE := Vector2i(2560, 1440)
const LEFT_MIN_WIDTH := 920.0
const RIGHT_MIN_WIDTH := 620.0
const WORKSPACE_LEFT_RATIO := 0.64

var _workspace_tabs: TabContainer = null
var _main_split: HSplitContainer = null
var _preview_panel: Control = null
var _preview_holder: SubViewportContainer = null
var _preview_viewport: SubViewport = null
var _layout_installed := false


func _ready() -> void:
	_configure_studio_window()
	super._ready()
	call_deferred("_install_workspace_layout")


func _configure_studio_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen).size
	var logical_width := clampi(usable.x, MIN_LOGICAL_SIZE.x, MAX_LOGICAL_SIZE.x)
	var logical_height := clampi(usable.y, MIN_LOGICAL_SIZE.y, MAX_LOGICAL_SIZE.y)
	var window := get_window()
	if window != null:
		# Lab-only override. The game can keep its 1600x900 project viewport while
		# Bone Studio uses the actual desktop real estate available to it.
		window.content_scale_size = Vector2i(logical_width, logical_height)
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
	_workspace_tabs.custom_minimum_size = Vector2(LEFT_MIN_WIDTH, 760.0)
	if _preview_panel != null:
		_preview_panel.custom_minimum_size = Vector2(RIGHT_MIN_WIDTH, 760.0)
	_main_split.add_theme_constant_override("separation", 14)

	_preview_holder = _find_subviewport_container(_preview_panel)
	if _preview_holder != null:
		_preview_holder.custom_minimum_size = Vector2(RIGHT_MIN_WIDTH, 690.0)
		_preview_viewport = _preview_holder.get_child(0) as SubViewport if _preview_holder.get_child_count() > 0 else null
		if not _preview_holder.resized.is_connected(_resize_juno_preview):
			_preview_holder.resized.connect(_resize_juno_preview)

	_polish_controls(self)
	if not resized.is_connected(_apply_responsive_layout):
		resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_resize_juno_preview()


func _apply_responsive_layout() -> void:
	if _main_split == null:
		return
	var available_width := maxf(size.x - 42.0, LEFT_MIN_WIDTH + RIGHT_MIN_WIDTH + 14.0)
	var desired_left := available_width * WORKSPACE_LEFT_RATIO
	var maximum_left := maxf(LEFT_MIN_WIDTH, available_width - RIGHT_MIN_WIDTH - 14.0)
	_main_split.split_offset = int(clampf(desired_left, LEFT_MIN_WIDTH, maximum_left))


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
		var fit := clampf(minf(holder_size.x, holder_size.y) / 180.0, 3.4, 5.4)
		(rig as Node2D).scale = Vector2.ONE * fit


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
