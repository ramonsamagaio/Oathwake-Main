extends RefCounted

const DEFAULT_TERRAIN_TYPE := "grass"
const TERRAIN_TYPE_CUSTOM_DATA := "terrain_type"


func get_tile_type_at_position(ground_layer: TileMapLayer, global_position: Vector2) -> String:
	if ground_layer == null:
		return DEFAULT_TERRAIN_TYPE

	var local_position := ground_layer.to_local(global_position)
	var tile_position := ground_layer.local_to_map(local_position)
	var tile_data := ground_layer.get_cell_tile_data(tile_position)
	if tile_data == null:
		return DEFAULT_TERRAIN_TYPE

	if _has_custom_data_layer(ground_layer.tile_set, TERRAIN_TYPE_CUSTOM_DATA):
		var terrain_type = tile_data.get_custom_data(TERRAIN_TYPE_CUSTOM_DATA)
		if terrain_type is String and not terrain_type.is_empty():
			return terrain_type

	# The temporary runtime TileSet does not define terrain custom data yet.
	# When map art/biomes are introduced, set custom data "terrain_type" on real tiles.
	if ground_layer.get_cell_source_id(tile_position) != -1:
		return DEFAULT_TERRAIN_TYPE

	return DEFAULT_TERRAIN_TYPE


func _has_custom_data_layer(tile_set: TileSet, layer_name: String) -> bool:
	if tile_set == null:
		return false

	for layer_index in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(layer_index) == layer_name:
			return true

	return false
