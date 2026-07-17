extends "res://scripts/enemies/EnemyBase.gd"

const HitFlashOverlayScript := preload("res://scripts/effects/HitFlashOverlay.gd")


func _play_hit_feedback(is_critical: bool) -> void:
	var vfx_profile := _get_vfx_profile()
	var flash_duration := float(vfx_profile.get("white_hit_flash_duration", 0.08))
	if is_critical:
		flash_duration = float(vfx_profile.get("critical_white_hit_flash_duration", max(flash_duration, 0.10)))
	HitFlashOverlayScript.flash_node(self, flash_duration)
	var sfx_manager := get_node_or_null("/root/SFXManager")
	if sfx_manager != null and sfx_manager.has_method("play_hit_for_target"):
		sfx_manager.play_hit_for_target(self, is_critical)

	if enable_knockback:
		var hit_bump_scale := float(vfx_profile.get("hit_bump_scale", 1.04))
		var critical_bump_scale := float(vfx_profile.get("critical_bump_scale", 1.08))
		var bump_scale := original_scale * (critical_bump_scale if is_critical else hit_bump_scale)
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", bump_scale, 0.04)
		scale_tween.tween_property(self, "scale", original_scale, 0.08)
