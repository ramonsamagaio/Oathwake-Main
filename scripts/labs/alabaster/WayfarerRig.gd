extends "res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd"
## Isolated reference-character skin. Inherits the exact JunoBase rig and cuts.
const WAYFARER_ATLAS := "res://assets/sprites/characters/WAYFARER.png"

func _load_png_texture(path: String) -> Texture2D:
	return super._load_png_texture(WAYFARER_ATLAS if path == COMPACT_ATLAS_PATH else path)

func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["profile"] = "wayfarer"
	result["profile_label"] = "Wayfarer reference character"
	result["core_atlas_path"] = WAYFARER_ATLAS
	result["compact_atlas_path"] = WAYFARER_ATLAS
	return result
