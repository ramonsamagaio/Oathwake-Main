extends "res://tools/content_editor/ContentEditorLivePreviewSuite.gd"

const WORKSPACE_MINIMUM_SIZE := Vector2i(960, 620)
const DEFAULT_SIDEBAR_WIDTH := 155
const DEFAULT_RECORD_WIDTH := 320
const FORM_SCROLL_MINIMUM_WIDTH := 720.0

var _record_panel: Control
var _content_split: HSplitContainer
var _record_toggle_button: Button
var _maximize_button: Button
var _sidebar_scroll: ScrollContainer


func _configure_content_editor_window() -> void:
	# Configure only the Window that owns this editor. The previous base behavior
	# called DisplayServer methods for window 0, which could resize the game while
	# the live editor was opening.
	var window := get_window()
	if window == null:
		return
	window.min_size = WORKSPACE_MINIMUM_SIZE
	window.unresizable = false
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = Vector2i.ZERO


func _get_editor_available_size() -> Vector2:
	# Embedded windows can report the parent game viewport through get_viewport_rect().
	# The actual subwindow size is authoritative; using the larger parent size made
	# the bottom of the editor exist outside the visible window with no way to reach it.
	var window := get_window()
	if window != null and window.size.x > 0 and window.size.y > 0:
		return Vector2(window.size)
	return super._get_editor_available_size()


func _ready() -> void:
	super._ready()
	call_deferred("_install_workspace_usability")


func _install_workspace_usability() -> void:
	var main_layout := get_node_or_null("MarginContainer/MainLayout") as HSplitContainer
	_content_split = get_node_or_null("MarginContainer/MainLayout/ContentSplit") as HSplitContainer
	var sidebar := find_child("Sidebar", true, false) as VBoxContainer
	_record_panel = get_node_or_null("MarginContainer/MainLayout/ContentSplit/RecordPanel") as Control
	var form_panel := get_node_or_null("MarginContainer/MainLayout/ContentSplit/FormPanel") as VBoxContainer
	var form_scroll := get_node_or_null("MarginContainer/MainLayout/ContentSplit/FormPanel/FormScroll") as ScrollContainer

	if main_layout != null:
		main_layout.split_offset = DEFAULT_SIDEBAR_WIDTH
	if sidebar != null:
		sidebar.custom_minimum_size = Vector2(145.0, 0.0)
		sidebar.add_theme_constant_override("separation", 4)
		for button_value in sidebar_buttons.values():
			if button_value is Button:
				(button_value as Button).custom_minimum_size = Vector2(0.0, 31.0)
		_wrap_sidebar_in_scroll(sidebar)
	if _content_split != null:
		_content_split.split_offset = DEFAULT_RECORD_WIDTH
	if _record_panel != null:
		_record_panel.custom_minimum_size = Vector2(230.0, 0.0)
	if form_panel != null:
		form_panel.custom_minimum_size = Vector2(480.0, 0.0)
		_install_workspace_toolbar(form_panel)
	if form_scroll != null:
		form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		form_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		form_scroll.follow_focus = true
	if form_container != null:
		form_container.custom_minimum_size = Vector2(FORM_SCROLL_MINIMUM_WIDTH, 0.0)
		form_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		form_container.add_theme_constant_override("separation", 6)

	_fit_root_to_viewport()


