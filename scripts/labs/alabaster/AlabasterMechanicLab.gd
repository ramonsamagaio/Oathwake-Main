extends Node2D

const RigRuntime := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd")
const SharedActions := preload("res://scripts/labs/alabaster/AlabasterSharedActions.gd")

const SCREEN_SIZE := Vector2(1600.0, 900.0)
const WALK_SPEED := 150.0
const RUN_SPEED := 240.0
const CATEGORY_ORDER := ["ALL", "COMBAT", "DEFAULT", "PUZZLE", "OTHER", "CUTSCENE"]

# Commands are handled in _input(), before Controls can consume Enter/Space/
# number-row keys. keycode and physical_keycode are both accepted so the lab is
# independent from keyboard layout and from which UI control was clicked last.
const COMMAND_KEYS := [
	KEY_F1, KEY_ESCAPE, KEY_TAB, KEY_PAGEUP, KEY_PAGEDOWN, KEY_ENTER, KEY_KP_ENTER, KEY_F2,
	KEY_SPACE, KEY_H, KEY_K, KEY_G, KEY_P, KEY_X, KEY_C,
	KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9,
]

var player: CharacterBody2D
var rig
var status_label: Label
var browser_label: Label
var hotkey_label: Label
var _debug_enabled := false
var _manual_active := false
var _auto_showcase := false
var _manual_elapsed := 0.0
var _manual_duration := 0.0
var _catalog: Array[Dictionary] = []
var _browser_entries: Array[Dictionary] = []
var _browser_category_index := 0
var _browser_index := 0
var _key_latch: Dictionary = {}
var _left_mouse_latched := false


func _ready() -> void:
	_build_world()
	_build_player()
	_build_ui()
	_refresh_catalog()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var command_key := _resolve_command_key(key_event)
		if command_key != KEY_NONE:
			_handle_command_key(command_key)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and not _pointer_over_gui():
			_auto_showcase = false
			_play_semantic_action("attack")
			get_viewport().set_input_as_handled()


func _resolve_command_key(event: InputEventKey) -> Key:
	var logical := event.keycode
	if logical in COMMAND_KEYS:
		return logical
	var physical := event.physical_keycode
	if physical in COMMAND_KEYS:
		return physical
	return KEY_NONE


func _physics_process(delta: float) -> void:
	if _manual_active:
		_manual_elapsed += delta
		if _manual_duration > 0.0 and _manual_elapsed >= _manual_duration:
			if _auto_showcase:
				_navigate_browser(1)
				_play_browser_animation()
			else:
				_stop_manual_animation()
		player.velocity = Vector2.ZERO
		_update_status()
		return

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var running := Input.is_key_pressed(KEY_SHIFT)
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		player.velocity = input_dir * (RUN_SPEED if running else WALK_SPEED)
		player.move_and_slide()
		player.position.x = clampf(player.position.x, 72.0, SCREEN_SIZE.x - 72.0)
		player.position.y = clampf(player.position.y, 92.0, SCREEN_SIZE.y - 72.0)
		if rig != null and rig.has_method("set_facing_from_vector"):
			rig.call("set_facing_from_vector", input_dir)
		_set_locomotion_action("run" if running else "walk")
	else:
		player.velocity = Vector2.ZERO
		_set_locomotion_action("idle")
	_update_status()


func reset_command_latches() -> void:
	# Kept as a public compatibility hook for profile switching. Commands now use
	# _input(), but clearing these values also prevents stale state if an older lab
	# layer still polls them.
	_key_latch.clear()
	_left_mouse_latched = false


func _set_locomotion_action(action_name: String) -> void:
	if rig == null:
		return
	var animation_name := SharedActions.resolve_action_animation(rig, action_name)
	if not animation_name.is_empty() and rig.has_method("set_animation"):
		rig.call("set_animation", animation_name)
		return
	if action_name == "idle" and rig.has_method("set_rest_pose"):
		rig.call("set_rest_pose")


