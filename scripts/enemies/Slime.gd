extends CharacterBody2D

const CombatCalculatorScript := preload("res://scripts/systems/CombatCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
const OverheadNameplateScene := preload("res://scenes/ui/OverheadNameplate.tscn")

@export var monster_id: String = "slime"
@export var speed: float = 45.0
@export var damage: int = 10
@export var damage_cooldown: float = 1.0
@export var max_health: int = 30
@export var gel_drop_amount: int = 1
@export var show_nameplates := true
@export var show_floating_damage := true
@export var enable_hit_flash := true
@export var enable_knockback := true

var player: CharacterBody2D
var player_in_contact := false
var damage_timer := 0.0
var health: int = 30
var is_dead := false
var display_name := "Slime"
var spawn_time_seconds := 20.0
var spawn_tiles := []
var loot_table := []
var nameplate: Node2D
var monster_data := {}
var combat_calculator := CombatCalculatorScript.new()
var original_scale := Vector2.ONE

@onready var damage_area: Area2D = $DamageArea


func _ready() -> void:
	add_to_group("enemy")
	original_scale = scale
	_load_monster_data()
	health = max_health
	_setup_nameplate()
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	damage_area.body_exited.connect(_on_damage_area_body_exited)
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	_move_toward_player()
	_update_damage(delta)


func _move_toward_player() -> void:
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := global_position.direction_to(player.global_position)
	velocity = direction * speed
	move_and_slide()


func _update_damage(delta: float) -> void:
	if damage_timer > 0.0:
		damage_timer -= delta

	if player_in_contact and damage_timer <= 0.0 and _can_damage_player():
		_attack_player()
		damage_timer = damage_cooldown


func _attack_player() -> void:
	var target_data := {}
	if player.has_method("_get_combat_data"):
		target_data = player.call("_get_combat_data")

	var combat_result := combat_calculator.calculate_damage(get_combat_data(), target_data)
	if player.has_method("apply_combat_result"):
		player.call("apply_combat_result", combat_result)
	else:
		player.take_damage(int(combat_result.get("damage", damage)))


func take_damage(amount: int) -> void:
	if is_dead:
		return

	if amount <= 0:
		return

	health = max(health - amount, 0)
	_update_nameplate()
	_play_hit_feedback(false)
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), false, "enemy")

	if health == 0:
		_die()


func apply_combat_result(combat_result: Dictionary) -> void:
	if is_dead:
		return

	if bool(combat_result.get("miss", false)):
		if show_floating_damage:
			FloatingCombatTextSpawner.show_miss(global_position + Vector2(0, -28))
		return

	var amount := int(combat_result.get("damage", 0))
	if amount <= 0:
		return

	health = max(health - amount, 0)
	_update_nameplate()
	var is_critical := bool(combat_result.get("is_critical", false))
	_play_hit_feedback(is_critical)
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), is_critical, "enemy")

	if health == 0:
		_die()


func _die() -> void:
	is_dead = true
	_drop_loot()
	damage_area.monitoring = false
	set_physics_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_property(self, "scale", original_scale * 0.75, 0.18)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _drop_loot() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main == null:
		return

	if not main.has_method("add_resource"):
		return

	if loot_table.is_empty():
		main.add_resource("gel", gel_drop_amount)
		print("%s dropped %d gel" % [display_name, gel_drop_amount])
		return

	for loot_entry in loot_table:
		if not loot_entry is Dictionary:
			continue

		var chance := float(loot_entry.get("chance", 1.0))
		if randf() > chance:
			continue

		var item_id := str(loot_entry.get("item_id", ""))
		var min_amount := int(loot_entry.get("min_amount", 1))
		var max_amount := int(loot_entry.get("max_amount", min_amount))
		var amount := min_amount
		if max_amount > min_amount:
			amount += int(randi() % (max_amount - min_amount + 1))

		if not item_id.is_empty() and amount > 0:
			main.add_resource(item_id, amount)
			print("%s dropped %d %s" % [display_name, amount, item_id])


func _on_damage_area_body_entered(body: Node2D) -> void:
	if _is_player_body(body):
		player = body as CharacterBody2D
		player_in_contact = true


func _on_damage_area_body_exited(body: Node2D) -> void:
	if _is_player_body(body):
		player_in_contact = false


func _can_damage_player() -> bool:
	return player != null and is_instance_valid(player) and player.is_in_group("player")


func _is_player_body(body: Node2D) -> bool:
	return body != null and body.is_in_group("player")


func _load_monster_data() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return

	monster_data = content_db.get_monster(monster_id)
	if monster_data.is_empty():
		push_error("Slime could not load monster_id: %s" % monster_id)
		return

	display_name = str(monster_data.get("display_name", display_name))
	max_health = int(monster_data.get("max_health", max_health))
	speed = float(monster_data.get("move_speed", speed))
	damage = int(monster_data.get("damage", damage))
	damage_cooldown = float(monster_data.get("attack_cooldown", damage_cooldown))
	spawn_time_seconds = float(monster_data.get("spawn_time_seconds", spawn_time_seconds))

	var loaded_spawn_tiles = monster_data.get("spawn_tiles", spawn_tiles)
	if loaded_spawn_tiles is Array:
		spawn_tiles = loaded_spawn_tiles

	var loaded_loot_table = monster_data.get("loot_table", loot_table)
	if loaded_loot_table is Array:
		loot_table = loaded_loot_table

	print("%s loaded monster data from ContentDB" % display_name)


func _setup_nameplate() -> void:
	if not show_nameplates:
		return

	nameplate = OverheadNameplateScene.instantiate()
	add_child(nameplate)
	nameplate.setup(display_name, health, max_health)


func _update_nameplate() -> void:
	if nameplate == null or not is_instance_valid(nameplate):
		return

	nameplate.set_health(health, max_health)


func _play_hit_feedback(is_critical: bool) -> void:
	if not enable_hit_flash:
		return

	var flash_color := Color(1.0, 0.65, 0.55, 1.0) if is_critical else Color(1.0, 0.35, 0.35, 1.0)
	for child in get_children():
		if not child is CanvasItem:
			continue
		if child == nameplate:
			continue

		var canvas_item := child as CanvasItem
		var original_color := canvas_item.modulate
		canvas_item.modulate = flash_color
		var tween := create_tween()
		tween.tween_property(canvas_item, "modulate", original_color, 0.12 if is_critical else 0.08)

	if enable_knockback:
		var bump_scale := original_scale * (1.08 if is_critical else 1.04)
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", bump_scale, 0.04)
		scale_tween.tween_property(self, "scale", original_scale, 0.08)


func get_combat_data() -> Dictionary:
	var combat_data: Dictionary = monster_data.duplicate(true) if monster_data is Dictionary else {}
	combat_data["max_health"] = max_health
	combat_data["damage"] = damage
	if not combat_data.has("base_combat"):
		combat_data["base_combat"] = {
			"base_attack": damage,
			"attack_cooldown": damage_cooldown,
		}
	return combat_data
