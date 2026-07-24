extends SceneTree

const IMAGE_SPECS := {
	"dual mask": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_mask_64.png",
		"size": Vector2i(256, 256),
	},
	"dual overlay": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_edge_overlay_64.png",
		"size": Vector2i(256, 256),
	},
	"native 47 mask": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_native_47_mask.png",
		"size": Vector2i(768, 256),
	},
	"native 47 overlay": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_native_47_edge_overlay.png",
		"size": Vector2i(768, 256),
	},
	"WebTyler input mask": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_webtyler_input_mask_4x4.png",
		"size": Vector2i(256, 256),
	},
	"WebTyler input overlay": {
		"path": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_webtyler_input_edge_overlay_4x4.png",
		"size": Vector2i(256, 256),
	},
}


func _initialize() -> void:
	var failures: Array[String] = []

	for label: String in IMAGE_SPECS:
		var spec: Dictionary = IMAGE_SPECS[label]
		var path: String = spec["path"]
		var expected_size := Vector2(spec["size"])
		if not FileAccess.file_exists(path):
			failures.append("%s is missing: %s" % [label, path])
			continue

		var texture := load(path) as Texture2D
		if texture == null:
			failures.append("%s cannot be imported as Texture2D: %s" % [label, path])
			continue
		if texture.get_size() != expected_size:
			failures.append(
				"%s must be %s, received %s" % [
					label,
					expected_size,
					texture.get_size(),
				]
			)

	if failures.is_empty():
		print("TERRAIN_MASK_IMPORT_VALIDATION: PASS")
		quit(OK)
		return

	for failure in failures:
		push_error(failure)
	print("TERRAIN_MASK_IMPORT_VALIDATION: FAIL (%d issue(s))" % failures.size())
	quit(1)
