extends Node

const EXPECTED_PET_IDS := [
	"butterfly_pet_trinket",
	"grey_butterfly_trinket",
	"pink_butterfly_trinket",
	"red_butterfly_trinket",
	"white_butterfly_trinket",
	"yellow_butterfly_trinket",
]
const PET_SECTION := "pets"
const BUTTERFLY_MONSTER_SCENE := preload("res://scenes/enemies/ButterflyMonster.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const DAY_NIGHT_SCRIPT := preload("res://scripts/world/DayNightCycle.gd")
const EXPECTED_BUTTERFLY_TEXTURE := "res://assets/sprites/pets/Butterflies/Blue.png"


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	call_deferred("_run_contract_probe")


func _run_contract_probe() -> void:
	await get_tree().process_frame
	var editor := get_parent()
	var launcher := get_tree().get_first_node_in_group("runtime_content_editor_launcher")
	if editor == null or not is_instance_valid(editor) or launcher == null:
		queue_free()
		return

	_validate_pet_section(editor)
	_validate_monster_and_player_fields(editor)
	_validate_inventory_contract()
	_validate_parry_contract()
	await _validate_butterfly_reload_and_facing_contract()
	await _validate_player_dash_stamina_and_light_contract()
	editor.call("_select_section", "items", true)
	queue_free()


func _validate_pet_section(editor: Node) -> void:
	if not editor.has_method("_select_section") or not editor.has_method("_load_record"):
		push_error("Pet contract probe: Content Editor navigation API is unavailable.")
		return
	editor.call("_select_section", PET_SECTION, true)
	var data_store: Variant = editor.get("data_store")
	if data_store == null or not data_store.has_method("get_records"):
		push_error("Pet contract probe: Content Editor data store is unavailable.")
		return
	var records_value: Variant = data_store.call("get_records", PET_SECTION)
	var records: Array = records_value as Array if records_value is Array else []
	if records.size() != EXPECTED_PET_IDS.size():
		push_error("Pet contract probe: expected %d pet records, found %d." % [EXPECTED_PET_IDS.size(), records.size()])
	for pet_id in EXPECTED_PET_IDS:
		if not bool(data_store.call("has_record", PET_SECTION, pet_id)):
			push_error("Pet contract probe: missing pet record %s." % pet_id)

	editor.call("_load_record", "butterfly_pet_trinket")
	var controls_value: Variant = editor.get("field_controls")
	var controls: Dictionary = controls_value as Dictionary if controls_value is Dictionary else {}
	for field_name in ["pet_function", "pet_visual_scale", "pet_pickup_radius"]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing pet field %s." % field_name)
	var current_file_label := editor.get("current_file_label") as Label
	if current_file_label == null or not current_file_label.text.contains("data/pet_items.json"):
		push_error("Pet contract probe: Pets section is not routed to data/pet_items.json.")
	if editor.has_method("_update_action_buttons"):
		editor.call("_update_action_buttons")
	var save_button := editor.get("save_button") as Button
	if save_button == null or save_button.disabled:
		push_error("Pet contract probe: Save must be enabled for a selected Pet record.")


func _validate_monster_and_player_fields(editor: Node) -> void:
	editor.call("_select_section", "monsters", true)
	editor.call("_load_record", "butterfly_blue")
	var controls_value: Variant = editor.get("field_controls")
	var controls: Dictionary = controls_value as Dictionary if controls_value is Dictionary else {}
	for field_name in [
		"runtime_monster_visual_scale",
		"runtime_monster_particles_enabled",
		"runtime_monster_particles_amount",
		"runtime_monster_particles_color",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing monster tuning field %s." % field_name)
	var particle_enabled := controls.get("runtime_monster_particles_enabled") as CheckBox
	if particle_enabled == null or not particle_enabled.button_pressed:
		push_error("Pet contract probe: butterfly particle emission should open enabled by default.")
	if not bool(editor.get_meta("butterfly_particle_default_synced", false)):
		push_error("Pet contract probe: butterfly particle UI default was not synchronized with runtime.")

	editor.call("_select_section", "player_tuning", true)
	controls_value = editor.get("field_controls")
	controls = controls_value as Dictionary if controls_value is Dictionary else {}
	for field_name in [
		"runtime_player_parry_stun_seconds",
		"runtime_player_dash_smoke_scale",
		"runtime_player_stamina_regeneration_per_second",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing Player Tuning field %s." % field_name)
	if controls.has("runtime_player_dash_smoke_facing"):
		push_error("Pet contract probe: dash smoke facing must be derived from movement, not exposed as an absolute setting.")


func _validate_inventory_contract() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var inventory_ui := current_scene.find_child("InventoryUI", true, false)
	# The editor is also opened by isolated scene-validation jobs where the real
	# Game root is intentionally absent. Inventory is validated only in gameplay.
	if inventory_ui == null:
		return
	if int(inventory_ui.get("slot_count")) != 60:
		push_error("Pet contract probe: InventoryUI should expose 60 slots.")
	var inventory_value: Variant = current_scene.get("inventory")
	if inventory_value != null and inventory_value.has_method("get_slot_count"):
		if int(inventory_value.call("get_slot_count")) != 60:
			push_error("Pet contract probe: backing Inventory should expose 60 slots.")


func _validate_parry_contract() -> void:
	var parry_scene := load("res://scenes/effects/ParryEffect.tscn") as PackedScene
	if parry_scene == null:
		push_error("Pet contract probe: ParryEffect scene could not be loaded.")
		return
	var effect := parry_scene.instantiate()
	if effect == null or not effect.has_method("get_sheet_row_index"):
		push_error("Pet contract probe: ParryEffect row contract is unavailable.")
		return
	if int(effect.call("get_sheet_row_index")) != 4:
		push_error("Pet contract probe: ParryEffect must use zero-based row index 4 (fifth row).")
	effect.free()


func _validate_butterfly_reload_and_facing_contract() -> void:
	var butterfly := BUTTERFLY_MONSTER_SCENE.instantiate() as CharacterBody2D
	if butterfly == null:
		push_error("Pet contract probe: ButterflyMonster scene could not be instantiated.")
		return
	butterfly.set("monster_id", "butterfly_blue")
	get_tree().root.add_child(butterfly)
	await get_tree().process_frame
	if butterfly.has_method("_refresh_runtime_monster_content"):
		butterfly.call("_refresh_runtime_monster_content")
	await get_tree().process_frame
	var sprite := butterfly.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or not sprite.visible:
		push_error("Pet contract probe: butterfly primary sprite became hidden after live content reload.")
	elif sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("idle"):
		push_error("Pet contract probe: butterfly lost its authored idle animation after live content reload.")
	else:
		var frame_texture := sprite.sprite_frames.get_frame_texture("idle", 0)
		var source_path := _texture_source_path(frame_texture)
		if source_path != EXPECTED_BUTTERFLY_TEXTURE:
			push_error("Pet contract probe: butterfly loaded %s instead of its own sprite sheet." % source_path)

	var animator := butterfly.get_node_or_null("MonsterAnimator")
	if animator == null or not animator.has_method("play_state"):
		push_error("Pet contract probe: butterfly animator is unavailable.")
	else:
		animator.call("play_state", "walk", "left")
		await get_tree().process_frame
		if sprite != null and sprite.flip_h:
			push_error("Pet contract probe: authored butterfly front should remain unflipped while moving left.")
		animator.call("play_state", "walk", "right")
		await get_tree().process_frame
		if sprite != null and not sprite.flip_h:
			push_error("Pet contract probe: butterfly should mirror its authored left-facing front while moving right.")

	butterfly.queue_free()
	await get_tree().process_frame


func _validate_player_dash_stamina_and_light_contract() -> void:
	var test_root := Node2D.new()
	test_root.name = "PlayerRuntimeContractRoot"
	get_tree().root.add_child(test_root)

	var cycle := Node.new()
	cycle.name = "PlayerRuntimeContractNightCycle"
	cycle.set_script(DAY_NIGHT_SCRIPT)
	test_root.add_child(cycle)
	cycle.call("set_night")
	cycle.set_process(false)

	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null:
		push_error("Pet contract probe: Player scene could not be instantiated.")
		test_root.queue_free()
		return
	test_root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	await get_tree().process_frame

	if not player.has_method("get_dash_stamina_cost") or not is_equal_approx(float(player.call("get_dash_stamina_cost")), 10.0):
		push_error("Pet contract probe: every dash must cost exactly 10 stamina.")
	if not player.has_method("get_stamina_regeneration_per_second") or float(player.call("get_stamina_regeneration_per_second")) <= 0.0:
		push_error("Pet contract probe: stamina regeneration must be positive and tunable.")

	_prepare_player_for_dash(player, 100.0)
	player.call("_start_dash", Vector2.RIGHT)
	if not is_equal_approx(float(player.call("get_current_stamina")), 90.0):
		push_error("Pet contract probe: right dash did not spend exactly 10 stamina.")
	if _last_authored_dash_smoke_facing(test_root) != "right":
		push_error("Pet contract probe: right dash smoke did not face right relative to movement.")
	await _clear_authored_dash_smoke(test_root)

	_prepare_player_for_dash(player, 100.0)
	player.call("_start_dash", Vector2.LEFT)
	if _last_authored_dash_smoke_facing(test_root) != "left":
		push_error("Pet contract probe: left dash smoke did not face left relative to movement.")
	await _clear_authored_dash_smoke(test_root)

	_prepare_player_for_dash(player, 100.0)
	player.call("_start_dash", Vector2.UP)
	if _authored_dash_smoke_count(test_root) != 0:
		push_error("Pet contract probe: vertical dash must not use the lateral dash-smoke sheet.")

	player.set("action_state", 0)
	player.set("current_stamina", 50.0)
	player.call("_regenerate_stamina", 0.5)
	var expected_regen := 50.0 + float(player.call("get_stamina_regeneration_per_second")) * 0.5
	if not is_equal_approx(float(player.call("get_current_stamina")), minf(expected_regen, float(player.call("get_max_stamina")))):
		push_error("Pet contract probe: stamina did not regenerate at the configured per-second rate.")

	player.set("current_stamina", 5.0)
	player.set("action_state", 0)
	player.call("_start_dash", Vector2.RIGHT)
	if int(player.get("action_state")) != 0 or not is_equal_approx(float(player.call("get_current_stamina")), 5.0):
		push_error("Pet contract probe: player dashed without the required 10 stamina.")

	if player.has_method("_sync_player_environment_halo_to_world"):
		player.call("_sync_player_environment_halo_to_world")
	await get_tree().process_frame
	var night_light := player.get_node_or_null("NightLight") as Node2D
	var point_light := night_light.get_node_or_null("PointLight2D") as PointLight2D if night_light != null else null
	if point_light == null or not point_light.enabled or point_light.energy <= 0.001:
		push_error("Pet contract probe: player night light did not activate under an active night cycle.")

	test_root.queue_free()
	await get_tree().process_frame


func _prepare_player_for_dash(player: Node, stamina_value: float) -> void:
	player.set("action_state", 0)
	player.set("dash_cooldown_left", 0.0)
	player.set("dash_time_left", 0.0)
	player.set("dash_buffered", false)
	player.set("current_stamina", stamina_value)


func _authored_dash_smoke_count(root: Node) -> int:
	var count := 0
	for child in root.get_children():
		if child != null and child.has_meta("dash_smoke_single_emission"):
			count += 1
	return count


func _last_authored_dash_smoke_facing(root: Node) -> String:
	for child in root.get_children():
		if child != null and child.has_meta("dash_smoke_single_emission"):
			return str(child.get_meta("dash_smoke_relative_facing", ""))
	return ""


func _clear_authored_dash_smoke(root: Node) -> void:
	for child in root.get_children():
		if child != null and child.has_meta("dash_smoke_single_emission"):
			child.queue_free()
	await get_tree().process_frame


func _texture_source_path(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var atlas := (texture as AtlasTexture).atlas
		return atlas.resource_path if atlas != null else ""
	return texture.resource_path if texture != null else ""
