extends "res://scripts/player/PlayerRuntimeTuningFxSuite.gd"
class_name PlayerBones

# Single gameplay entry point for bone-driven player rendering.
# The live Player scene talks only to this integration class, BonesSystem and
# BonesWeapons. Alabaster lab scripts remain low-level renderer/import tools.

const RigVisualController := preload("res://scripts/player/AlabasterPlayerVisualController.gd")
const BonesWeaponRuntime := preload("res://scripts/systems/bones/BonesWeapons.gd")
const RomesteadCompositePlayerShadowScript := preload("res://scripts/effects/RomesteadCompositePlayerShadow.gd")
const JUNO_WEAPON_TEST_ITEMS := [
	["Sword", "juno_sword"],
	["Hammer", "juno_hammer"],
	["Spear", "juno_spear"],
	["Tonfa", "juno_tonfa"],
	["Crossbow", "juno_crossbow"],
	["Chakram", "juno_chakram"],
	["Kama", "juno_kama"],
	["Bomb", "juno_bomb"],
]

var _rig_visual := RigVisualController.new()
var _weapon_visual := BonesWeaponRuntime.new()
var _bones_ground_offset := Vector2.ZERO
var _bones_weapon_visibility_mode := "attack_only"
var _last_bones_weapon_item_id := ""
var _debug_forced_weapon_item_id := ""
var _juno_weapon_test_layer: CanvasLayer
var _juno_weapon_test_panel: PanelContainer
var _romestead_player_shadow: Node2D


func _sync_character_id_from_player_tuning() -> void:
	# Player Tuning is the single authority for which character record is active.
	# Do not depend on an inherited scene default or stale in-memory character_id
	# when the Content Editor has just reloaded content.
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	var selected_character_id := str(tuning.get("character_id", character_id)).strip_edges()
	if selected_character_id.is_empty():
		return
	if content_db.has_method("has_character") and not content_db.has_character(selected_character_id):
		push_warning("PlayerBones ignored unknown player_tuning.character_id: %s" % selected_character_id)
		return
	character_id = selected_character_id
	set_meta("active_player_character_id", character_id)


func _setup_character_visual() -> void:
	_sync_character_id_from_player_tuning()
	super._setup_character_visual()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_character") or not content_db.has_character(character_id):
		return
	var character_data: Dictionary = content_db.get_character(character_id)
	_bones_ground_offset = _read_bones_ground_offset(character_data)
	var rig_position := _content_visual_offset + _bones_ground_offset
	if not _rig_visual.configure(self, character_data, rig_position, _content_visual_scale):
		return
	_weapon_visual.configure(_rig_visual.rig)
	_load_bones_weapon_tuning()
	_sync_bones_weapon(true)
	_rig_visual.prewarm_actions()
	_force_rig_visual()
	_publish_bones_ground_contract()
	_ensure_romestead_player_shadow()
	call_deferred("_ensure_juno_weapon_test_panel")
	call_deferred("_configure_rig_night_readability")
	call_deferred("_refresh_player_directional_shadow_source")
	call_deferred("_report_rig_player_ready")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _rig_visual.active:
		_sync_bones_weapon(false)
		_weapon_visual.set_attacking(action_state == ActionState.ATTACKING)
		_weapon_visual.update()
		if _romestead_player_shadow != null and _romestead_player_shadow.has_method("sync_projection"):
			_romestead_player_shadow.call("sync_projection")


func _apply_player_directional_shadow() -> void:
	if _rig_visual.active:
		_ensure_romestead_player_shadow()


func _refresh_player_directional_shadow_source() -> void:
	if _rig_visual.active:
		_ensure_romestead_player_shadow()


