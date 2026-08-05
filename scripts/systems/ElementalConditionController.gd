extends Node2D

signal condition_applied(condition_id: String, stacks: int, duration: float)
signal condition_removed(condition_id: String)
signal condition_ticked(condition_id: String, damage: int)

const ElementalDamageResolverScript := preload("res://scripts/systems/ElementalDamageResolver.gd")

const CONDITION_PROFILES := {
	"burning": {
		"display_name": "Burning",
		"element": "fire",
		"duration": 4.0,
		"tick_interval": 0.75,
		"damage_per_tick": 3.0,
		"max_stacks": 3,
		"movement_multiplier": 1.0,
		"color": Color(1.0, 0.34, 0.08, 1.0),
	},
	"poisoned": {
		"display_name": "Poisoned",
		"element": "poison",
		"duration": 7.0,
		"tick_interval": 1.0,
		"damage_per_tick": 2.0,
		"max_stacks": 5,
		"movement_multiplier": 0.94,
		"color": Color(0.42, 0.92, 0.24, 1.0),
	},
	"bleeding": {
		"display_name": "Bleeding",
		"element": "physical",
		"duration": 5.0,
		"tick_interval": 0.8,
		"damage_per_tick": 2.0,
		"max_stacks": 4,
		"movement_multiplier": 0.96,
		"color": Color(0.88, 0.10, 0.12, 1.0),
	},
	"chilled": {
		"display_name": "Chilled",
		"element": "frost",
		"duration": 4.0,
		"tick_interval": 0.0,
		"damage_per_tick": 0.0,
		"max_stacks": 1,
		"movement_multiplier": 0.72,
		"color": Color(0.38, 0.82, 1.0, 1.0),
	},
	"shocked": {
		"display_name": "Shocked",
		"element": "lightning",
		"duration": 3.5,
		"tick_interval": 1.0,
		"damage_per_tick": 2.0,
		"max_stacks": 2,
		"movement_multiplier": 0.88,
		"color": Color(0.98, 0.84, 0.22, 1.0),
	},
}

var active_conditions: Dictionary = {}
var _visual_time := 0.0


func _ready() -> void:
	name = "ElementalConditions"
	z_index = 80
	add_to_group("status_effect_controller")
	set_process(true)


func apply_condition(condition_id: String, duration := -1.0, potency := 1.0, source: Node = null) -> bool:
	var normalized := condition_id.strip_edges().to_lower()
	if not CONDITION_PROFILES.has(normalized):
		push_warning("Unknown elemental condition: %s" % condition_id)
		return false

	var profile: Dictionary = (CONDITION_PROFILES[normalized] as Dictionary).duplicate(true)
	var resolved_duration := duration if duration > 0.0 else float(profile.get("duration", 1.0))
	var source_id := source.get_instance_id() if source != null and is_instance_valid(source) else 0
	var state: Dictionary = active_conditions.get(normalized, {})
	var previous_source_id := int(state.get("source_id", -1))
	var stacks := int(state.get("stacks", 0))
	if state.is_empty():
		stacks = 1
	elif source_id == 0 or previous_source_id != source_id:
		stacks = mini(stacks + 1, int(profile.get("max_stacks", 1)))

	state["remaining"] = maxf(float(state.get("remaining", 0.0)), resolved_duration)
	state["tick_left"] = minf(float(state.get("tick_left", float(profile.get("tick_interval", 0.0)))), float(profile.get("tick_interval", 0.0)))
	state["stacks"] = maxi(stacks, 1)
	state["potency"] = maxf(float(state.get("potency", 0.0)), maxf(potency, 0.01))
	state["source"] = weakref(source) if source != null and is_instance_valid(source) else null
	state["source_id"] = source_id
	active_conditions[normalized] = state
	condition_applied.emit(normalized, int(state["stacks"]), resolved_duration)
	queue_redraw()
	return true


