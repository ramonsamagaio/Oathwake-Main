extends "res://scripts/buildings/Building.gd"

const ContentGlowRuntime := preload("res://scripts/effects/ContentGlowRuntime.gd")


func _ready() -> void:
	super._ready()
	_apply_content_lighting()


func setup(new_building_id: String, new_data: Dictionary = {}) -> void:
	super.setup(new_building_id, new_data)
	_apply_content_lighting()


func _on_content_reloaded() -> void:
	super._on_content_reloaded()
	_apply_content_lighting()


func _apply_content_lighting() -> void:
	ContentGlowRuntime.apply_glow(self, building_data.get("glow", {}) if building_data.get("glow", {}) is Dictionary else {}, 24)
