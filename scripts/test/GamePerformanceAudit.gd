extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("performance_audit_%d" % Time.get_ticks_usec(), "Audit Hero", "Performance Audit")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _index in range(120):
		await process_frame

	var stats := {
		"nodes": 0,
		"processing": 0,
		"physics_processing": 0,
		"canvas_items": 0,
		"visible_canvas_items": 0,
		"tilemap_layers": 0,
		"multimesh_instances": 0,
		"point_lights": 0,
		"directional_lights": 0,
		"projected_shadows": 0,
		"resources": 0,
		"areas_monitoring": 0,
		"particles": 0,
	}
	var process_scripts := {}
	var physics_scripts := {}
	_audit_node(root, stats, process_scripts, physics_scripts)
	print("GAME_PERFORMANCE_AUDIT stats=%s process_ms=%.3f physics_ms=%.3f objects=%d draw_calls=%d primitives=%d" % [
		stats,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])
	print("GAME_PERFORMANCE_AUDIT process_top=" + str(_top_counts(process_scripts, 15)))
	print("GAME_PERFORMANCE_AUDIT physics_top=" + str(_top_counts(physics_scripts, 15)))
	var pinned_paths: Array[String] = []
	_collect_processing_paths(root, "PinnedActiveFrameProjectedShadow.gd", pinned_paths)
	print("GAME_PERFORMANCE_AUDIT pinned_samples=" + str(pinned_paths.slice(0, mini(12, pinned_paths.size()))))
	var visible_classes := {}
	var visible_branches := {}
	_collect_visible_canvas_counts(root, visible_classes, visible_branches)
	print("GAME_PERFORMANCE_AUDIT visible_classes=" + str(_top_counts(visible_classes, 12)))
	print("GAME_PERFORMANCE_AUDIT visible_branches=" + str(_top_counts(visible_branches, 12)))
	var romestead_environment := game.get_node_or_null("Systems/RomesteadEnvironment")
	if romestead_environment != null and romestead_environment.has_method("get_runtime_performance_diagnostics"):
		print("GAME_PERFORMANCE_AUDIT runtime_scheduler=" + str(romestead_environment.call("get_runtime_performance_diagnostics")))
	quit(0)


func _audit_node(node: Node, stats: Dictionary, process_scripts: Dictionary, physics_scripts: Dictionary) -> void:
	stats["nodes"] = int(stats["nodes"]) + 1
	if node is CanvasItem:
		stats["canvas_items"] = int(stats["canvas_items"]) + 1
		if (node as CanvasItem).is_visible_in_tree():
			stats["visible_canvas_items"] = int(stats["visible_canvas_items"]) + 1
	if node is TileMapLayer:
		stats["tilemap_layers"] = int(stats["tilemap_layers"]) + 1
	if node is MultiMeshInstance2D:
		stats["multimesh_instances"] = int(stats["multimesh_instances"]) + 1
	if node is PointLight2D:
		stats["point_lights"] = int(stats["point_lights"]) + 1
	if node is DirectionalLight2D:
		stats["directional_lights"] = int(stats["directional_lights"]) + 1
	if node is Area2D and (node as Area2D).monitoring:
		stats["areas_monitoring"] = int(stats["areas_monitoring"]) + 1
	if node is GPUParticles2D or node is CPUParticles2D:
		stats["particles"] = int(stats["particles"]) + 1
	if node.is_in_group("projected_shadow_caster"):
		stats["projected_shadows"] = int(stats["projected_shadows"]) + 1
	if node.is_in_group("resource_node"):
		stats["resources"] = int(stats["resources"]) + 1
	var script_path := "<native>"
	var script := node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		script_path = script.resource_path
	if node.is_processing():
		stats["processing"] = int(stats["processing"]) + 1
		process_scripts[script_path] = int(process_scripts.get(script_path, 0)) + 1
	if node.is_physics_processing():
		stats["physics_processing"] = int(stats["physics_processing"]) + 1
		physics_scripts[script_path] = int(physics_scripts.get(script_path, 0)) + 1
	for child in node.get_children():
		_audit_node(child, stats, process_scripts, physics_scripts)


func _top_counts(counts: Dictionary, limit: int) -> Array:
	var rows: Array = []
	for key in counts:
		rows.append({"script": key, "count": counts[key]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	return rows.slice(0, mini(limit, rows.size()))


func _collect_processing_paths(node: Node, script_suffix: String, paths: Array[String]) -> void:
	var script := node.get_script() as Script
	if node.is_processing() and script != null and script.resource_path.ends_with(script_suffix):
		var source_type := "unknown"
		if node.has_method("get_shadow_source"):
			var source: Variant = node.call("get_shadow_source")
			if source != null:
				source_type = (source as Object).get_class()
		paths.append("%s source=%s" % [str(node.get_path()), source_type])
	for child in node.get_children():
		_collect_processing_paths(child, script_suffix, paths)


func _collect_visible_canvas_counts(node: Node, classes: Dictionary, branches: Dictionary) -> void:
	if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
		var class_name_value := node.get_class()
		classes[class_name_value] = int(classes.get(class_name_value, 0)) + 1
		var path := str(node.get_path())
		var branch := "Other"
		for candidate in ["Resources", "RomesteadProceduralGameWorld", "UI", "RuntimeEntities", "Buildings", "WorldPostEffects", "WeatherLayer"]:
			if path.contains("/%s/" % candidate) or path.ends_with("/%s" % candidate):
				branch = candidate
				break
		branches[branch] = int(branches.get(branch, 0)) + 1
	for child in node.get_children():
		_collect_visible_canvas_counts(child, classes, branches)
