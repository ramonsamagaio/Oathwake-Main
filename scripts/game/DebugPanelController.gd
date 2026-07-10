## Updates legacy debug labels and visibility without owning gameplay state.
class_name DebugPanelController
extends Node

var labels: Dictionary = {}
var panels: Array[CanvasItem] = []
var hud_status_ui: Control
var is_visible := false


func setup(context: Dictionary) -> void:
	labels = context.get("labels", {})
	panels = context.get("panels", [])
	hud_status_ui = context.get("hud_status_ui") as Control


func set_debug_visible(visible_state: bool) -> void:
	is_visible = visible_state
	for node in panels:
		if node != null:
			node.visible = visible_state
	if not visible_state:
		_set_visible("player_stats_panel", false)
		_set_visible("monster_spawn_panel", false)


func set_resource_counts(wood_name: String, wood: int, stone_name: String, stone: int, gel_name: String, gel: int) -> void:
	_set_text("wood", "%s: %d" % [wood_name, wood])
	_set_text("stone", "%s: %d" % [stone_name, stone])
	_set_text("gel", "%s: %d" % [gel_name, gel])


func set_health(current_health: int, max_health: int) -> void:
	_set_text("health", "Health: %d/%d" % [current_health, max_health])
	if hud_status_ui != null and hud_status_ui.has_method("set_health"):
		hud_status_ui.set_health(current_health, max_health)


func set_xp(current_xp: int, xp_to_next_level: int, level: int) -> void:
	_set_text("xp", "LV %d | XP %d/%d" % [level, current_xp, xp_to_next_level])
	if hud_status_ui != null and hud_status_ui.has_method("set_xp"):
		hud_status_ui.set_xp(current_xp, xp_to_next_level, level)


func set_current_tool(tool_name: String) -> void:
	_set_text("tool", "Tool: %s" % tool_name)
	if hud_status_ui != null and hud_status_ui.has_method("set_current_tool"):
		hud_status_ui.set_current_tool(tool_name)


func set_settlement(villagers: int, houses: int, housed: int) -> void:
	_set_text("villagers", "Villagers: %d" % villagers)
	_set_text("houses", "Houses: %d" % houses)
	_set_text("housed_villagers", "Housed Villagers: %d/%d" % [housed, villagers])


func _set_text(key: String, value: String) -> void:
	var label := labels.get(key) as Label
	if label != null:
		label.text = value


func _set_visible(key: String, visible_state: bool) -> void:
	var node := labels.get(key) as CanvasItem
	if node != null:
		node.visible = visible_state
