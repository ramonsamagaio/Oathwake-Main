extends Node2D

const RigRuntime := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd")

const SCREEN_SIZE := Vector2(1600.0, 900.0)
const WALK_SPEED := 150.0
const RUN_SPEED := 240.0
const CATEGORY_ORDER := ["ALL", "DEFAULT", "COMBAT", "PUZZLE", "OTHER", "CUTSCENE"]

const QUICK_ANIMATIONS := {
	KEY_SPACE: {"name": "idleJump1", "label": "Jump"},
	KEY_H: {"name": "damage", "label": "Hurt"},
	KEY_K: {"name": "dead", "label": "Death"},
	KEY_G: {"name": "guard", "label": "Guard", "sticky": true},
	KEY_P: {"name": "guardParry", "label": "Parry"},
	KEY_X: {"name": "respawn", "label": "Respawn"},
	KEY_C: {"name": "castPoint", "label": "Cast / Ability"},
	KEY_1: {"name": "atkSwordN1", "label": "Sword 1"},
	KEY_2: {"name": "atkSwordN2", "label": "Sword 2"},
	KEY_3: {"name": "atkSwordNFinisher", "label": "Sword Finisher"},
	KEY_4: {"name": "atkSwordTripleSlash", "label": "Sword Skill 1 / Triple Slash"},
	KEY_5: {"name": "atkSwordCrossStrike", "label": "Sword Skill 2 / Cross Strike"},
	KEY_6: {"name": "atkHammer1fast", "label": "2H Hammer 1"},
	KEY_7: {"name": "atkHammer2", "label": "2H Hammer 2"},
	KEY_8: {"name": "atkHammer3", "label": "2H Hammer 3"},
	KEY_9: {"name": "atkSpear1", "label": "Spear 1"},
	KEY_0: {"name": "atkTonfa1-punch", "label": "Tonfa 1"},
}

var player: CharacterBody2D
var rig
var status_label: Label
var browser_label: Label
var hotkey_label: Label
var _debug_enabled := false

var _catalog: Array[Dictionary] = []
var _browser_entries: Array[Dictionary] = []
var _browser_category_index := 0
var _browser_index := 0

var _manual_active := false
var _manual_sticky := false
var _manual_elapsed := 0.0
var _manual_timeout := 0.0
var _auto_showcase := false


func _ready() -> void:
	_build_world()
	_build_player()
	_catalog = rig.get_animation_catalog()
	_refresh_browser_entries()
	_build_ui()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _manual_active:
		player.velocity = Vector2.ZERO
		_manual_elapsed += delta
		if _auto_showcase:
			if _manual_elapsed >= _manual_timeout:
				_step_browser(1)
				_play_selected_browser_animation(true)
		elif not _manual_sticky and (rig.is_current_animation_finished() or _manual_elapsed >= _manual_timeout):
			_stop_manual_animation()
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
		rig.set_facing_from_vector(input_dir)
		rig.set_animation("run" if running else "walk")
	else:
		player.velocity = Vector2.ZERO
		rig.set_animation("idle")
	_update_status()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_F1:
		_debug_enabled = not _debug_enabled
		rig.set_debug_enabled(_debug_enabled)
		_update_status()
		return

	if event.keycode == KEY_ESCAPE:
		_auto_showcase = false
		_stop_manual_animation()
		return

	if event.keycode == KEY_TAB:
		_cycle_browser_category()
		return

	if event.keycode == KEY_PAGEUP:
		_step_browser(-1)
		return

	if event.keycode == KEY_PAGEDOWN:
		_step_browser(1)
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_auto_showcase = false
		_play_selected_browser_animation(false)
		return

	if event.keycode == KEY_F2:
		_auto_showcase = not _auto_showcase
		if _auto_showcase:
			_play_selected_browser_animation(true)
		else:
			_stop_manual_animation()
		_update_browser_label()
		return

	if QUICK_ANIMATIONS.has(event.keycode):
		var quick: Dictionary = QUICK_ANIMATIONS[event.keycode]
		_auto_showcase = false
		_play_manual_animation(
			String(quick.get("name", "idle")),
			bool(quick.get("sticky", false))
		)


