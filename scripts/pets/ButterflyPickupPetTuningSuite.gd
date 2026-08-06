extends "res://scripts/pets/ButterflyPickupPet.gd"

const MonsterParticleRuntime := preload("res://scripts/effects/MonsterParticleRuntime.gd")


func setup(owner_player: Node2D, item_data: Dictionary = {}) -> void:
	super.setup(owner_player, item_data)
	_apply_pet_visual_scale()
	_apply_pet_particles()
	_apply_pet_horizontal_facing()


func _process(delta: float) -> void:
	super._process(delta)
	_apply_pet_horizontal_facing()


func _apply_pet_visual_scale() -> void:
	if sprite == null:
		return
	var visual_scale := maxf(float(pet_data.get("visual_scale", 2.0)), 0.05)
	sprite.scale = Vector2.ONE * visual_scale
	set_meta("pet_visual_scale", visual_scale)


func _apply_pet_particles() -> void:
	MonsterParticleRuntime.apply(self, pet_data)
	var particles := get_node_or_null("ContentParticles") as CPUParticles2D
	if particles != null:
		particles.add_to_group("persistent_content_visual")
		set_meta("pet_particles_enabled", true)
		set_meta("pet_particle_mode", str(particles.get_meta("content_particle_mode", "trail")))
	else:
		set_meta("pet_particles_enabled", false)
		set_meta("pet_particle_mode", "none")


func _apply_pet_horizontal_facing() -> void:
	if sprite == null or absf(_velocity.x) <= 0.5:
		return
	# The authored butterfly sheet faces left. Mirror only while travelling right;
	# vertical drift keeps the previous horizontal side instead of flickering.
	sprite.flip_h = _velocity.x > 0.0
	set_meta("butterfly_horizontal_facing", "right" if sprite.flip_h else "left")
