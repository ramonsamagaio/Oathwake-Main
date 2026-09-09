extends Node
## Keeps the cheap single-polygon ocean but feeds it the original Romestead
## water texture instead of generating FBM/noise over the whole visible sea.

const WATER_TEXTURE_PATH := "res://assets/world_lab/romestead_native_png/sources/rendering/water.png"

var _water_texture: Texture2D
var _applied_to: Polygon2D


func _ready() -> void:
	process_priority = 925
	_water_texture = load(WATER_TEXTURE_PATH) as Texture2D
	if _water_texture == null:
		push_warning("RomesteadNativeWaterRestore: native water texture is missing.")
		set_process(false)
		return
	call_deferred("_try_apply")


func _process(_delta: float) -> void:
	if _applied_to == null or not is_instance_valid(_applied_to):
		_try_apply()


func _try_apply() -> void:
	if _water_texture == null:
		return
	var world := get_tree().get_first_node_in_group("procedural_resource_world")
	if world == null:
		return
	var backdrop := world.get_node_or_null("OceanBackdrop") as Polygon2D
	if backdrop == null:
		return
	if backdrop == _applied_to and backdrop.texture == _water_texture:
		return
	backdrop.texture = _water_texture
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_applied_to = backdrop
