extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var game_session := root.get_node_or_null("GameSession")
	var slot_manager := root.get_node_or_null("SaveSlotManager")
	if game_session == null or slot_manager == null:
		_fail("required save autoloads are missing")
		return

	# Use the two non-default slots so this test catches the historical silent
	# fallback to slot_1. CI's user:// directory is disposable.
	if not bool(game_session.call("start_new_session", "slot_2", "IsolationA", "WorldA", {})):
		_fail("could not create slot_2 session")
		return
	var world_a := str(game_session.get("active_world_id"))
	var player_a := str(game_session.get("active_player_id"))
	var world_data_a: Dictionary = (game_session.get("world_data") as Dictionary).duplicate(true)
	if str(slot_manager.call("get_active_slot")) != "slot_2":
		_fail("legacy SaveSlotManager did not follow slot_2")
		return
	if world_a.is_empty() or player_a.is_empty():
		_fail("slot_2 did not receive independent player/world ids")
		return

	if not bool(game_session.call("start_new_session", "slot_3", "IsolationB", "WorldB", {})):
		_fail("could not create slot_3 session")
		return
	var world_b := str(game_session.get("active_world_id"))
	var player_b := str(game_session.get("active_player_id"))
	var world_data_b: Dictionary = (game_session.get("world_data") as Dictionary).duplicate(true)
	if str(slot_manager.call("get_active_slot")) != "slot_3":
		_fail("legacy SaveSlotManager did not follow slot_3")
		return
	if world_b.is_empty() or player_b.is_empty():
		_fail("slot_3 did not receive independent player/world ids")
		return
	if world_a == world_b:
		_fail("two new games shared one world id")
		return
	if player_a == player_b:
		_fail("two new games shared one player id")
		return
	if int(world_data_a.get("seed", 0)) <= 0 or int(world_data_b.get("seed", 0)) <= 0:
		_fail("new procedural world seed is invalid")
		return

	var state_a: Variant = (world_data_a.get("player_states", {}) as Dictionary).get(player_a, {})
	var state_b: Variant = (world_data_b.get("player_states", {}) as Dictionary).get(player_b, {})
	if not state_a is Dictionary or not state_b is Dictionary:
		_fail("world-specific initial player state was not created")
		return

	print("OATHWAKE_SESSION_ISOLATION_OK slot2=%s slot3=%s worlds_independent=true legacy_slot_sync=true" % [world_a, world_b])
	quit(0)

func _fail(message: String) -> void:
	push_error("OATHWAKE_SESSION_ISOLATION_FAIL %s" % message)
	quit(1)
