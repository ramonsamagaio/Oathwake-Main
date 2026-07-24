@tool
class_name OathwakeTerrainLayer
extends TileMapLayer

const EXPECTED_TILE_SIZE := Vector2i(64, 64)
const DEFAULT_TILE_SET: TileSet = preload("res://tilesets/terrain/terrain_grass_dirt_tileset.tres")
const DEFAULT_MATERIAL: ShaderMaterial = preload("res://materials/terrain/terrain_grass_dirt_material.tres")

@export_category("Oathwake Terrain")
@export var auto_configure := true
@export var warn_on_invalid_configuration := true

func _enter_tree() -> void:
    if auto_configure:
        call_deferred("_ensure_configuration")

func _ready() -> void:
    if auto_configure:
        _ensure_configuration()

func _ensure_configuration() -> void:
    if tile_set == null:
        tile_set = DEFAULT_TILE_SET
    if material == null:
        material = DEFAULT_MATERIAL

    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

    if warn_on_invalid_configuration:
        _validate_configuration()

func _validate_configuration() -> void:
    if tile_set == null:
        push_warning("OathwakeTerrainLayer requires a TileSet.")
        return
    if tile_set.tile_size != EXPECTED_TILE_SIZE:
        push_warning(
            "OathwakeTerrainLayer expects %s terrain tiles, received %s." % [
                EXPECTED_TILE_SIZE,
                tile_set.tile_size,
            ]
        )
    if material == null or not material is ShaderMaterial:
        push_warning("OathwakeTerrainLayer expects the grass/dirt world-space ShaderMaterial.")
