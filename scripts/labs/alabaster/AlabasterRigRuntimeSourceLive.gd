extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSource.gd"

# Small live correction layer over the source-derived runtime. It keeps the
# main reconstruction readable while applying selection-dependent details
# that the billboard transform itself does not receive as arguments.

var _active_record: Dictionary = {}


func _update_sprite_source(record: Dictionary) -> void:
	_active_record = record
	super._update_sprite_source(record)
	_active_record = {}


func _billboard_xfm(node_name: String, state: Dictionary, gfx_world: Vector3, gfx_screen: Vector2, billboard: Dictionary, row: Dictionary, rot_mode: int, tile_idx: int, tile_w: int, tile_h: int, pivot_px: Vector2, region: Rect2) -> Dictionary:
	var result: Dictionary = super._billboard_xfm(node_name, state, gfx_world, gfx_screen, billboard, row, rot_mode, tile_idx, tile_w, tile_h, pivot_px, region)
	if _active_record.is_empty():
		return result
	var gfx: Dictionary = _active_record.get("gfx", {})
	var selected: Dictionary = _select_texture(gfx.get("tex", {}), state)
	if selected.is_empty():
		return result
	var entry: Dictionary = selected.get("entry", {})
	var facing: Dictionary = _select_facing_source(
		String(entry.get("facing", "FACE_1")),
		float(state.get("facing_yaw", 180.0)),
		bool(state.get("yaw_flipped", false)) and bool(entry.get("flipRoll", false))
	)
	if not bool(facing.get("flip", false)):
		return result
	var refs: Array = row.get("refAngles", [])
	if tile_idx < 0 or tile_idx >= refs.size() or refs[tile_idx] == null:
		return result
	# bundle.js: if texResult.flipX != root.flipX, rotRef = 2PI - refAngle.
	# Root FACE_16 does not flip, so converting angle-ref to angle-(2PI-ref)
	# is equivalent to adding 2*ref modulo a full turn.
	result["rotation"] = float(result.get("rotation", 0.0)) + 2.0 * deg_to_rad(float(refs[tile_idx]))
	return result
