extends SceneTree

const BASE_PATH := "res://scripts/creatures/ProceduralCreature.gd"
const CREATURE_PATHS := [
	"res://scripts/creatures/ProceduralSlime.gd",
	"res://scripts/creatures/ProceduralSnake.gd",
	"res://scripts/creatures/ProceduralWisp.gd",
	"res://scripts/creatures/ProceduralCrawler.gd",
]
const VISUAL_SHADER_PATHS := [
	"res://shaders/creatures/procedural_palette_pixel.gdshader",
	"res://shaders/creatures/slime_gel_pixel.gdshader",
	"res://shaders/creatures/snake_scale_pixel.gdshader",
]
const LAB_PATH := "res://scenes/labs/ProceduralCreatureLab.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_check(ResourceLoader.exists(BASE_PATH), "base creature script is missing")
	for shader_path_value: Variant in VISUAL_SHADER_PATHS:
		var shader_path: String = String(shader_path_value)
		_check(ResourceLoader.exists(shader_path), "%s is missing" % shader_path)
	for path_value: Variant in CREATURE_PATHS:
		_validate_creature(String(path_value))

	var lab_resource := load(LAB_PATH) as PackedScene
	_check(lab_resource != null, "lab scene failed to load")
	if lab_resource != null:
		var lab := lab_resource.instantiate()
		root.add_child(lab)
		await process_frame
		await process_frame
		_check(lab.get_node_or_null("LODAnchor") != null, "lab did not create its LOD anchor")
		lab.queue_free()
		await process_frame

	if _failures.is_empty():
		print("PROCEDURAL_CREATURE_VALIDATION_OK")
		quit(0)
		return

	for failure in _failures:
		push_error("PROCEDURAL_CREATURE_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_creature(path: String) -> void:
	var script := load(path) as Script
	_check(script != null, "%s failed to load" % path)
	if script == null:
		return

	var creature: Variant = script.new()
	_check(creature != null, "%s failed to instantiate" % path)
	if creature == null:
		return
	root.add_child(creature)
	creature.set_simulation_active(false)

	var schema: Array = creature.get_editor_schema()
	_check(not schema.is_empty(), "%s exposes no editor parameters" % path)
	var exposes_pixel_size := false
	var exposes_palette_banding := false
	var exposes_pixel_material := false
	for descriptor_value: Variant in schema:
		if descriptor_value is Dictionary:
			var descriptor: Dictionary = descriptor_value as Dictionary
			var descriptor_key: StringName = StringName(descriptor.get("key", &""))
			if descriptor_key == &"pixel_size":
				exposes_pixel_size = true
			elif descriptor_key == &"palette_band_strength":
				exposes_palette_banding = true
			elif descriptor_key == &"material_detail_strength":
				exposes_pixel_material = true
	_check(not exposes_pixel_size, "%s exposes forbidden pixel_size authoring control" % path)
	_check(exposes_palette_banding, "%s has no palette banding authoring control" % path)
	_check(exposes_pixel_material, "%s has no pixel material authoring control" % path)

	# Pixel-perfect rendering is a hard engine contract: one source pixel is
	# always one rendered pixel. Older presets may still contain pixel_size, but
	# attempting to change it must be harmless and must never alter the unit.
	_check(int(creature.get_parameter(&"pixel_size")) == 1, "%s pixel unit is not fixed at 1" % path)
	_check(creature.set_parameter(&"pixel_size", 6), "%s rejected legacy pixel_size compatibility key" % path)
	_check(int(creature.get_parameter(&"pixel_size")) == 1, "%s allowed pixel_size to change" % path)

	# Every creature now owns a CanvasItem ShaderMaterial. Slime and Snake may
	# replace the generic palette shader with specialized pixel-native variants.
	var shader_material: ShaderMaterial = creature.material as ShaderMaterial
	_check(shader_material != null, "%s has no ShaderMaterial visual pipeline" % path)
	if shader_material != null:
		_check(shader_material.shader != null, "%s ShaderMaterial has no shader" % path)

	var preset: Dictionary = creature.make_preset()
	_check(String(preset.get("creature_id", "")).length() > 0, "%s preset has no creature_id" % path)
	_check(preset.has("params"), "%s preset has no params" % path)
	var preset_params: Dictionary = preset.get("params", {}) as Dictionary
	_check(not preset_params.has("pixel_size"), "%s persists forbidden pixel_size parameter" % path)
	_check(preset_params.has("palette_band_strength"), "%s preset omits palette banding" % path)
	_check(preset_params.has("material_detail_strength"), "%s preset omits pixel material strength" % path)

	var creature_id: String = String(creature.creature_id)
	if creature_id == "slime":
		_check(int(creature.get_parameter(&"point_count")) >= 24, "slime surface mesh is too coarse")
		_check(int(creature.get_parameter(&"render_subdivisions")) >= 2, "slime render contour lacks subdivision")
		_check(float(creature.get_parameter(&"internal_layer_strength")) > 0.0, "slime internal membranes are disabled")
	elif creature_id == "snake":
		_check(int(creature.get_parameter(&"segment_count")) >= 20, "snake control ribbon is too coarse")
		_check(float(creature.get_parameter(&"dorsal_pattern_strength")) > 0.0, "snake dorsal pattern is disabled")

	var old_scale := float(creature.get_parameter(&"global_scale_factor"))
	_check(creature.set_parameter(&"global_scale_factor", old_scale + 0.1), "%s rejected common parameter" % path)
	_check(float(creature.get_parameter(&"global_scale_factor")) > old_scale, "%s common parameter did not change" % path)

	creature.apply_impulse(Vector2(25.0, -12.0))
	creature.apply_preset(preset)
	_check(creature.random_seed == int(preset.get("seed", creature.random_seed)), "%s preset seed did not restore" % path)
	_check(int(creature.get_parameter(&"pixel_size")) == 1, "%s preset application changed pixel unit" % path)

	creature.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
