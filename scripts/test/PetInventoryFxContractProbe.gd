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
const DASH_SMOKE_SCENE := preload("res://scenes/effects/SmokePuff.tscn")


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
	await _validate_butterfly_reload_contract()
	await _validate_dash_smoke_facing_contract()
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
		"runtime_player_dash_smoke_facing",
	]:
		if not controls.has(field_name):
			push_error("Pet contract probe: missing Player Tuning field %s." % field_name)


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


func _validate_butterfly_reload_contract() -> void:
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
	elif sprite.sprite_frames == null or sprite.sprite_frames.get_animation_names().is_empty():
		push_error("Pet contract probe: butterfly lost its animation frames after live content reload.")	
	butterfly.queue_free()
	await get_tree().process_frame


func _validate_dash_smoke_facing_contract() -> void:
	for facing_value in ["left", "right"]:
		var smoke := DASH_SMOKE_SCENE.instantiate() as Node2D
		if smoke == null:
			push_error("Pet contract probe: Dash Smoke scene could not be instantiated.")
			return
		smoke.set("auto_free_on_finish", false)
		smoke.set("facing", facing_value)
		get_tree().root.add_child(smoke)
		await get_tree().process_frame
		if not smoke.has_method("get_facing") or str(smoke.call("get_facing")) != facing_value:
			push_error("Pet contract probe: dash smoke did not preserve facing %s." % facing_value)
		var sprite := smoke.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		var expected_flip := facing_value == "left"
		if sprite == null or sprite.flip_h != expected_flip:
			push_error("Pet contract probe: dash smoke flip does not match facing %s." % facing_value)
		smoke.queue_free()
		await get_tree().process_frame
