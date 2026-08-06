extends Node

const EXPECTED_PET_IDS: Array[String] = [
	"butterfly_pet_trinket",
	"grey_butterfly_trinket",
	"pink_butterfly_trinket",
	"red_butterfly_trinket",
	"white_butterfly_trinket",
	"yellow_butterfly_trinket",
]
const PET_SECTION := "pets"
const BUTTERFLY_MONSTER_SCENE := preload("res://scenes/enemies/ButterflyMonster.tscn")
const EXPECTED_BUTTERFLY_TEXTURE := "res://assets/sprites/pets/Butterflies/Blue.png"


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	call_deferred("_run_contract_probe")


func _run_contract_probe() -> void:
	await get_tree().process_frame
	var editor: Node = get_parent()
	var launcher: Node = get_tree().get_first_node_in_group("runtime_content_editor_launcher")
	if editor == null or not is_instance_valid(editor) or launcher == null:
		queue_free()
		return

	_validate_pet_editor_contract(editor)
	_validate_monster_editor_contract(editor)
	_validate_player_tuning_contract(editor)
	_validate_sound_contract(editor)
	_validate_inventory_contract()
	_validate_parry_visual_contract()
	await _validate_butterfly_runtime_contract()
	if editor.has_method("_select_section"):
		editor.call("_select_section", "items", true)
	queue_free()


