extends Node

const MANAGER_PATH := "/root/MultiFloorBuildManager"
const REQUIRED_STABLE_FRAMES := 6

var _stable_context_frames := 0
var _bootstrap_pending := false
var _label_cleanup_pending := false


func _ready() -> void:
	# Runs before the floor manager so stale scene references are neutralized first.
	process_priority = -1000


func _process(_delta: float) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null:
		return

	var active_build_system := get_tree().get_first_node_in_group("build_system")
	var bound_build_system: Variant = manager.get("_build_system")
	var initialized := bool(manager.get("_initialized"))

	if initialized and (
		active_build_system == null
		or not is_instance_valid(bound_build_system)
		or bound_build_system != active_build_system
	):
		_reset_manager_context(manager)
		initialized = false

	if active_build_system == null or initialized:
		_stable_context_frames = 0
	else:
		_stable_context_frames += 1
		if _stable_context_frames >= REQUIRED_STABLE_FRAMES and not _bootstrap_pending:
			_bootstrap_pending = true
			call_deferred("_bootstrap_manager")

	if initialized and not _label_cleanup_pending:
		_label_cleanup_pending = true
		call_deferred("_cleanup_generated_build_menu_entry")


func _bootstrap_manager() -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager != null and not bool(manager.get("_initialized")):
		manager.call_deferred("_bootstrap")

	# The manager waits two frames internally. Give it enough room before retrying.
	for _frame in range(5):
		await get_tree().process_frame
	_bootstrap_pending = false
	_stable_context_frames = 0


func _reset_manager_context(manager: Node) -> void:
	manager.set("_initialized", false)
	manager.set("_build_system", null)
	manager.set("_main", null)
	manager.set("_player", null)
	manager.set("_build_layer", null)
	manager.set("_obstacle_layer", null)
	manager.set("_resources_root", null)
	manager.set("_enemies_root", null)
	manager.set("_npcs_root", null)
	manager.set("_build_label", null)
	manager.set("_connected_save_button", null)
	manager.set("_connected_load_button", null)
	_stable_context_frames = 0
	_bootstrap_pending = false


func _cleanup_generated_build_menu_entry() -> void:
	_label_cleanup_pending = false
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null or not bool(manager.get("_initialized")):
		return
	var build_label := manager.get("_build_label") as Label
	if build_label == null:
		return

	var cleaned := PackedStringArray()
	for line in build_label.text.split("\n"):
		if str(line) == "? Stairs Down":
			continue
		cleaned.append(str(line))
	build_label.text = "\n".join(cleaned)