func _play_manual_animation(animation_name: String, sticky: bool = false, auto_preview: bool = false) -> void:
	if not rig.has_animation(animation_name):
		push_warning("AlabasterMechanicLab: animation not loaded: %s" % animation_name)
		return
	rig.set_animation(animation_name)
	_manual_active = true
	_manual_sticky = sticky and not auto_preview
	_manual_elapsed = 0.0
	var source_duration: float = rig.get_animation_duration_seconds(animation_name)
	if auto_preview:
		_manual_timeout = clampf(source_duration, 0.65, 2.6)
	elif _manual_sticky:
		_manual_timeout = INF
	else:
		_manual_timeout = maxf(source_duration + 0.06, 0.25)
	_update_status()


func _stop_manual_animation() -> void:
	_manual_active = false
	_manual_sticky = false
	_manual_elapsed = 0.0
	_manual_timeout = 0.0
	rig.set_animation("idle")
	_update_status()


func _play_selected_browser_animation(auto_preview: bool) -> void:
	if _browser_entries.is_empty():
		return
	var entry: Dictionary = _browser_entries[_browser_index]
	_play_manual_animation(String(entry.get("name", "idle")), false, auto_preview)


func _cycle_browser_category() -> void:
	_browser_category_index = (_browser_category_index + 1) % CATEGORY_ORDER.size()
	_browser_index = 0
	_refresh_browser_entries()
	_update_browser_label()


func _step_browser(delta: int) -> void:
	if _browser_entries.is_empty():
		return
	_browser_index = (_browser_index + delta + _browser_entries.size()) % _browser_entries.size()
	_update_browser_label()


func _refresh_browser_entries() -> void:
	_browser_entries.clear()
	var filter_name: String = CATEGORY_ORDER[_browser_category_index]
	for entry in _catalog:
		if filter_name == "ALL" or String(entry.get("category", "DEFAULT")) == filter_name:
			_browser_entries.append(entry)
	if _browser_index >= _browser_entries.size():
		_browser_index = 0


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
	add_child(title)

	var help := Label.new()
	help.position = Vector2(28.0, 58.0)
	help.text = "WASD mover • SHIFT correr • F1 skeleton • TAB categoria • PgUp/PgDn navegar • ENTER tocar • F2 autoplay • ESC idle"
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(0.82, 0.86, 0.94)
	add_child(help)

	status_label = Label.new()
	status_label.position = Vector2(28.0, 88.0)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.modulate = Color(0.60, 0.94, 0.80)
	add_child(status_label)

	browser_label = Label.new()
	browser_label.position = Vector2(28.0, 118.0)
	browser_label.add_theme_font_size_override("font_size", 15)
	browser_label.modulate = Color(0.93, 0.82, 0.48)
	add_child(browser_label)

	hotkey_label = Label.new()
	hotkey_label.position = Vector2(28.0, SCREEN_SIZE.y - 108.0)
	hotkey_label.text = "SPACE jump • H hurt • K death • G guard • P parry • X respawn • C cast\n1 sword1 • 2 sword2 • 3 finisher • 4 triple slash • 5 cross strike • 6/7/8 2H hammer • 9 spear • 0 tonfa"
	hotkey_label.add_theme_font_size_override("font_size", 14)
	hotkey_label.modulate = Color(0.78, 0.82, 0.90)
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
	status_label.text = "anim=%s   anims=%d bank=%s   facing16=%02d   angle=%6.1f°   nodes=%d   pieces=%d   manual=%s   debug=%s" % [
		String(summary.get("animation", "")),
		int(summary.get("animation_count", 0)),
		"OK" if bool(summary.get("animation_bank_loaded", false)) else "FALLBACK",
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
