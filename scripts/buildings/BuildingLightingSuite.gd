extends "res://scripts/buildings/Building.gd"

const ContentGlowRuntime := preload("res://scripts/effects/ContentGlowRuntime.gd")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")
const EmberEmitterScript := preload("res://scripts/effects/EmberEmitter.gd")
const CampfireFlameAnimatorScript := preload("res://scripts/effects/CampfireFlameAnimator.gd")
const EnvironmentalHazardScript := preload("res://scripts/systems/EnvironmentalHazard.gd")

const CAMPFIRE_ID := "campfire"
const CAMPFIRE_FLAME_Z_INDEX := 70
const CAMPFIRE_EMBER_Z_INDEX := 80


func _ready() -> void:
	super._ready()
	_apply_content_presentation()


func setup(new_building_id: String, new_data: Dictionary = {}) -> void:
	super.setup(new_building_id, new_data)
	_apply_content_presentation()


func _on_content_reloaded() -> void:
	super._on_content_reloaded()
	_apply_content_presentation()


func _apply_content_presentation() -> void:
	ContentGlowRuntime.apply_glow(self, building_data.get("glow", {}) if building_data.get("glow", {}) is Dictionary else {}, 24)
	var depth_value: Variant = building_data.get("depth_sort", {})
	var depth_config: Dictionary = (depth_value as Dictionary) if depth_value is Dictionary else {}
	if content_sprite != null and content_sprite.visible:
		var depth_y := WorldDepthRuntime.get_sprite_depth_y(content_sprite, float(depth_config.get("line_ratio", 0.64)))
		WorldDepthRuntime.apply_depth(self, depth_y + float(depth_config.get("offset_y", 0.0)))
	else:
		WorldDepthRuntime.apply_node_depth(self, float(depth_config.get("offset_y", 0.0)))

	var shadow_value: Variant = building_data.get("shadow", {})
	var shadow_config: Dictionary = (shadow_value as Dictionary).duplicate(true) if shadow_value is Dictionary else {}
	if not shadow_config.has("enabled"):
		shadow_config["enabled"] = true
	var visual_size := DirectionalShadowRuntime.estimate_target_visual_size(self)
	var foot_offset := DirectionalShadowRuntime.estimate_target_foot_offset(self)
	DirectionalShadowRuntime.apply_to_target(self, shadow_config, visual_size, foot_offset)
	_apply_runtime_building_features()


func _apply_runtime_building_features() -> void:
	if building_id == CAMPFIRE_ID:
		_ensure_campfire_effects()
		return
	remove_from_group("campfire")
	_disable_runtime_child("AnimatedFlame")
	_disable_runtime_child("EmberEmitter")
	_disable_runtime_child("ElementalHazard")


func _ensure_campfire_effects() -> void:
	add_to_group("campfire")
	_ensure_campfire_animated_flame()

	var ember_emitter := get_node_or_null("EmberEmitter") as Node2D
	if ember_emitter == null:
		ember_emitter = EmberEmitterScript.new()
		ember_emitter.name = "EmberEmitter"
		add_child(ember_emitter)
	if ember_emitter.has_method("apply_small_campfire_preset"):
		ember_emitter.call("apply_small_campfire_preset")
	ember_emitter.position = Vector2(-1.0, -16.0)
	ember_emitter.z_as_relative = true
	# EmberEmitter reapplies z_index_value every frame, so both values must be
	# configured. Setting only z_index made the particles fall back under the
	# campfire on the next process tick.
	ember_emitter.set("z_index_value", CAMPFIRE_EMBER_Z_INDEX)
	ember_emitter.z_index = CAMPFIRE_EMBER_Z_INDEX
	ember_emitter.visible = true
	ember_emitter.set_process(true)

	var hazard := get_node_or_null("ElementalHazard") as Area2D
	if hazard == null:
		hazard = EnvironmentalHazardScript.new()
		hazard.name = "ElementalHazard"
		add_child(hazard)
	hazard.position = Vector2(0.0, -7.0)
	hazard.call("configure", {
		"condition_id": "burning",
		"condition_duration": 4.0,
		"condition_potency": 1.0,
		"reapply_interval": 0.45,
		"radius": 20.0,
		"avoidance_radius": 52.0,
		"hazard_cost": 1.0,
		"affects_groups": ["player", "enemy"],
	})
	hazard.monitoring = true
	hazard.set_physics_process(true)


func _ensure_campfire_animated_flame() -> void:
	var flame := get_node_or_null("AnimatedFlame") as AnimatedSprite2D
	if flame == null:
		flame = CampfireFlameAnimatorScript.new()
		flame.name = "AnimatedFlame"
		add_child(flame)
	flame.position = Vector2(0.0, -20.0)
	flame.z_as_relative = true
	flame.z_index = CAMPFIRE_FLAME_Z_INDEX
	flame.visible = true
	flame.process_mode = Node.PROCESS_MODE_INHERIT
	if flame.has_method("configure_from_sheet"):
		flame.call("configure_from_sheet")
	if flame.sprite_frames != null and flame.sprite_frames.has_animation("burn"):
		flame.play("burn")


func _disable_runtime_child(child_name: String) -> void:
	var child := get_node_or_null(child_name)
	if child == null:
		return
	if child is CanvasItem:
		(child as CanvasItem).visible = false
	child.set_process(false)
	child.set_physics_process(false)
	if child is Area2D:
		(child as Area2D).monitoring = false
