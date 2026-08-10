extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"

const ProductionRigRuntime := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd")

# UI layer over the validated mechanic lab. The playground uses the same
# production rig/runtime and the same repository-local animation bank as gameplay.
# No Steam/local-install source lookup is needed.

var _sprite_opacity_slider: HSlider


func _ready() -> void:
	super._ready()
	_build_sprite_opacity_control()


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "AlabasterPlayer"
	player.position = SCREEN_SIZE * 0.5 + Vector2(0.0, 80.0)
	add_child(player)

	rig = ProductionRigRuntime.new()
	rig.name = "JunoProductionRig"
	rig.scale = Vector2(2.5, 2.5)
	player.add_child(rig)


# AlabasterMechanicLab intentionally handles keyboard commands by polling global
# key state in _physics_process(). Do not call super._unhandled_key_input(): the
# parent does not define that virtual callback, and Godot treats that as a parser
# error before the playground can open.


func _build_sprite_opacity_control() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpriteOpacityControls"
	layer.layer = 90
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 112)
	panel.custom_minimum_size = Vector2(310, 58)
	layer.add_child(panel)

	var row := HBoxContainer.new()
	panel.add_child(row)

	var label := Label.new()
	label.text = "Sprite opacity"
	label.custom_minimum_size = Vector2(115, 0)
	row.add_child(label)

	_sprite_opacity_slider = HSlider.new()
	_sprite_opacity_slider.min_value = 0.0
	_sprite_opacity_slider.max_value = 1.0
	_sprite_opacity_slider.step = 0.05
	_sprite_opacity_slider.value = 1.0
	_sprite_opacity_slider.custom_minimum_size = Vector2(150, 0)
	_sprite_opacity_slider.focus_mode = Control.FOCUS_NONE
	_sprite_opacity_slider.tooltip_text = "Lower this to inspect the bones underneath the sprites."
	_sprite_opacity_slider.value_changed.connect(_on_sprite_opacity_changed)
	row.add_child(_sprite_opacity_slider)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "100%"
	row.add_child(value_label)
	_sprite_opacity_slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % roundi(value * 100.0)
	)


func _on_sprite_opacity_changed(value: float) -> void:
	if rig != null and rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", value)
