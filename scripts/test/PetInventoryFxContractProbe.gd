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
const HUD_STATUS_SCENE := preload("res://scenes/ui/HUDStatusUI.tscn")
const DAY_NIGHT_SCRIPT := preload("res://scripts/world/DayNightCycle.gd")
const MONSTER_PARTICLE_RUNTIME := preload("res://scripts/effects/MonsterParticleRuntime.gd")
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
	_validate_sound_editor_contract(editor)
	_validate_inventory_contract()
	_validate_parry_contract()
	await _validate_butterfly_reload_facing_and_trail_contract()
	await _validate_particle_scale_and_modes_contract()
	await _validate_player_dash_stamina_hud_and_light_contract()
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
	var controls := _editor_controls(editor)
	for field_name in [
		"pet_function",
		"pet_visual_scale",
		"pet_pickup_radius",
		"pet_particles_enabled",
		"pet_particles_mode",
		"pet_particles_amount",
		"pet_particles_size_multiplier",
		"pet_particles_scale_with_visual",
		"pet_particles_fade_out",
	]:
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
	var controls := _editor_controls(editor)
	for field_name in [
		"runtime_monster_visual_scale",
		"runtime_monster_particles_enabled",
		"runtime_monster_particles_amount",
		"runtime_monster_particles_color",
		"runtime_monster_particles_mode",
		"runtime_monster_particles_size_multiplier",
		"runtime_monster_particles_scale_with_visual",
		"runtime_monster_particles_fade_out",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing monster tuning field %s." % field_name)
	var particle_enabled := controls.get("runtime_monster_particles_enabled") as CheckBox
	if particle_enabled == null or not particle_enabled.button_pressed:
		push_error("Pet contract probe: butterfly particle emission should open enabled by default.")
	if not bool(editor.get_meta("butterfly_particle_default_synced", false)):
		push_error("Pet contract probe: butterfly particle UI default was not synchronized with runtime.")

	editor.call("_select_section", "player_tuning", true)
	controls = _editor_controls(editor)
	for field_name in [
		"runtime_player_parry_stun_seconds",
		"runtime_player_dash_smoke_scale",
		"runtime_player_stamina_regeneration_per_second",
		"runtime_player_stamina_regeneration_delay_seconds",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing Player Tuning field %s." % field_name)
	if controls.has("runtime_player_dash_smoke_facing"):
		push_error("Pet contract probe: dash smoke facing must be derived from movement, not exposed as an absolute setting.")


func _validate_sound_editor_contract(editor: Node) -> void:
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager == null or not sfx_manager.has_method("has_profile") or not bool(sfx_manager.call("has_profile", "player_parry")):
		push_error("Pet contract probe: player_parry sound profile is missing from SFXManager.")
	if not editor.has_method("_select_integrated_section"):
		push_error("Pet contract probe: integrated Sound Effects section is unavailable.")
		return
	editor.call("_select_integrated_section", "__sound_effects")
	var record_list := editor.get("record_list") as ItemList
	if record_list == null:
		push_error("Pet contract probe: Sound Effects record list is unavailable.")
		return
	var found_parry := false
	for index in range(record_list.item_count):
		if str(record_list.get_item_metadata(index)) == "player_parry":
			found_parry = true
			break
	if not found_parry:
		push_error("Pet contract probe: player_parry is not exposed in Content Editor Sound Effects.")


func _validate_inventory_contract() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var inventory_ui := current_scene.find_child("InventoryUI", true, false)
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


func _validate_butterfly_reload_facing_and_trail_contract() -> void:
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

	var particles := butterfly.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null:
		push_error("Pet contract probe: butterfly did not create its default particle trail.")
	else:
		if particles.local_coords:
			push_error("Pet contract probe: butterfly trail particles still move with the butterfly instead of remaining in world space.")
		if str(particles.get_meta("content_particle_mode", "")) != "trail":
			push_error("Pet contract probe: butterfly default particle mode is not trail.")
		if particles.initial_velocity_max > 3.1:
			push_error("Pet contract probe: butterfly trail particles move more than the intended few pixels.")
		if particles.color_ramp == null or particles.color_ramp.colors.is_empty() or particles.color_ramp.colors[-1].a > 0.01:
			push_error("Pet contract probe: butterfly trail particles do not fade out.")

	butterfly.queue_free()
	await get_tree().process_frame


func _validate_particle_scale_and_modes_contract() -> void:
	var host := Node2D.new()
	host.name = "ParticleModeContractHost"
	get_tree().root.add_child(host)
	var trail_data := {
		"pet_family": "butterfly",
		"pet_color": "blue",
		"visual_scale": 1.0,
		"particles": {
			"enabled": true,
			"mode": "trail",
			"scale_with_visual": true,
			"size_multiplier": 1.0,
			"fade_out": true,
		},
	}
	MONSTER_PARTICLE_RUNTIME.apply(host, trail_data)
	var particles := host.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null:
		push_error("Pet contract probe: trail particle runtime did not create a particle node.")
	else:
		if particles.local_coords:
			push_error("Pet contract probe: trail mode did not use world-space particles.")
		if not is_equal_approx(float(particles.get_meta("content_particle_visual_scale_ratio", -1.0)), 0.5):
			push_error("Pet contract probe: particle size did not follow the reduced butterfly visual scale.")
		if particles.scale_amount_max > 0.41:
			push_error("Pet contract probe: reduced butterfly still has oversized particles.")

	var attached_data := trail_data.duplicate(true)
	(attached_data["particles"] as Dictionary)["mode"] = "attached"
	MONSTER_PARTICLE_RUNTIME.apply(host, attached_data)
	particles = host.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null or not particles.local_coords:
		push_error("Pet contract probe: attached mode does not remain bound to its actor.")
	host.queue_free()
	await get_tree().process_frame


func _validate_player_dash_stamina_hud_and_light_contract() -> void:
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
	var hud := HUD_STATUS_SCENE.instantiate() as Control
	test_root.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	if not player.has_method("get_dash_stamina_cost") or not is_equal_approx(float(player.call("get_dash_stamina_cost")), 10.0):
		push_error("Pet contract probe: every dash must cost exactly 10 stamina.")
	if not player.has_method("get_stamina_regeneration_per_second") or float(player.call("get_stamina_regeneration_per_second")) <= 0.0:
		push_error("Pet contract probe: stamina regeneration must be positive and tunable.")
	if not player.has_method("get_stamina_regeneration_delay_seconds") or float(player.call("get_stamina_regeneration_delay_seconds")) <= 0.0:
		push_error("Pet contract probe: repeated dash has no regeneration delay.")

	player.call("_set_stamina", 100.0, true)
	for dash_index in range(10):
		_release_player_dash_state(player)
		player.call("_start_dash", Vector2.RIGHT)
		var expected := 100.0 - float(dash_index + 1) * 10.0
		if not is_equal_approx(float(player.call("get_current_stamina")), expected):
			push_error("Pet contract probe: dash %d did not spend cumulative stamina correctly." % (dash_index + 1))
	await get_tree().process_frame
	if hud == null or not hud.has_method("get_displayed_stamina_ratio") or float(hud.call("get_displayed_stamina_ratio")) > 0.01:
		push_error("Pet contract probe: HUD stamina bar did not reach empty after ten dashes.")

	_release_player_dash_state(player)
	player.call("_start_dash", Vector2.RIGHT)
	if int(player.get("action_state")) != 0 or not is_equal_approx(float(player.call("get_current_stamina")), 0.0):
		push_error("Pet contract probe: player performed an eleventh dash with empty stamina.")

	player.call("_set_stamina", 50.0, true)
	player.set("action_state", 0)
	var delay := float(player.call("get_stamina_regeneration_delay_seconds"))
	player.set("stamina_regeneration_delay_left", delay)
	player.call("_regenerate_stamina", delay * 0.75)
	if not is_equal_approx(float(player.call("get_current_stamina")), 50.0):
		push_error("Pet contract probe: stamina regenerated before its post-dash delay ended.")
	player.call("_regenerate_stamina", delay * 0.25 + 0.5)
	var expected_regen := 50.0 + float(player.call("get_stamina_regeneration_per_second")) * 0.5
	if not is_equal_approx(float(player.call("get_current_stamina")), minf(expected_regen, float(player.call("get_max_stamina")))):
		push_error("Pet contract probe: stamina did not regenerate at the configured rate after the delay.")

	_release_player_dash_state(player)
	player.call("_set_stamina", 100.0, true)
	player.call("_start_dash", Vector2.UP)
	if _authored_dash_smoke_count(test_root) != 0:
		push_error("Pet contract probe: vertical dash must not use the lateral dash-smoke sheet.")

	if player.has_method("_sync_player_environment_halo_to_world"):
		player.call("_sync_player_environment_halo_to_world")
	await get_tree().process_frame
	var night_light := player.get_node_or_null("NightLight") as Node2D
	if night_light != null and night_light.has_method("set_day_night_strength"):
		night_light.call("set_day_night_strength", 1.0)
	await get_tree().process_frame
	var point_light := night_light.get_node_or_null("PointLight2D") as PointLight2D if night_light != null else null
	var texture_glow := night_light.get_node_or_null("TextureGlow") as Sprite2D if night_light != null else null
	if point_light == null or not point_light.enabled or point_light.energy <= 0.001:
		push_error("Pet contract probe: player PointLight2D did not activate under an active night cycle.")
	if texture_glow == null or not texture_glow.visible or texture_glow.modulate.a <= 0.001:
		push_error("Pet contract probe: player visible ground-light texture is absent at night.")

	test_root.queue_free()
	await get_tree().process_frame


func _release_player_dash_state(player: Node) -> void:
	player.set("action_state", 0)
	player.set("dash_cooldown_left", 0.0)
	player.set("dash_time_left", 0.0)
	player.set("dash_buffered", false)


func _authored_dash_smoke_count(root: Node) -> int:
	var count := 0
	for child in root.get_children():
		if child != null and child.has_meta("dash_smoke_single_emission"):
			count += 1
	return count


func _texture_source_path(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var atlas := (texture as AtlasTexture).atlas
		return atlas.resource_path if atlas != null else ""
	return texture.resource_path if texture != null else ""


func _editor_controls(editor: Node) -> Dictionary:
	var value: Variant = editor.get("field_controls")
	return value as Dictionary if value is Dictionary else {}