func _handle_command_key(key: Key) -> void:
	if key == KEY_F1:
		_debug_enabled = not _debug_enabled
		if rig != null and rig.has_method("set_debug_enabled"):
			rig.call("set_debug_enabled", _debug_enabled)
		_update_status()
		return
	if key == KEY_ESCAPE:
		_auto_showcase = false
		_stop_manual_animation()
		return
	if key == KEY_TAB:
		_browser_category_index = (_browser_category_index + 1) % CATEGORY_ORDER.size()
		_rebuild_browser_entries()
		return
	if key == KEY_PAGEUP:
		_navigate_browser(-1)
		return
	if key == KEY_PAGEDOWN:
		_navigate_browser(1)
		return
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		_play_browser_animation()
		return
	if key == KEY_F2:
		_auto_showcase = not _auto_showcase
		if _auto_showcase:
			_play_browser_animation()
		else:
			_stop_manual_animation()
		_update_browser_label()
		return

	var action_name := str(SharedActions.QUICK_ACTIONS.get(key, ""))
	if not action_name.is_empty():
		_auto_showcase = false
		_play_semantic_action(action_name)


func _play_semantic_action(action_name: String) -> void:
	var animation_name := SharedActions.resolve_action_animation(rig, action_name)
	if animation_name.is_empty():
		var source := "UNKNOWN"
		if rig != null and rig.has_method("get_runtime_summary"):
			var summary_value: Variant = rig.call("get_runtime_summary")
			if summary_value is Dictionary:
				source = str((summary_value as Dictionary).get("animation_bank_source", "UNKNOWN"))
		push_warning("AlabasterMechanicLab: no animation resolved for action '%s'. catalog=%d source=%s" % [action_name, _catalog.size(), source])
		return
	print("ALABASTER_LAB_ACTION action=%s animation=%s" % [action_name, animation_name])
	_play_manual_animation(animation_name)


func _pointer_over_gui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _refresh_catalog() -> void:
	_catalog.clear()
	if rig != null and rig.has_method("get_animation_catalog"):
		var catalog_value: Variant = rig.call("get_animation_catalog")
		if catalog_value is Array:
			for entry_value in catalog_value as Array:
				if entry_value is Dictionary:
					_catalog.append((entry_value as Dictionary).duplicate(true))
	_rebuild_browser_entries()


func _rebuild_browser_entries() -> void:
	_browser_entries.clear()
	var filter_name: String = CATEGORY_ORDER[_browser_category_index]
	for entry_variant in _catalog:
		var entry: Dictionary = entry_variant
		if filter_name == "ALL" or String(entry.get("category", "DEFAULT")) == filter_name:
			_browser_entries.append(entry)
	_browser_index = clampi(_browser_index, 0, maxi(_browser_entries.size() - 1, 0))
	_update_browser_label()


func _navigate_browser(step: int) -> void:
	if _browser_entries.is_empty():
		return
	_browser_index = posmod(_browser_index + step, _browser_entries.size())
	_update_browser_label()


func _play_browser_animation() -> void:
	if _browser_entries.is_empty():
		return
	var entry: Dictionary = _browser_entries[_browser_index]
	_play_manual_animation(String(entry.get("name", "")))


func _play_manual_animation(animation_name: String) -> void:
	if animation_name.is_empty() or rig == null or not rig.has_method("has_animation") or not bool(rig.call("has_animation", animation_name)):
		push_warning("AlabasterMechanicLab: animation not available on active shared rig: %s" % animation_name)
		return
	_manual_active = true
	_manual_elapsed = 0.0
	_manual_duration = float(rig.call("get_animation_duration_seconds", animation_name)) if rig.has_method("get_animation_duration_seconds") else 0.0
	rig.call("set_animation", animation_name)
	_update_status()


func _stop_manual_animation() -> void:
	_manual_active = false
	_manual_elapsed = 0.0
	_manual_duration = 0.0
	_set_locomotion_action("idle")
	_update_status()


func _build_world() -> void:
	var floor := ColorRect.new()
	floor.name = "Floor"
	floor.position = Vector2.ZERO
	floor.size = SCREEN_SIZE
	floor.color = Color("#11141b")
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.z_index = -1000
	add_child(floor)


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "AlabasterPlayer"
	player.position = SCREEN_SIZE * 0.5 + Vector2(0.0, 80.0)
	add_child(player)

	rig = RigRuntime.new()
	rig.name = "JunoRig"
	rig.scale = Vector2(2.5, 2.5)
	player.add_child(rig)