func remove_condition(condition_id: String) -> void:
	var normalized := condition_id.strip_edges().to_lower()
	if not active_conditions.has(normalized):
		return
	active_conditions.erase(normalized)
	condition_removed.emit(normalized)
	queue_redraw()


func clear_all_conditions() -> void:
	var ids := active_conditions.keys()
	active_conditions.clear()
	for condition_id in ids:
		condition_removed.emit(str(condition_id))
	queue_redraw()


func has_condition(condition_id: String) -> bool:
	return active_conditions.has(condition_id.strip_edges().to_lower())


func get_active_conditions() -> Dictionary:
	return active_conditions.duplicate(false)


func get_movement_multiplier() -> float:
	var multiplier := 1.0
	for condition_id in active_conditions.keys():
		var profile: Dictionary = CONDITION_PROFILES.get(str(condition_id), {})
		multiplier *= clampf(float(profile.get("movement_multiplier", 1.0)), 0.1, 2.0)
	return clampf(multiplier, 0.25, 1.5)


func _process(delta: float) -> void:
	_visual_time += delta
	var expired: Array[String] = []
	for condition_variant in active_conditions.keys():
		var condition_id := str(condition_variant)
		var state: Dictionary = active_conditions.get(condition_id, {})
		var profile: Dictionary = CONDITION_PROFILES.get(condition_id, {})
		state["remaining"] = float(state.get("remaining", 0.0)) - delta
		var tick_interval := float(profile.get("tick_interval", 0.0))
		if tick_interval > 0.0 and float(profile.get("damage_per_tick", 0.0)) > 0.0:
			state["tick_left"] = float(state.get("tick_left", tick_interval)) - delta
			while float(state.get("tick_left", 0.0)) <= 0.0 and float(state.get("remaining", 0.0)) > 0.0:
				_tick_condition(condition_id, state, profile)
				state["tick_left"] = float(state.get("tick_left", 0.0)) + tick_interval
		active_conditions[condition_id] = state
		if float(state.get("remaining", 0.0)) <= 0.0:
			expired.append(condition_id)

	for condition_id in expired:
		remove_condition(condition_id)
	if not active_conditions.is_empty():
		queue_redraw()


func _tick_condition(condition_id: String, state: Dictionary, profile: Dictionary) -> void:
	var target := get_parent()
	if target == null or not is_instance_valid(target):
		return
	var raw_damage := float(profile.get("damage_per_tick", 0.0)) * float(state.get("stacks", 1)) * float(state.get("potency", 1.0))
	var source: Node = null
	var source_ref: Variant = state.get("source")
	if source_ref is WeakRef:
		source = (source_ref as WeakRef).get_ref() as Node
	var damage := maxi(int(round(raw_damage)), 1)
	if target.has_method("take_elemental_damage"):
		target.call("take_elemental_damage", damage, str(profile.get("element", "physical")), source, condition_id)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage)
	condition_ticked.emit(condition_id, damage)


func _draw() -> void:
	if active_conditions.is_empty():
		return
	var effect_index := 0
	for condition_variant in active_conditions.keys():
		var condition_id := str(condition_variant)
		var profile: Dictionary = CONDITION_PROFILES.get(condition_id, {})
		var color: Color = profile.get("color", Color.WHITE)
		for pixel_index in range(4):
			var phase := _visual_time * (2.2 + float(effect_index) * 0.2) + float(pixel_index) * 1.7
			var radius := 11.0 + float(pixel_index % 2) * 4.0
			var position := Vector2(cos(phase), sin(phase * 1.23)) * radius + Vector2(0.0, -8.0 - float(effect_index) * 2.0)
			var alpha := 0.45 + 0.35 * ((sin(phase * 2.0) + 1.0) * 0.5)
			draw_rect(Rect2(position.round() - Vector2.ONE, Vector2(2.0, 2.0)), Color(color.r, color.g, color.b, alpha), true)
		effect_index += 1
