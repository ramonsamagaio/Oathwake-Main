extends SceneTree

const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const INVENTORY_UI_SCENE := preload("res://scenes/ui/InventoryUI.tscn")
const LOCOMOTION_SCRIPT := preload("res://scripts/enemies/MonsterLocomotion.gd")
const HAZARD_SCRIPT := preload("res://scripts/systems/EnvironmentalHazard.gd")
const CONDITION_SCRIPT := preload("res://scripts/systems/ElementalConditionController.gd")
const COMBAT_CALCULATOR_SCRIPT := preload("res://scripts/systems/CombatCalculator.gd")

const OBSOLETE_CHARACTER_FOLDERS := [
	"Run Top Down",
	"Run Top Down V2",
	"Run Top Down V3",
	"Run Top Down V3 REVIEW",
	"Run Top Down V4",
	"Run Top Down V5",
	"Run Top Down V6",
	"Run Top Down V7",
]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_validate_deleted_character_folders()
	_validate_elemental_contracts()
	await _validate_built_campfire()
	await _validate_condition_runtime()
	await _validate_hazard_aware_locomotion()
	await _validate_inventory_details()
	if failures.is_empty():
		print("ELEMENTAL_CAMPFIRE_INVENTORY_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("ELEMENTAL_CAMPFIRE_INVENTORY_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_deleted_character_folders() -> void:
	var root_path := "res://assets/sprites/characters/2D-Pixel-Art-Character-Template"
	for folder_name in OBSOLETE_CHARACTER_FOLDERS:
		if DirAccess.open("%s/%s" % [root_path, folder_name]) != null:
			failures.append("Obsolete character folder still exists: %s" % folder_name)


func _validate_elemental_contracts() -> void:
	if not CONDITION_SCRIPT.CONDITION_PROFILES.has("burning"):
		failures.append("Burning condition profile is missing")
	if not CONDITION_SCRIPT.CONDITION_PROFILES.has("poisoned"):
		failures.append("Poisoned condition profile is missing")
	var calculator = COMBAT_CALCULATOR_SCRIPT.new()
	var result: Dictionary = calculator.calculate_damage(
		{"base_stats": {"dex": 999, "luk": 0}, "base_combat": {"base_attack": 10.0}},
		{"base_stats": {"agi": 0}, "base_combat": {"base_defense": 0.0, "base_magic_defense": 0.0}},
		{"combat": {"attack_power": 4.0, "damage_type": "fire", "condition": "burning", "condition_duration": 4.0}}
	)
	if str(result.get("damage_type", "")) != "fire":
		failures.append("CombatCalculator did not preserve elemental damage type")
	if str(result.get("condition", "")) != "burning":
		failures.append("CombatCalculator did not preserve condition payload")


func _validate_built_campfire() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null:
		failures.append("ContentDB autoload is unavailable")
		return
	var campfire := BUILDING_SCENE.instantiate()
	campfire.set("building_id", "campfire")
	root.add_child(campfire)
	await process_frame
	await process_frame
	var collision := campfire.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.disabled or collision.shape == null:
		failures.append("Built campfire has no blocking collision")
	else:
		var rectangle := collision.shape as RectangleShape2D
		if rectangle == null or rectangle.size.x < 20.0 or rectangle.size.y < 12.0:
			failures.append("Built campfire collision is too small")
	var ember := campfire.get_node_or_null("EmberEmitter")
	if ember == null or not ember.visible or not ember.is_processing():
		failures.append("Built campfire ember/spark emitter is inactive")
	var hazard := campfire.get_node_or_null("ElementalHazard")
	if hazard == null or not hazard.is_in_group("environmental_hazard"):
		failures.append("Built campfire has no registered elemental hazard")
	elif str(hazard.get("condition_id")) != "burning":
		failures.append("Built campfire hazard does not apply burning")
	var glow := campfire.get_node_or_null("ContentGlow")
	if glow == null or not glow.visible:
		failures.append("Built campfire glow/flicker is inactive")
	campfire.queue_free()
	await process_frame


func _validate_condition_runtime() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	var initial_health := int(player.get("health"))
	if not bool(player.call("apply_condition", "burning", 1.2, 1.0, null)):
		failures.append("Player rejected the burning condition")
	elif not bool(player.call("has_condition", "burning")):
		failures.append("Player did not retain the burning condition")
	await create_timer(0.9).timeout
	if int(player.get("health")) >= initial_health:
		failures.append("Burning did not deal periodic elemental damage")
	player.call("apply_condition", "poisoned", 2.0, 1.0, null)
	if not bool(player.call("has_condition", "poisoned")):
		failures.append("Player rejected the poisoned condition")
	player.call("clear_all_conditions")
	player.queue_free()
	await process_frame


func _validate_hazard_aware_locomotion() -> void:
	var owner := CharacterBody2D.new()
	owner.add_to_group("enemy")
	owner.global_position = Vector2.ZERO
	root.add_child(owner)
	var target := CharacterBody2D.new()
	target.add_to_group("player")
	target.global_position = Vector2(120.0, 0.0)
	root.add_child(target)
	var hazard := HAZARD_SCRIPT.new()
	hazard.global_position = Vector2(42.0, 0.0)
	root.add_child(hazard)
	hazard.call("configure", {
		"radius": 20.0,
		"avoidance_radius": 54.0,
		"hazard_cost": 1.0,
		"affects_groups": ["enemy"],
	})
	var locomotion = LOCOMOTION_SCRIPT.new()
	owner.add_child(locomotion)
	locomotion.call("configure", {}, "walk", "4dir", {"move_speed": 45.0}, 45.0)
	await physics_frame
	var movement: Dictionary = locomotion.call("update", 0.1, owner, target)
	var velocity: Vector2 = movement.get("velocity", Vector2.ZERO)
	if velocity.length() <= 0.01:
		failures.append("Monster locomotion stopped instead of steering around a hazard")
	elif velocity.normalized().dot(Vector2.RIGHT) > 0.98:
		failures.append("Monster locomotion still heads directly through a damaging hazard")
	hazard.queue_free()
	target.queue_free()
	owner.queue_free()
	await process_frame


func _validate_inventory_details() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null:
		return
	var inventory_ui := INVENTORY_UI_SCENE.instantiate()
	root.add_child(inventory_ui)
	await process_frame
	var details := inventory_ui.get_node_or_null("WindowPanel/TooltipText") as RichTextLabel
	if details == null:
		details = inventory_ui.find_child("TooltipText", true, false) as RichTextLabel
	if details == null or not details.bbcode_enabled:
		failures.append("Inventory right panel is not a BBCode RichTextLabel")
	var item_data: Dictionary = content_db.get_item("stone_sword")
	var text := str(inventory_ui.call(
		"_build_item_details_bbcode",
		"stone_sword",
		1,
		"weapon",
		item_data,
		{"refinement_level": 3, "current_durability": 131}
	))
	for token in ["[b]Stone Sword[/b]", "+3", "[b]Attack:[/b]", ">19<", "[b]Refinement:[/b]", "[b]Rarity:[/b]"]:
		if not text.contains(token):
			failures.append("Inventory refined detail is missing token: %s" % token)
	inventory_ui.queue_free()
	await process_frame
