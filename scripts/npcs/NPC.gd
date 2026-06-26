extends CharacterBody2D

const NPCDataScript = preload("res://scripts/npcs/NPCData.gd")

@export var npc_id: String = "villager_basic"
@export var npc_instance_id: String = "npc_001"
@export var interaction_range: float = 64.0

var npc_data = NPCDataScript.new()
var display_name := "NPC"
var max_health := 50
var health := 50
var move_speed := 35.0
var role := "worker"
var preferred_workstation := ""
var production := []
var needs_house := true
var recruited := false
var assigned_bed_id := ""
var has_house := false
var production_timers := {}


func _ready() -> void:
	add_to_group("npc")
	add_to_group("npcs")
	collision_layer = 0
	collision_mask = 0
	_load_npc_data()


func _process(delta: float) -> void:
	_update_production(delta)


func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO


func try_interact_with_player(player_node: Node2D) -> bool:
	if player_node == null:
		return false

	if global_position.distance_to(player_node.global_position) > interaction_range:
		return false

	interact()
	return true


func interact() -> void:
	if not recruited:
		print("Press R to recruit")
		return

	print("NPC: %s" % display_name)
	print("Role: %s" % role)


func try_recruit_with_player(player_node: Node2D) -> bool:
	if player_node == null:
		return false

	if global_position.distance_to(player_node.global_position) > interaction_range:
		return false

	if recruited:
		print("%s is already recruited" % display_name)
		return true

	var settlement_manager = get_tree().get_first_node_in_group("settlement_manager")
	if settlement_manager != null and settlement_manager.has_method("recruit_npc"):
		settlement_manager.recruit_npc(self)
	else:
		set_recruited(true, true)

	return true


func set_recruited(value: bool, announce := false) -> void:
	recruited = value
	if recruited and announce:
		print("%s recruited" % display_name)


func is_recruited() -> bool:
	return recruited


func assign_bed(bed_id: String) -> void:
	assigned_bed_id = bed_id
	has_house = not assigned_bed_id.is_empty()


func clear_house_assignment() -> void:
	assigned_bed_id = ""
	has_house = false


func get_assigned_bed_id() -> String:
	return assigned_bed_id


func has_valid_house() -> bool:
	return has_house


func get_npc_instance_id() -> String:
	return npc_instance_id


func get_save_data() -> Dictionary:
	return {
		"npc_instance_id": npc_instance_id,
		"npc_id": npc_id,
		"recruited": recruited,
		"assigned_bed_id": assigned_bed_id,
		"has_house": has_house,
		"production_timers": production_timers.duplicate(true),
	}


func load_save_data(save_data) -> void:
	if not save_data is Dictionary:
		set_recruited(false)
		clear_house_assignment()
		production_timers.clear()
		return

	set_recruited(bool(save_data.get("recruited", false)))
	assigned_bed_id = str(save_data.get("assigned_bed_id", ""))
	has_house = bool(save_data.get("has_house", false)) and not assigned_bed_id.is_empty()

	var loaded_timers = save_data.get("production_timers", {})
	production_timers = loaded_timers.duplicate(true) if loaded_timers is Dictionary else {}


func _load_npc_data() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	var error: String = npc_data.load_from_content_db(npc_id, content_db)
	if not error.is_empty():
		push_error(error)
		return

	display_name = npc_data.display_name
	max_health = npc_data.max_health
	health = max_health
	move_speed = npc_data.move_speed
	role = npc_data.role
	preferred_workstation = npc_data.preferred_workstation
	production = npc_data.production.duplicate(true)
	needs_house = npc_data.needs_house


func _update_production(delta: float) -> void:
	if not recruited or not has_house:
		return

	for index in range(production.size()):
		var production_entry = production[index]
		if not production_entry is Dictionary:
			continue

		var item_id := str(production_entry.get("item_id", ""))
		var amount := int(production_entry.get("amount", 0))
		var interval_seconds := float(production_entry.get("interval_seconds", 0.0))
		if item_id.is_empty() or amount <= 0 or interval_seconds <= 0.0:
			continue

		if not _is_valid_item_id(item_id):
			push_error("NPC production item_id does not exist: %s" % item_id)
			continue

		var timer_key := str(index)
		var elapsed := float(production_timers.get(timer_key, 0.0)) + delta
		if elapsed >= interval_seconds:
			elapsed = 0.0
			_produce_item(item_id, amount)

		production_timers[timer_key] = elapsed


func _produce_item(item_id: String, amount: int) -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main == null or not main.has_method("add_resource"):
		return

	main.add_resource(item_id, amount)
	print("%s produced %d %s" % [display_name, amount, _get_item_display_name(item_id)])


func _is_valid_item_id(item_id: String) -> bool:
	var content_db := get_node_or_null("/root/ContentDB")
	return content_db != null and content_db.has_method("has_item") and content_db.has_item(item_id)


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_item"):
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))
