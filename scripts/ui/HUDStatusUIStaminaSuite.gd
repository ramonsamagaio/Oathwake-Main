extends "res://scripts/ui/HUDStatusUI.gd"

var _bound_stamina_player: Node
var _stamina_bind_retry_left := 0.0

func _ready() -> void:
	super._ready()
	add_to_group("hud_status_ui")
	call_deferred("_bind_player_stamina")
	set_process(true)

func _process(delta: float) -> void:
	if _bound_stamina_player != null and is_instance_valid(_bound_stamina_player):
		return
	_stamina_bind_retry_left = maxf(_stamina_bind_retry_left - delta, 0.0)
	if _stamina_bind_retry_left <= 0.0:
		_stamina_bind_retry_left = 0.25
		_bind_player_stamina()

func _exit_tree() -> void:
	_unbind_player_stamina()

func _bind_player_stamina() -> void:
	var candidate := get_tree().get_first_node_in_group("player")
	if candidate == null or not is_instance_valid(candidate):
		return
	if _bound_stamina_player == candidate:
		_sync_stamina_from_player()
		return
	_unbind_player_stamina()
	_bound_stamina_player = candidate
	var callback := Callable(self, "_on_player_stamina_changed")
	if candidate.has_signal("stamina_changed") and not candidate.is_connected("stamina_changed", callback):
		candidate.connect("stamina_changed", callback)
	_sync_stamina_from_player()

func _unbind_player_stamina() -> void:
	if _bound_stamina_player == null or not is_instance_valid(_bound_stamina_player):
		_bound_stamina_player = null
		return
	var callback := Callable(self, "_on_player_stamina_changed")
	if _bound_stamina_player.has_signal("stamina_changed") and _bound_stamina_player.is_connected("stamina_changed", callback):
		_bound_stamina_player.disconnect("stamina_changed", callback)
	_bound_stamina_player = null

func _sync_stamina_from_player() -> void:
	if _bound_stamina_player == null or not is_instance_valid(_bound_stamina_player):
		return
	var current := float(_bound_stamina_player.get_meta("current_stamina", 100.0))
	var maximum := float(_bound_stamina_player.get_meta("max_stamina", 100.0))
	if _bound_stamina_player.has_method("get_current_stamina"):
		current = float(_bound_stamina_player.call("get_current_stamina"))
	if _bound_stamina_player.has_method("get_max_stamina"):
		maximum = float(_bound_stamina_player.call("get_max_stamina"))
	_on_player_stamina_changed(current, maximum)

func _on_player_stamina_changed(current_stamina: float, maximum_stamina: float) -> void:
	var safe_maximum := maxf(maximum_stamina, 1.0)
	set_stamina(roundi(current_stamina), roundi(safe_maximum))
	set_meta("hud_stamina_current", current_stamina)
	set_meta("hud_stamina_maximum", safe_maximum)
	set_meta("hud_stamina_ratio", clampf(current_stamina / safe_maximum, 0.0, 1.0))

func get_displayed_stamina_ratio() -> float:
	return float(get_meta("hud_stamina_ratio", 1.0))

func get_bound_stamina_player() -> Node:
	return _bound_stamina_player if _bound_stamina_player != null and is_instance_valid(_bound_stamina_player) else null
