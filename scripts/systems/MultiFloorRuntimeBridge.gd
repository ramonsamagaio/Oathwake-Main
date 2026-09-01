extends Node

const MANAGER_PATH := "/root/MultiFloorBuildManager"
const REQUIRED_STABLE_FRAMES := 6
const EDIT_SAVE_DEBOUNCE_SEC := 0.35

var _stable_context_frames := 0
var _bootstrap_pending := false
var _label_cleanup_pending := false
var _save_sync_pending := false


func _ready() -> void:
	process_priority = -1000


func _process(_delta: float) -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null:
		return

	var active_build_system := get_tree().get_first_node_in_group("build_system")
	var bound_build_system: Variant = manager.get("_build_system")
	var initialized := bool(manager.get("_initialized"))
	if initialized and (active_build_system == null or not is_instance_valid(bound_build_system) or bound_build_system != active_build_system):
		_reset_manager_context(manager)
		initialized = false

	if active_build_system == null or initialized:
		_stable_context_frames = 0
	else:
		_stable_context_frames += 1
		if _stable_context_frames >= REQUIRED_STABLE_FRAMES and not _bootstrap_pending:
			_bootstrap_pending = true
			call_deferred("_bootstrap_manager")

	if initialized:
		_connect_manager_signals(manager)
		if not _label_cleanup_pending:
			_label_cleanup_pending = true
			call_deferred("_cleanup_generated_build_menu_entry")


func _bootstrap_manager() -> void:
	var manager := get_node_or_null(MANAGER_PATH)
	var build_system := get_tree().get_first_node_in_group("build_system")
	if build_system != null:
		_ensure_complete_save_exists(build_system)
	if manager != null and not bool(manager.get("_initialized")):
		manager.call_deferred("_bootstrap")
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
	manager.set("_ground_layer", null)
	manager.set("_obstacle_layer", null)
	manager.set("_resources_root", null)
	manager.set("_enemies_root", null)
	manager.set("_npcs_root", null)
	manager.set("_build_label", null)
	manager.set("_surface_visual_root", null)
	manager.set("_lower_floor_visual_root", null)
	manager.set("_lower_floor_dim_visual", null)
	manager.set("_empty_obstacle_layer", null)
	manager.set("_stair_use_cooldown", 0.0)
	manager.set("_connected_save_button", null)
	manager.set("_connected_load_button", null)
	_stable_context_frames = 0
	_bootstrap_pending = false
	_save_sync_pending = false


func _connect_manager_signals(manager: Node) -> void:
	var floor_changed_callback := Callable(self, "_on_floor_changed")
	if not manager.is_connected("floor_changed", floor_changed_callback):
		manager.connect("floor_changed", floor_changed_callback)
	var floor_data_callback := Callable(self, "_on_floor_data_changed")
	if not manager.is_connected("floor_data_changed", floor_data_callback):
		manager.connect("floor_data_changed", floor_data_callback)


func _on_floor_changed(_previous_floor: int, _current_floor: int) -> void:
	# MultiFloorBuildManager has already captured and persisted its lightweight
	# floor state before this signal. A second full Main/GameSession save here was
	# doing disk IO and world serialization in the exact frame the player stepped
	# on a stair, producing the very large hitch seen in gameplay.
	pass


func _on_floor_data_changed(_floor_index: int) -> void:
	# Building edits still need to reach the complete save document, but they do
	# not need to block the edit frame. Coalesce bursts and save after the scene
	# has had time to settle.
	_queue_full_save_sync()


func _queue_full_save_sync() -> void:
	if _save_sync_pending:
		return
	_save_sync_pending = true
	call_deferred("_synchronize_complete_save")


func _synchronize_complete_save() -> void:
	await get_tree().create_timer(EDIT_SAVE_DEBOUNCE_SEC, true, false, true).timeout
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null or not bool(manager.get("_initialized")):
		_save_sync_pending = false
		return
	var main := manager.get("_main") as Node
	if main != null and main.has_method("save_game"):
		main.call("save_game")
		await get_tree().process_frame
	if manager.has_method("save_now"):
		manager.call("save_now")
	_save_sync_pending = false


func _ensure_complete_save_exists(build_system: Node) -> void:
	var slot_manager := get_node_or_null("/root/SaveSlotManager")
	if slot_manager == null or not slot_manager.has_method("get_active_save_path"):
		return
	var save_path := str(slot_manager.call("get_active_save_path"))
	if save_path.is_empty() or FileAccess.file_exists(save_path):
		return
	var main := build_system.get("main") as Node
	if main != null and main.has_method("save_game"):
		main.call("save_game")


func _cleanup_generated_build_menu_entry() -> void:
	_label_cleanup_pending = false
	var manager := get_node_or_null(MANAGER_PATH)
	if manager == null or not bool(manager.get("_initialized")):
		return
	var build_label := manager.get("_build_label") as Label
	if build_label != null:
		build_label.visible = false