func _wrap_sidebar_in_scroll(sidebar: VBoxContainer) -> void:
	if sidebar == null or sidebar.get_parent() == null:
		return
	if sidebar.get_parent() is ScrollContainer:
		_sidebar_scroll = sidebar.get_parent() as ScrollContainer
		return
	var parent := sidebar.get_parent()
	var original_index := sidebar.get_index()
	parent.remove_child(sidebar)
	_sidebar_scroll = ScrollContainer.new()
	_sidebar_scroll.name = "SidebarScroll"
	_sidebar_scroll.custom_minimum_size = Vector2(145.0, 0.0)
	_sidebar_scroll.size_flags_horizontal = Control.SIZE_FILL
	_sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_sidebar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_sidebar_scroll.follow_focus = true
	parent.add_child(_sidebar_scroll)
	parent.move_child(_sidebar_scroll, original_index)
	_sidebar_scroll.add_child(sidebar)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _install_workspace_toolbar(form_panel: VBoxContainer) -> void:
	if form_panel.get_node_or_null("WorkspaceToolbar") != null:
		return

	var toolbar := HBoxContainer.new()
	toolbar.name = "WorkspaceToolbar"
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_theme_constant_override("separation", 6)
	form_panel.add_child(toolbar)
	form_panel.move_child(toolbar, 0)

	_record_toggle_button = Button.new()
	_record_toggle_button.name = "RecordPanelToggle"
	_record_toggle_button.text = "Hide Record List"
	_record_toggle_button.tooltip_text = "Give the form the full editor width, or restore the record browser."
	_record_toggle_button.pressed.connect(_toggle_record_panel)
	toolbar.add_child(_record_toggle_button)

	var reset_button := Button.new()
	reset_button.name = "ResetWorkspaceLayout"
	reset_button.text = "Reset Columns"
	reset_button.tooltip_text = "Restore the default sidebar, record list and form widths."
	reset_button.pressed.connect(_reset_workspace_layout)
	toolbar.add_child(reset_button)

	_maximize_button = Button.new()
	_maximize_button.name = "EditorMaximizeToggle"
	_maximize_button.text = "Maximize Editor"
	_maximize_button.tooltip_text = "Toggle only the Content Editor window between maximized and movable."
	_maximize_button.pressed.connect(_toggle_editor_maximize)
	toolbar.add_child(_maximize_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var close_button := Button.new()
	close_button.name = "CloseLiveEditor"
	close_button.text = "Close"
	close_button.tooltip_text = "Close the live Content Editor without closing the game."
	close_button.pressed.connect(_request_close_editor)
	toolbar.add_child(close_button)


func _toggle_record_panel() -> void:
	if _record_panel == null or not is_instance_valid(_record_panel):
		return
	_record_panel.visible = not _record_panel.visible
	if _record_toggle_button != null:
		_record_toggle_button.text = "Hide Record List" if _record_panel.visible else "Show Record List"
	if _record_panel.visible and _content_split != null:
		_content_split.split_offset = DEFAULT_RECORD_WIDTH


func _reset_workspace_layout() -> void:
	var main_layout := get_node_or_null("MarginContainer/MainLayout") as HSplitContainer
	if main_layout != null:
		main_layout.split_offset = DEFAULT_SIDEBAR_WIDTH
	if _record_panel != null:
		_record_panel.visible = true
	if _record_toggle_button != null:
		_record_toggle_button.text = "Hide Record List"
	if _content_split != null:
		_content_split.split_offset = DEFAULT_RECORD_WIDTH
	if _sidebar_scroll != null and is_instance_valid(_sidebar_scroll):
		_sidebar_scroll.scroll_horizontal = 0
		_sidebar_scroll.scroll_vertical = 0
	var form_scroll := get_node_or_null("MarginContainer/MainLayout/ContentSplit/FormPanel/FormScroll") as ScrollContainer
	if form_scroll != null:
		form_scroll.scroll_horizontal = 0
		form_scroll.scroll_vertical = 0


func _toggle_editor_maximize() -> void:
	var window := get_window()
	if window == null:
		return
	if window.mode == Window.MODE_MAXIMIZED:
		window.mode = Window.MODE_WINDOWED
		if _maximize_button != null:
			_maximize_button.text = "Maximize Editor"
	else:
		window.mode = Window.MODE_MAXIMIZED
		if _maximize_button != null:
			_maximize_button.text = "Restore Editor"


func _request_close_editor() -> void:
	var window := get_window()
	if window == null:
		return
	var connections := window.get_signal_connection_list("close_requested")
	window.emit_signal("close_requested")
	if connections.is_empty():
		if window == get_tree().root:
			get_tree().quit()
		else:
			window.queue_free()