func _ensure_romestead_player_shadow() -> void:
	var old_shadow := get_node_or_null("GroundShadow")
	if old_shadow != null:
		old_shadow.queue_free()
	if not _rig_visual.active or _rig_visual.rig == null:
		return
	if _romestead_player_shadow == null or not is_instance_valid(_romestead_player_shadow):
		_romestead_player_shadow = RomesteadCompositePlayerShadowScript.new()
		add_child(_romestead_player_shadow)
	if _romestead_player_shadow.has_method("configure"):
		_romestead_player_shadow.call("configure", self, _rig_visual.rig)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not _rig_visual.active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_ensure_juno_weapon_test_panel()
		if _juno_weapon_test_panel != null:
			_juno_weapon_test_panel.visible = not _juno_weapon_test_panel.visible
		get_viewport().set_input_as_handled()


func _load_player_tuning() -> void:
	super._load_player_tuning()
	_sync_character_id_from_player_tuning()
	_load_bones_weapon_tuning()


func _load_bones_weapon_tuning() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	var mode := str(tuning.get("alabaster_weapon_visibility", "attack_only"))
	_bones_weapon_visibility_mode = "always_when_supported" if mode == "always_when_supported" else "attack_only"
	_weapon_visual.set_visibility_mode(_bones_weapon_visibility_mode)


func _sync_bones_weapon(force := false) -> void:
	if not _rig_visual.active:
		return
	var held_id := _get_current_held_item_id()
	if held_id.begins_with("juno_"):
		_debug_forced_weapon_item_id = ""
	var resolved_id := _debug_forced_weapon_item_id if not _debug_forced_weapon_item_id.is_empty() else held_id
	if not force and resolved_id == _last_bones_weapon_item_id:
		return
	_last_bones_weapon_item_id = resolved_id
	var item_record := {}
	var content_db := get_node_or_null("/root/ContentDB")
	if not resolved_id.is_empty() and content_db != null and content_db.has_method("has_item") and content_db.has_item(resolved_id):
		item_record = content_db.get_item(resolved_id)
	_weapon_visual.set_item(resolved_id, item_record)
	_weapon_visual.set_visibility_mode(_bones_weapon_visibility_mode)


func _ensure_juno_weapon_test_panel() -> void:
	if not _rig_visual.active:
		return
	if _juno_weapon_test_panel != null and is_instance_valid(_juno_weapon_test_panel):
		return
	_juno_weapon_test_layer = CanvasLayer.new()
	_juno_weapon_test_layer.name = "JunoWeaponTestLayer"
	_juno_weapon_test_layer.layer = 95
	add_child(_juno_weapon_test_layer)

	_juno_weapon_test_panel = PanelContainer.new()
	_juno_weapon_test_panel.name = "JunoWeaponTestPanel"
	_juno_weapon_test_panel.position = Vector2(18, 190)
	_juno_weapon_test_panel.custom_minimum_size = Vector2(255, 0)
	_juno_weapon_test_panel.visible = false
	_juno_weapon_test_layer.add_child(_juno_weapon_test_panel)

	var box := VBoxContainer.new()
	_juno_weapon_test_panel.add_child(box)
	var title := Label.new()
	title.text = "JUNO WEAPON TEST · F6"
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	var help := Label.new()
	help.text = "Give + Preview grants the real content item. Source weapon FIGs use the project's real player-melee/player-ranged atlases and follow the bone sockets."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(235, 0)
	box.add_child(help)
	for pair in JUNO_WEAPON_TEST_ITEMS:
		var label := str(pair[0])
		var test_item_id := str(pair[1])
		var button := Button.new()
		button.text = "Give + Preview  %s" % label
		button.pressed.connect(_debug_grant_and_preview_juno_weapon.bind(test_item_id))
		box.add_child(button)
	var clear := Button.new()
	clear.text = "Clear Forced Preview"
	clear.pressed.connect(_clear_debug_juno_weapon_preview)
	box.add_child(clear)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _juno_weapon_test_panel.visible = false)
	box.add_child(close)


func _debug_grant_and_preview_juno_weapon(test_item_id: String) -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(test_item_id):
		push_warning("Juno weapon test item is not present in ContentDB: %s" % test_item_id)
		return
	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method("add_item_to_inventory"):
		var leftover := int(main.call("add_item_to_inventory", test_item_id, 1, {"debug_juno_weapon": true}))
		if leftover > 0:
			push_warning("Inventory full; could not grant %s" % test_item_id)
		else:
			print("JUNO_WEAPON_GRANTED %s" % test_item_id)
	_debug_forced_weapon_item_id = test_item_id
	_last_bones_weapon_item_id = ""
	_sync_bones_weapon(true)