func _validate_pet_editor_contract(editor: Node) -> void:
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
	for pet_id: String in EXPECTED_PET_IDS:
		if not bool(data_store.call("has_record", PET_SECTION, pet_id)):
			push_error("Pet contract probe: missing pet record %s." % pet_id)

	editor.call("_load_record", "butterfly_pet_trinket")
	var controls: Dictionary = _editor_controls(editor)
	for field_name: String in [
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
			push_error("Pet contract probe: missing Pet control %s." % field_name)
	var current_file_label: Label = editor.get("current_file_label") as Label
	if current_file_label == null or not current_file_label.text.contains("data/pet_items.json"):
		push_error("Pet contract probe: Pets section is not routed to data/pet_items.json.")
	if editor.has_method("_update_action_buttons"):
		editor.call("_update_action_buttons")
	var save_button: Button = editor.get("save_button") as Button
	if save_button == null or save_button.disabled:
		push_error("Pet contract probe: Save must be enabled for a selected Pet record.")


func _validate_monster_editor_contract(editor: Node) -> void:
	editor.call("_select_section", "monsters", true)
	editor.call("_load_record", "butterfly_blue")
	var controls: Dictionary = _editor_controls(editor)
	for field_name: String in [
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
			push_error("Pet contract probe: missing Monster control %s." % field_name)
	var particle_enabled: CheckBox = controls.get("runtime_monster_particles_enabled") as CheckBox
	if particle_enabled == null or not particle_enabled.button_pressed:
		push_error("Pet contract probe: butterfly particles should open enabled by default.")


func _validate_player_tuning_contract(editor: Node) -> void:
	editor.call("_select_section", "player_tuning", true)
	var controls: Dictionary = _editor_controls(editor)
	for field_name: String in [
		"runtime_player_parry_stun_seconds",
		"runtime_player_dash_smoke_scale",
		"runtime_player_stamina_regeneration_per_second",
		"runtime_player_stamina_regeneration_delay_seconds",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing Player Tuning control %s." % field_name)
	if controls.has("runtime_player_dash_smoke_facing"):
		push_error("Pet contract probe: absolute dash-smoke direction must not be exposed.")


func _validate_sound_contract(editor: Node) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SFXManager")
	if sfx_manager == null:
		push_error("Pet contract probe: SFXManager is unavailable.")
		return
	if not sfx_manager.has_method("has_profile") or not bool(sfx_manager.call("has_profile", "player_parry")):
		push_error("Pet contract probe: player_parry sound profile is missing.")
	if not editor.has_method("_select_integrated_section"):
		push_error("Pet contract probe: integrated Sound Effects section is unavailable.")
		return
	editor.call("_select_integrated_section", "__sound_effects")
	var record_list: ItemList = editor.get("record_list") as ItemList
	if record_list == null:
		push_error("Pet contract probe: Sound Effects record list is unavailable.")
		return
	var found_parry: bool = false
	for index: int in range(record_list.item_count):
		if str(record_list.get_item_metadata(index)) == "player_parry":
			found_parry = true
			break
	if not found_parry:
		push_error("Pet contract probe: player_parry is not listed in Content Editor Sound Effects.")


func _validate_inventory_contract() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	var inventory_ui: Node = current_scene.find_child("InventoryUI", true, false)
	if inventory_ui == null:
		return
	if int(inventory_ui.get("slot_count")) != 60:
		push_error("Pet contract probe: InventoryUI should expose 60 slots.")


func _validate_parry_visual_contract() -> void:
	var parry_scene: PackedScene = load("res://scenes/effects/ParryEffect.tscn") as PackedScene
	if parry_scene == null:
		push_error("Pet contract probe: ParryEffect scene could not be loaded.")
		return
	var effect: Node = parry_scene.instantiate()
	if effect == null or not effect.has_method("get_sheet_row_index"):
		push_error("Pet contract probe: ParryEffect row contract is unavailable.")
		return
	if int(effect.call("get_sheet_row_index")) != 4:
		push_error("Pet contract probe: ParryEffect must use zero-based row index 4.")
	effect.free()


func _validate_butterfly_runtime_contract() -> void:
	var butterfly: CharacterBody2D = BUTTERFLY_MONSTER_SCENE.instantiate() as CharacterBody2D
	if butterfly == null:
		push_error("Pet contract probe: ButterflyMonster scene could not be instantiated.")
		return
	butterfly.set("monster_id", "butterfly_blue")
	get_tree().root.add_child(butterfly)
	await get_tree().process_frame
	if butterfly.has_method("_refresh_runtime_monster_content"):
		butterfly.call("_refresh_runtime_monster_content")
	await get_tree().process_frame

	var sprite: AnimatedSprite2D = butterfly.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or not sprite.visible:
		push_error("Pet contract probe: butterfly primary sprite is hidden after reload.")
	elif sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("idle"):
		push_error("Pet contract probe: butterfly lost its authored animation after reload.")
	else:
		var frame_texture: Texture2D = sprite.sprite_frames.get_frame_texture("idle", 0)
		var source_path: String = _texture_source_path(frame_texture)
		if source_path != EXPECTED_BUTTERFLY_TEXTURE:
			push_error("Pet contract probe: butterfly loaded %s instead of Blue.png." % source_path)

	var animator: Node = butterfly.get_node_or_null("MonsterAnimator")
	if animator != null and animator.has_method("play_state"):
		animator.call("play_state", "walk", "left")
		await get_tree().process_frame
		if sprite != null and sprite.flip_h:
			push_error("Pet contract probe: left-moving butterfly should use its authored orientation.")
		animator.call("play_state", "walk", "right")
		await get_tree().process_frame
		if sprite != null and not sprite.flip_h:
			push_error("Pet contract probe: right-moving butterfly should mirror horizontally.")

	var particles: CPUParticles2D = butterfly.get_node_or_null("ContentParticles") as CPUParticles2D
	if particles == null:
		push_error("Pet contract probe: butterfly did not create its default trail.")
	else:
		if particles.local_coords:
			push_error("Pet contract probe: trail particles remain attached to the butterfly.")
		if str(particles.get_meta("content_particle_mode", "")) != "trail":
			push_error("Pet contract probe: butterfly default particle mode is not trail.")
		if particles.initial_velocity_max > 3.1:
			push_error("Pet contract probe: trail particles move more than a few pixels.")
		if particles.color_ramp == null:
			push_error("Pet contract probe: trail particles have no fade ramp.")
		else:
			var ramp_colors: PackedColorArray = particles.color_ramp.colors
			if ramp_colors.is_empty():
				push_error("Pet contract probe: trail fade ramp is empty.")
			else:
				var last_color: Color = ramp_colors[ramp_colors.size() - 1]
				if last_color.a > 0.01:
					push_error("Pet contract probe: trail particles do not end transparent.")

	butterfly.queue_free()
	await get_tree().process_frame


func _texture_source_path(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var atlas: Texture2D = (texture as AtlasTexture).atlas
		return atlas.resource_path if atlas != null else ""
	return texture.resource_path if texture != null else ""


func _editor_controls(editor: Node) -> Dictionary:
	var value: Variant = editor.get("field_controls")
	return value as Dictionary if value is Dictionary else {}
