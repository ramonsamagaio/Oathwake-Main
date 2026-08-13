extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"

const SharedJunoRigRuntime := preload("res://scripts/systems/bones/BonesSystem.gd")

# UI layer over the validated mechanic lab. The playground now instantiates the
# exact same BonesSystem used by gameplay, Mechanic Lab Juno and Bone Studio.
# Animation-bank recovery/fallback behavior therefore cannot diverge here.

var _sprite_opacity_slider: HSlider


func _ready() -> void:
	super._ready()
	_build_sprite_opacity_control()


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "AlabasterPlayer"
	player.position = SCREEN_SIZE * 0.5 + Vector2(0.0, 80.0)
	add_child(player)

	rig = SharedJunoRigRuntime.new()
	rig.name = "JunoSharedBonesRig"
	rig.scale = Vector2(2.5, 2.5)
	player.add_child(rig)


# AlabasterMechanicLab owns the keyboard command path in _input(). There is no
# parent _unhandled_key_input() callback to chain here.


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