func _clear_debug_juno_weapon_preview() -> void:
	_debug_forced_weapon_item_id = ""
	_last_bones_weapon_item_id = ""
	_sync_bones_weapon(true)


func _report_rig_player_ready() -> void:
	if not _rig_visual.active:
		return
	var data := _rig_visual.summary()
	print("BONES_PLAYER_READY character=%s profile=%s animations=%s source=%s cache=%s" % [
		character_id,
		_rig_visual.profile_id,
		str(data.get("animation_count", "?")),
		str(data.get("animation_bank_source", "?")),
		str(_rig_visual.rig.call("get_animation_cache_summary") if _rig_visual.rig != null and _rig_visual.rig.has_method("get_animation_cache_summary") else {}),
	])


func _configure_rig_night_readability() -> void:
	if not _rig_visual.active:
		return
	_configure_player_night_readability()
	_rig_visual.set_material(null)


func _apply_player_visual_tuning() -> void:
	super._apply_player_visual_tuning()
	if _rig_visual.active and _rig_visual.rig != null and is_instance_valid(_rig_visual.rig):
		_refresh_bones_ground_offset()
		_rig_visual.rig.position = _content_visual_offset + _bones_ground_offset
		_rig_visual.rig.scale = Vector2.ONE * _content_visual_scale
		_publish_bones_ground_contract()
		_force_rig_visual()


func _force_rig_visual() -> void:
	if not _rig_visual.active:
		return
	if _rig_visual.rig != null:
		_rig_visual.rig.visible = true
	if animated_sprite != null:
		animated_sprite.visible = false
	if body_visual != null:
		body_visual.visible = false
	if wip_south_sprite != null:
		wip_south_sprite.visible = false


func _set_wip_visual_active(active: bool) -> void:
	if _rig_visual.active:
		super._set_wip_visual_active(false)
		_force_rig_visual()
		return
	super._set_wip_visual_active(active)


func _update_movement_animation(input_direction: Vector2) -> void:
	if not _rig_visual.active:
		super._update_movement_animation(input_direction)
		return
	_force_rig_visual()
	if _is_life_animation_locked() or is_blocking():
		return
	if action_state == ActionState.ATTACKING or action_state == ActionState.DASHING:
		return
	if input_direction != Vector2.ZERO:
		_update_last_direction(input_direction)
		_rig_visual.face(input_direction)
		_rig_visual.play("run" if is_running else "walk")
	else:
		_rig_visual.play("idle")


func _play_attack_animation() -> void:
	if not _rig_visual.active:
		super._play_attack_animation()
		return
	_force_rig_visual()
	_sync_bones_weapon(false)
	_rig_visual.face(_rig_visual.last_facing)
	_weapon_visual.set_attacking(true)
	var weapon_animation := _weapon_visual.get_attack_animation()
	if not weapon_animation.is_empty() and _rig_visual.has_animation(weapon_animation):
		# This should already be resident from BonesWeapons.set_item(). Calling it
		# again is a constant-time cache check and protects dynamically supplied items.
		_rig_visual.prewarm_animation(weapon_animation)
		var weapon_duration := _rig_visual.duration_for_animation(weapon_animation)
		var weapon_speed := 1.0
		if weapon_duration > 0.0:
			weapon_speed = clampf(weapon_duration / maxf(current_attack_cooldown, 0.05), 0.20, 8.0)
		_rig_visual.play_animation_name(weapon_animation, "attack", weapon_speed)
		return
	var native_duration := _rig_visual.duration_for("attack")
	var speed := 1.0
	if native_duration > 0.0:
		speed = clampf(native_duration / maxf(current_attack_cooldown, 0.05), 0.20, 8.0)
	_rig_visual.play("attack", speed)


