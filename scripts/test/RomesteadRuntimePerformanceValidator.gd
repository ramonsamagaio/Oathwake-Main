extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("runtime_perf_%d" % Time.get_ticks_usec(), "Runtime Perf", "Runtime Perf")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _frame in range(24):
		await process_frame

	var environment := game.get_node_or_null("Systems/RomesteadEnvironment")
	_check(environment != null, "Romestead environment controller exists")
	var diagnostics: Dictionary = {}
	if environment != null and environment.has_method("get_runtime_performance_diagnostics"):
		diagnostics = environment.call("get_runtime_performance_diagnostics") as Dictionary
	_check(bool(diagnostics.get("scheduler_enabled", false)), "chunked runtime scheduler is enabled")
	_check(bool(diagnostics.get("world_process_disabled", false)), "legacy all-world process loop is disabled")
	_check(int(diagnostics.get("pending_chunks", 0)) > 0, "offscreen resources are indexed into stream chunks")
	_check(int(diagnostics.get("pending_resources", 0)) > 0, "offscreen resources remain data until needed")
	_check(int(diagnostics.get("active_resources", 0)) > 0, "nearby resources are active")

	var resources: Node = game.current_map.get_resources_root()
	var idle_resources := 0
	for resource in resources.get_children():
		if resource.is_processing() and resource.has_method("is_collected") and not bool(resource.call("is_collected")):
			idle_resources += 1
	_check(idle_resources == 0, "uncollected resource nodes have no individual idle callback")

	var streamed_before := int(diagnostics.get("streamed_resources", 0))
	var pending_before := int(diagnostics.get("pending_resources", 0))
	var player := game.player as Node2D
	player.global_position += Vector2(1152.0, 0.0)
	for _frame in range(36):
		await process_frame
	if environment != null and environment.has_method("get_runtime_performance_diagnostics"):
		diagnostics = environment.call("get_runtime_performance_diagnostics") as Dictionary
	var streamed_after := int(diagnostics.get("streamed_resources", 0))
	var pending_after := int(diagnostics.get("pending_resources", 0))
	_check(streamed_after > streamed_before or pending_after < pending_before, "camera travel streams only nearby reserved resources")
	_check(int(diagnostics.get("active_resources", 0)) > 0, "active resource set survives camera travel")

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("ROMESTEAD_RUNTIME_PERFORMANCE_VALIDATION: PASS diagnostics=%s" % diagnostics)
		quit(0)
	else:
		push_error("ROMESTEAD_RUNTIME_PERFORMANCE_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
