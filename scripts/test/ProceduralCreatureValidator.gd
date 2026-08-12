extends SceneTree

const BASE_PATH := "res://scripts/creatures/ProceduralCreature.gd"
const CREATURE_PATHS := [
	"res://scripts/creatures/ProceduralSlime.gd",
	"res://scripts/creatures/ProceduralSnake.gd",
	"res://scripts/creatures/ProceduralWisp.gd",
	"res://scripts/creatures/ProceduralCrawler.gd",
]
const LAB_PATH := "res://scenes/labs/ProceduralCreatureLab.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_check(ResourceLoader.exists(BASE_PATH), "base creature script is missing")
	for path in CREATURE_PATHS:
		_validate_creature(path)

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
	var preset: Dictionary = creature.make_preset()
	_check(String(preset.get("creature_id", "")).length() > 0, "%s preset has no creature_id" % path)
	_check(preset.has("params"), "%s preset has no params" % path)

	var old_scale := float(creature.get_parameter(&"global_scale_factor"))
	_check(creature.set_parameter(&"global_scale_factor", old_scale + 0.1), "%s rejected common parameter" % path)
	_check(float(creature.get_parameter(&"global_scale_factor")) > old_scale, "%s common parameter did not change" % path)

	creature.apply_impulse(Vector2(25.0, -12.0))
	creature.apply_preset(preset)
	_check(creature.random_seed == int(preset.get("seed", creature.random_seed)), "%s preset seed did not restore" % path)

	creature.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
