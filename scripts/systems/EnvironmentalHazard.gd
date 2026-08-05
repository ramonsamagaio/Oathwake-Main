extends Area2D

@export var condition_id := "burning"
@export var condition_duration := 4.0
@export var condition_potency := 1.0
@export var reapply_interval := 0.45
@export var avoidance_radius := 46.0
@export var hazard_cost := 1.0
@export var affects_groups: Array[String] = ["player", "enemy"]

var _tracked_bodies: Dictionary = {}
var _reapply_left := 0.0
var _shape_radius := 20.0


func _ready() -> void:
	add_to_group("environmental_hazard")
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_ensure_collision_shape()
	set_physics_process(true)


func configure(config: Dictionary) -> void:
	condition_id = str(config.get("condition_id", condition_id))
	condition_duration = maxf(float(config.get("condition_duration", condition_duration)), 0.1)
	condition_potency = maxf(float(config.get("condition_potency", condition_potency)), 0.01)
	reapply_interval = maxf(float(config.get("reapply_interval", reapply_interval)), 0.1)
	_shape_radius = maxf(float(config.get("radius", _shape_radius)), 2.0)
	avoidance_radius = maxf(float(config.get("avoidance_radius", maxf(avoidance_radius, _shape_radius + 20.0))), _shape_radius)
	hazard_cost = maxf(float(config.get("hazard_cost", hazard_cost)), 0.0)
	var groups_value: Variant = config.get("affects_groups", affects_groups)
	if groups_value is Array:
		affects_groups.clear()
		for group_value in groups_value:
			affects_groups.append(str(group_value))
	_ensure_collision_shape()


func _physics_process(delta: float) -> void:
	_reapply_left -= delta
	if _reapply_left > 0.0:
		return
	_reapply_left = reapply_interval
	var stale: Array[int] = []
	for body_id_variant in _tracked_bodies.keys():
		var body_id := int(body_id_variant)
		var body_ref: Variant = _tracked_bodies.get(body_id)
		var body: Node = null
		if body_ref is WeakRef:
			body = (body_ref as WeakRef).get_ref() as Node
		if body == null or not is_instance_valid(body):
			stale.append(body_id)
			continue
		_apply_to_body(body)
	for body_id in stale:
		_tracked_bodies.erase(body_id)


func is_dangerous_to(body: Node) -> bool:
	if body == null:
		return false
	for group_name in affects_groups:
		if body.is_in_group(group_name):
			return true
	return false


func get_avoidance_center() -> Vector2:
	return global_position


func get_avoidance_radius() -> float:
	return avoidance_radius


func get_avoidance_cost() -> float:
	return hazard_cost


func _on_body_entered(body: Node2D) -> void:
	if not is_dangerous_to(body):
		return
	_tracked_bodies[body.get_instance_id()] = weakref(body)
	_apply_to_body(body)


func _on_body_exited(body: Node2D) -> void:
	if body != null:
		_tracked_bodies.erase(body.get_instance_id())


func _apply_to_body(body: Node) -> void:
	if body == null or not is_instance_valid(body) or not is_dangerous_to(body):
		return
	if body.has_method("apply_condition"):
		body.call("apply_condition", condition_id, condition_duration, condition_potency, self)


func _ensure_collision_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		add_child(shape_node)
	var circle := CircleShape2D.new()
	circle.radius = _shape_radius
	shape_node.shape = circle
