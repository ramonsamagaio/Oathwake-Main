extends SceneTree

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const HUD_STATUS_SCENE := preload("res://scenes/ui/HUDStatusUI.tscn")
const BUTTERFLY_MONSTER_SCENE := preload("res://scenes/enemies/ButterflyMonster.tscn")
const BUTTERFLY_PET_SCENE := preload("res://scenes/pets/ButterflyPet.tscn")
const DAY_NIGHT_SCRIPT := preload("res://scripts/world/DayNightCycle.gd")
const PARTICLE_RUNTIME := preload("res://scripts/effects/MonsterParticleRuntime.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_player_light_stamina_hud_and_parry()
	await _validate_particle_modes_scale_and_pet_runtime()
	_validate_content_editor_field_contract()
	if failures.is_empty():
		print("PLAYER_LIGHT_STAMINA_PARTICLE_AUDIO_VALIDATION_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("PLAYER_LIGHT_STAMINA_PARTICLE_AUDIO_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_player_light_stamina_hud_and_parry() -> void:
	var test_root: Node2D = Node2D.new()
	test_root.name = "PlayerLightStaminaRuntimeValidation"
	root.add_child(test_root)

	var cycle: Node = DAY_NIGHT_SCRIPT.new() as Node
	cycle.name = "ValidationNightCycle"
	test_root.add_child(cycle)
	cycle.call("set_night")
	cycle.set_process(false)

	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null:
		failures.append("Player scene could not be instantiated.")
		test_root.queue_free()
		await process_frame
		return
	test_root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)

	var hud: Control = HUD_STATUS_SCENE.instantiate() as Control
	test_root.add_child(hud)
	await process_frame
	await process_frame

	if player.has_method("_sync_player_environment_halo_to_world"):
		player.call("_sync_player_environment_halo_to_world")
	var night_light: Node2D = player.get_node_or_null("NightLight") as Node2D
	if night_light != null and night_light.has_method("set_day_night_strength"):
		night_light.call("set_day_night_strength", 1.0)
	await process_frame
	var texture_glow: Sprite2D = null
	var point_light: PointLight2D = null
	if night_light != null:
		texture_glow = night_light.get_node_or_null("TextureGlow") as Sprite2D
		point_light = night_light.get_node_or_null("PointLight2D") as PointLight2D
	if night_light == null:
		failures.append("Player has no NightLight node.")
	else:
		if not bool(night_light.get("visual_enabled")):
			failures.append("Visible player ground light is disabled in runtime configuration.")
		if texture_glow == null or not texture_glow.visible or texture_glow.modulate.a <= 0.001:
			failures.append("Visible player ground-light texture did not render at full night.")
		if point_light == null or not point_light.enabled or point_light.energy <= 0.001:
			failures.append("Player PointLight2D did not activate at full night.")

	if not player.has_method("get_dash_stamina_cost") or not is_equal_approx(float(player.call("get_dash_stamina_cost")), 10.0):
		failures.append("Dash stamina cost is not 10.")
	if not player.has_method("get_stamina_regeneration_delay_seconds") or float(player.call("get_stamina_regeneration_delay_seconds")) <= 0.0:
		failures.append("Stamina has no post-dash regeneration delay.")

	player.call("_set_stamina", 100.0, true)
	for dash_index: int in range(10):
		_release_dash_state(player)
		player.call("_start_dash", Vector2.RIGHT)
		var expected: float = 100.0 - float(dash_index + 1) * 10.0
		if not is_equal_approx(float(player.call("get_current_stamina")), expected):
			failures.append("Dash %d left %.2f stamina instead of %.2f." % [dash_index + 1, float(player.call("get_current_stamina")), expected])
	await process_frame
	if hud == null or not hud.has_method("get_displayed_stamina_ratio"):
		failures.append("HUD does not expose its bound stamina ratio.")
	elif float(hud.call("get_displayed_stamina_ratio")) > 0.01:
		failures.append("HUD stamina bar did not empty after ten dashes.")

	_release_dash_state(player)
	player.call("_start_dash", Vector2.RIGHT)
	if int(player.get("action_state")) != 0:
		failures.append("Player entered dash state with empty stamina.")
	if not bool(player.get_meta("last_dash_rejected_for_stamina", false)):
		failures.append("Empty-stamina dash was not rejected by the stamina gate.")

	player.call("_set_stamina", 50.0, true)
	player.set("action_state", 0)
	var delay: float = float(player.call("get_stamina_regeneration_delay_seconds"))
	player.set("stamina_regeneration_delay_left", delay)
	player.call("_regenerate_stamina", delay * 0.75)
	if not is_equal_approx(float(player.call("get_current_stamina")), 50.0):
		failures.append("Stamina regenerated before the configured delay ended.")
	player.call("_regenerate_stamina", delay * 0.25 + 0.5)
	var expected_regen: float = minf(
		50.0 + float(player.call("get_stamina_regeneration_per_second")) * 0.5,
		float(player.call("get_max_stamina"))
	)
	if not is_equal_approx(float(player.call("get_current_stamina")), expected_regen):
		failures.append("Stamina regeneration rate after the delay is incorrect.")

	var sfx_manager: Node = root.get_node_or_null("SFXManager")
	if sfx_manager == null or not sfx_manager.has_method("has_profile") or not bool(sfx_manager.call("has_profile", "player_parry")):
		failures.append("player_parry sound event is missing from SFXManager.")
	else:
		var attacker: CharacterBody2D = BUTTERFLY_MONSTER_SCENE.instantiate() as CharacterBody2D
		if attacker == null:
			failures.append("Parry validation attacker could not be instantiated.")
		else:
			attacker.set("monster_id", "butterfly_blue")
			test_root.add_child(attacker)
			await process_frame
			player.call("_perform_parry", attacker)
			await process_frame
			if not bool(player.get_meta("last_parry_sfx_requested", false)):
				failures.append("Successful parry did not request its sound profile.")
			if not bool(player.get_meta("last_parry_sfx_played", false)):
				failures.append("Parry placeholder audio stream could not be played.")

	test_root.queue_free()
	await process_frame


func _validate_particle_modes_scale_and_pet_runtime() -> void:
	var host: Node2D = Node2D.new()
	host.name = "ParticleRuntimeValidationHost"
	root.add_child(host)
	var trail_data: Dictionary = {
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
	PARTICLE_RUNTIME.apply(host, trail_data)
	var particles: CPUParticles2D = host.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null:
		failures.append("Trail runtime did not create ContentParticles.")
	else:
		if particles.local_coords:
			failures.append("Trail particles remain attached to the moving actor.")
		if particles.initial_velocity_max > 3.1:
			failures.append("Trail particles move farther than the requested few pixels.")
		if particles.color_ramp == null:
			failures.append("Trail particles have no fade-out ramp.")
		else:
			var colors: PackedColorArray = particles.color_ramp.colors
			if colors.is_empty():
				failures.append("Trail particle fade-out ramp is empty.")
			else:
				var last_color: Color = colors[colors.size() - 1]
				if last_color.a > 0.01:
					failures.append("Trail particle fade-out ramp does not end transparent.")
		if not is_equal_approx(float(particles.get_meta("content_particle_visual_scale_ratio", -1.0)), 0.5):
			failures.append("Particle size did not inherit reduced butterfly visual scale.")
		if particles.scale_amount_max > 0.41:
			failures.append("Particles remain oversized after reducing the butterfly to half scale.")

	var attached_data: Dictionary = trail_data.duplicate(true)
	var attached_config: Dictionary = attached_data["particles"] as Dictionary
	attached_config["mode"] = "attached"
	PARTICLE_RUNTIME.apply(host, attached_data)
	particles = host.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null or not particles.local_coords:
		failures.append("Attached particle mode does not follow its actor.")

	var pet_owner: CharacterBody2D = CharacterBody2D.new()
	pet_owner.add_to_group("player")
	root.add_child(pet_owner)
	var pet: Node2D = BUTTERFLY_PET_SCENE.instantiate() as Node2D
	if pet == null:
		failures.append("Butterfly Pet scene could not be instantiated.")
	else:
		root.add_child(pet)
		var pet_data: Dictionary = trail_data.duplicate(true)
		pet_data["sprite_path"] = "res://assets/sprites/pets/Butterflies/Blue.png"
		pet_data["frame_width"] = 16
		pet_data["frame_height"] = 16
		pet_data["frames"] = 5
		pet_data["fps"] = 10.0
		pet_data["pet_id"] = "validation_butterfly"
		pet_data["pet_pickup_radius"] = 100.0
		pet.call("setup", pet_owner, pet_data)
		pet.set_process(false)
		await process_frame
		var pet_particles: CPUParticles2D = pet.get_node_or_null("ContentParticles") as CPUParticles2D
		if pet_particles == null or str(pet.get_meta("pet_particle_mode", "")) != "trail":
			failures.append("Butterfly Pet runtime did not apply its optional trail particle configuration.")

	host.queue_free()
	if pet != null:
		pet.queue_free()
	pet_owner.queue_free()
	await process_frame


func _validate_content_editor_field_contract() -> void:
	var editor_text: String = FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPetSaveDashSideSuite.gd")
	for token: String in [
		"runtime_monster_particles_mode",
		"runtime_monster_particles_size_multiplier",
		"runtime_monster_particles_scale_with_visual",
		"pet_particles_enabled",
		"pet_particles_mode",
		"pet_particles_size_multiplier",
		"pet_particles_scale_with_visual",
		"runtime_player_stamina_regeneration_delay_seconds",
	]:
		if not editor_text.contains(token):
			failures.append("Content Editor is missing control contract %s." % token)
	var sfx_text: String = FileAccess.get_file_as_string("res://data/sfx_profiles.json")
	if not sfx_text.contains("\"player_parry\""):
		failures.append("Content Editor audio data does not contain player_parry.")


func _release_dash_state(player: Node) -> void:
	player.set("action_state", 0)
	player.set("dash_cooldown_left", 0.0)
	player.set("dash_time_left", 0.0)
	player.set("dash_buffered", false)
