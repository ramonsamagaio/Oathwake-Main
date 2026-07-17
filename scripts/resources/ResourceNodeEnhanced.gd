extends "res://scripts/ResourceNode.gd"

const HitFlashOverlayScript := preload("res://scripts/effects/HitFlashOverlay.gd")


func take_damage(amount: int) -> void:
	var health_before := health
	super.take_damage(amount)
	if amount > 0 and health_before > health:
		_play_resource_hit_feedback(false)


func _show_gather_feedback(text: String, is_critical: bool, is_damage: bool) -> void:
	if is_damage:
		_play_resource_hit_feedback(is_critical)
	super._show_gather_feedback(text, is_critical, is_damage)


func _play_resource_hit_feedback(is_critical: bool) -> void:
	var vfx_profile := _get_vfx_profile()
	var duration := float(vfx_profile.get("white_hit_flash_duration", 0.08))
	if is_critical:
		duration = float(vfx_profile.get("critical_white_hit_flash_duration", max(duration, 0.10)))
	HitFlashOverlayScript.flash_node(self, duration)
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_hit_for_target"):
		sfx_manager.play_hit_for_target(self, is_critical)