func _finish_attack_cycle() -> void:
	super._finish_attack_cycle()
	_weapon_visual.set_attacking(false)
	if _rig_visual.active:
		_rig_visual.set_speed(1.0)
		_rig_visual.play("idle")
		_force_rig_visual()


func start_block() -> bool:
	var started := super.start_block()
	if started and _rig_visual.active:
		_force_rig_visual()
		_rig_visual.play("block")
	return started


func stop_block() -> void:
	var was_blocking := is_blocking()
	super.stop_block()
	if was_blocking and _rig_visual.active and not _is_life_animation_locked():
		_rig_visual.set_speed(1.0)
		_rig_visual.play("idle")
		_force_rig_visual()


func _start_dash(direction: Vector2) -> void:
	var was_dashing := action_state == ActionState.DASHING
	super._start_dash(direction)
	if not _rig_visual.active or was_dashing or action_state != ActionState.DASHING:
		return
	if dash_direction != Vector2.ZERO:
		_rig_visual.face(dash_direction)
	var native_duration := _rig_visual.duration_for("dash")
	var speed := 1.0
	if native_duration > 0.0:
		speed = clampf(native_duration / maxf(dash_duration, 0.05), 0.20, 8.0)
	_rig_visual.play("dash", speed)
	_force_rig_visual()


func _has_player_animation(animation_name: String) -> bool:
	if _rig_visual.active and (animation_name == "hurt" or animation_name == "death"):
		return _rig_visual.has_action(animation_name)
	return super._has_player_animation(animation_name)


func _play_life_animation(animation_name: String, fallback_duration: float) -> float:
	if not _rig_visual.active:
		return super._play_life_animation(animation_name, fallback_duration)
	if not _rig_visual.has_action(animation_name):
		return fallback_duration
	_rig_visual.set_speed(1.0)
	_rig_visual.play(animation_name)
	_force_rig_visual()
	var duration := _rig_visual.duration_for(animation_name)
	return maxf(duration, 0.05) if duration > 0.0 else fallback_duration


func _restore_idle_after_life_animation() -> void:
	if not _rig_visual.active:
		super._restore_idle_after_life_animation()
		return
	_rig_visual.set_speed(1.0)
	_rig_visual.play("idle")
	_force_rig_visual()


func _set_player_visual_alpha(alpha: float) -> void:
	super._set_player_visual_alpha(alpha)
	if _rig_visual.active:
		_rig_visual.set_alpha(alpha)


func refresh_alabaster_character_visual() -> void:
	_sync_character_id_from_player_tuning()
	_weapon_visual.dispose()
	if _rig_visual.active:
		_rig_visual.dispose()
	_last_bones_weapon_item_id = ""
	_debug_forced_weapon_item_id = ""
	_setup_character_visual()
	call_deferred("_refresh_player_directional_shadow_source")


func is_alabaster_player_visual_active() -> bool:
	return _rig_visual.active


func get_alabaster_player_rig() -> Node2D:
	return _rig_visual.rig if _rig_visual.active else null


func get_bones_ground_world_position() -> Vector2:
	# Ground VFX, projected light and the collision body share this contract.
	return global_position + Vector2(0.0, 12.0)


func _read_bones_ground_offset(character_data: Dictionary) -> Vector2:
	var value: Variant = character_data.get("bones_ground_offset", {})
	if value is Dictionary:
		var data := value as Dictionary
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	return Vector2.ZERO


func _refresh_bones_ground_offset() -> void:
	_bones_ground_offset = Vector2.ZERO
	if not _rig_visual.active:
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_character") or not content_db.has_character(character_id):
		return
	_bones_ground_offset = _read_bones_ground_offset(content_db.get_character(character_id))


func _publish_bones_ground_contract() -> void:
	set_meta("bones_ground_offset", _bones_ground_offset)
	set_meta("bones_visual_position", _content_visual_offset + _bones_ground_offset)
	set_meta("bones_ground_world_position", get_bones_ground_world_position())
