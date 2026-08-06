extends "res://scripts/pets/ButterflyPickupPet.gd"


func setup(owner_player: Node2D, item_data: Dictionary = {}) -> void:
	super.setup(owner_player, item_data)
	_apply_pet_visual_scale()


func _apply_pet_visual_scale() -> void:
	if sprite == null:
		return
	var visual_scale := maxf(float(pet_data.get("visual_scale", 2.0)), 0.05)
	sprite.scale = Vector2.ONE * visual_scale
	set_meta("pet_visual_scale", visual_scale)
