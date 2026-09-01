class_name ConstructionWallTopology
extends RefCounted

## Shared topology grammar for the player-built wall family.
##
## The player places semantic wall-family cells on the 32 px construction grid.
## Visual combinations are derived from cardinal neighbours so the artist does
## not need to author separate L/T/cross/end-cap sprites.

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const HORIZONTAL_MASK := EAST | WEST
const VERTICAL_MASK := NORTH | SOUTH
const ALL_MASK := NORTH | EAST | SOUTH | WEST

const AXIS_EW := "ew"
const AXIS_NS := "ns"
const AXIS_JUNCTION := "junction"

const TYPE_ISOLATED := "isolated"
const TYPE_END := "end"
const TYPE_STRAIGHT := "straight"
const TYPE_CORNER := "corner"
const TYPE_TEE := "tee"
const TYPE_CROSS := "cross"

const WALL_FAMILY := {
	"wall": true,
	"wall_window": true,
	"wall_doorway": true,
	"door": true,
}


static func is_wall_family(building_type: String) -> bool:
	return WALL_FAMILY.has(building_type.to_lower())


static func mask_from_neighbor_types(north_type: String, east_type: String, south_type: String, west_type: String) -> int:
	var mask := 0
	if is_wall_family(north_type):
		mask |= NORTH
	if is_wall_family(east_type):
		mask |= EAST
	if is_wall_family(south_type):
		mask |= SOUTH
	if is_wall_family(west_type):
		mask |= WEST
	return mask


static func classify(mask: int) -> String:
	mask &= ALL_MASK
	var count := _bit_count(mask)
	match count:
		0:
			return TYPE_ISOLATED
		1:
			return TYPE_END
		2:
			if mask == HORIZONTAL_MASK or mask == VERTICAL_MASK:
				return TYPE_STRAIGHT
			return TYPE_CORNER
		3:
			return TYPE_TEE
		4:
			return TYPE_CROSS
	return TYPE_ISOLATED


static func infer_axis(mask: int, fallback_axis: String = AXIS_EW) -> String:
	mask &= ALL_MASK
	var has_horizontal := (mask & HORIZONTAL_MASK) != 0
	var has_vertical := (mask & VERTICAL_MASK) != 0
	if has_horizontal and not has_vertical:
		return AXIS_EW
	if has_vertical and not has_horizontal:
		return AXIS_NS
	if has_horizontal and has_vertical:
		return AXIS_JUNCTION
	return _normalize_axis(fallback_axis)


static func resolve_straight_axis(mask: int, preferred_axis: String = AXIS_EW) -> String:
	## Special wall modules such as windows and doorways must remain straight.
	## If a junction surrounds the cell, preserve the authored preferred axis
	## rather than requiring a unique corner-window or T-door sprite.
	var inferred := infer_axis(mask, preferred_axis)
	if inferred == AXIS_JUNCTION:
		return _normalize_axis(preferred_axis)
	return inferred


static func is_straight_compatible(mask: int, axis: String) -> bool:
	mask &= ALL_MASK
	axis = _normalize_axis(axis)
	if axis == AXIS_EW:
		return (mask & VERTICAL_MASK) == 0
	return (mask & HORIZONTAL_MASK) == 0


static func requires_joint_post(mask: int) -> bool:
	var topology := classify(mask)
	return topology == TYPE_CORNER or topology == TYPE_TEE or topology == TYPE_CROSS


static func connection_signature(mask: int) -> String:
	mask &= ALL_MASK
	var result := ""
	if (mask & NORTH) != 0:
		result += "N"
	if (mask & EAST) != 0:
		result += "E"
	if (mask & SOUTH) != 0:
		result += "S"
	if (mask & WEST) != 0:
		result += "W"
	return result if not result.is_empty() else "NONE"


static func preferred_axis_from_drag(delta_cells: Vector2i, fallback_axis: String = AXIS_EW) -> String:
	if absi(delta_cells.x) > absi(delta_cells.y):
		return AXIS_EW
	if absi(delta_cells.y) > 0:
		return AXIS_NS
	return _normalize_axis(fallback_axis)


static func footprint_cells_for_axis(axis: String, length_cells: int = 1) -> Vector2i:
	length_cells = maxi(length_cells, 1)
	if _normalize_axis(axis) == AXIS_NS:
		return Vector2i(1, length_cells)
	return Vector2i(length_cells, 1)


static func _bit_count(mask: int) -> int:
	var count := 0
	for bit in [NORTH, EAST, SOUTH, WEST]:
		if (mask & bit) != 0:
			count += 1
	return count


static func _normalize_axis(axis: String) -> String:
	return AXIS_NS if axis.to_lower() == AXIS_NS else AXIS_EW