func _build_ui() -> void:
	var title := Label.new()
	title.position = Vector2(28.0, 24.0)
	title.text = "ALABASTER MECHANIC LAB • FULL ANIMATION PLAYGROUND"
	title.add_theme_font_size_override("font_size", 24)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var help := Label.new()
	help.position = Vector2(28.0, 58.0)
	help.text = "WASD mover • SHIFT correr • LMB ataque • F1 skeleton • TAB categoria • PgUp/PgDn navegar • ENTER tocar • F2 autoplay • ESC idle"
	help.add_theme_font_size_override("font_size", 16)
	help.modulate = Color(0.82, 0.86, 0.94)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)

	status_label = Label.new()
	status_label.position = Vector2(28.0, 86.0)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.modulate = Color(0.60, 0.94, 0.80)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)

	browser_label = Label.new()
	browser_label.position = Vector2(28.0, 118.0)
	browser_label.add_theme_font_size_override("font_size", 15)
	browser_label.modulate = Color(0.93, 0.82, 0.48)
	browser_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(browser_label)

	hotkey_label = Label.new()
	hotkey_label.position = Vector2(28.0, SCREEN_SIZE.y - 108.0)
	hotkey_label.text = "SPACE jump • H hurt • K death • G guard • P parry • X respawn • C cast\n1 sword1 • 2 sword2 • 3 finisher • 4 triple slash • 5 cross strike • 6/7/8 2H hammer • 9 spear • 0 tonfa"
	hotkey_label.add_theme_font_size_override("font_size", 14)
	hotkey_label.modulate = Color(0.78, 0.82, 0.90)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotkey_label)

	_update_browser_label()
	_update_status()


func _update_browser_label() -> void:
	if browser_label == null:
		return
	var filter_name: String = CATEGORY_ORDER[_browser_category_index]
	if _browser_entries.is_empty():
		browser_label.text = "browser [%s] vazio • catálogo total=%d" % [filter_name, _catalog.size()]
		return
	var entry: Dictionary = _browser_entries[_browser_index]
	browser_label.text = "browser [%s] %d/%d  •  %s  •  source %.2fs  •  %s  •  autoplay=%s" % [
		filter_name,
		_browser_index + 1,
		_browser_entries.size(),
		String(entry.get("name", "")),
		float(entry.get("duration", 0.0)),
		"LOOP" if bool(entry.get("repeat", false)) else "ONE-SHOT",
		"ON" if _auto_showcase else "OFF",
	]


func _update_status() -> void:
	if rig == null or status_label == null:
		return
	var summary = rig.get_runtime_summary()
	status_label.text = "anim=%s   anims=%d source=%s   facing16=%02d   angle=%6.1f°   nodes=%d   pieces=%d   manual=%s   debug=%s" % [
		String(summary.get("animation", "")),
		int(summary.get("animation_count", 0)),
		String(summary.get("animation_bank_source", "FALLBACK")),
		int(summary.get("facing_index_16", 0)),
		float(summary.get("facing_degrees", 0.0)),
		int(summary.get("node_count", 0)),
		int(summary.get("sprite_piece_count", 0)),
		"LOCK" if _manual_active else "FREE",
		"ON" if _debug_enabled else "OFF",
	]
	_update_browser_label()


func _draw() -> void:
	for x in range(0, int(SCREEN_SIZE.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_SIZE.y), Color(0.18, 0.21, 0.28, 0.55), 1.0)
	for y in range(0, int(SCREEN_SIZE.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(SCREEN_SIZE.x, y), Color(0.18, 0.21, 0.28, 0.55), 1.0)
	draw_line(Vector2(0, SCREEN_SIZE.y * 0.5), Vector2(SCREEN_SIZE.x, SCREEN_SIZE.y * 0.5), Color(0.28, 0.33, 0.42, 0.65), 1.0)
	draw_line(Vector2(SCREEN_SIZE.x * 0.5, 0), Vector2(SCREEN_SIZE.x * 0.5, SCREEN_SIZE.y), Color(0.28, 0.33, 0.42, 0.65), 1.0)
