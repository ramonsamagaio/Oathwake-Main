extends "res://scripts/player/PlayerAlabasterRigSuite.gd"

const OptimizedWeaponVisualRuntime := preload("res://scripts/player/AlabasterWeaponVisualRuntimeOptimized.gd")


func _init() -> void:
	# Parent declares the weapon visual as the base runtime type; this optimized
	# implementation is a subtype and keeps the same public contract.
	_weapon_visual = OptimizedWeaponVisualRuntime.new()
