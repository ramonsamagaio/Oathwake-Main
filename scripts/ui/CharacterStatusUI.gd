extends Control

const CombatCalculatorScript := preload("res://scripts/systems/CombatCalculator.gd")
const PlayerStatsResolverScript := preload("res://scripts/systems/PlayerStatsResolver.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")

var player
var equipment_system
var combat_calculator := CombatCalculatorScript.new()
var stats_resolver := PlayerStatsResolverScript.new()
var value_labels := {}


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func set_equipment_system(new_equipment_system) -> void:
	equipment_system = new_equipment_system


func setup(new_player) -> void:
	player = new_player
	if player != null and player.has_signal("tool_changed"):
		player.tool_changed.connect(_on_player_tool_changed)
	refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if player == null or value_labels.is_empty():
		return

	var actor_data := _get_player_combat_data()
	var held_item_data := _get_held_item_data()
	var derived := combat_calculator.calculate_derived_stats(actor_data, held_item_data)
	var damage_preview := combat_calculator.get_damage_preview(actor_data, held_item_data)
	var base_stats := _get_dictionary(actor_data, "base_stats")

	var total_player_data := stats_resolver.get_total_player_data(player, equipment_system)
	var total_derived := combat_calculator.calculate_derived_stats(total_player_data, held_item_data)
	var total_damage_preview := combat_calculator.get_damage_preview(total_player_data, held_item_data)
	var equip_bonus := stats_resolver.get_equipment_bonus(equipment_system)
	var equip_stats: Dictionary = equip_bonus.get("stats_bonus", {})

	_set_value("Name", str(actor_data.get("display_name", "Player")))
	_set_value("Level", str(actor_data.get("level", "N/A")))
	_set_value("HP", "%d / %d" % [int(player.health), int(player.max_health)])
	_set_value("Tool", player.get_current_tool() if player.has_method("get_current_tool") else "N/A")
	_set_value("Damage Range", "%d - %d (Equipped: %d - %d)" % [
		int(damage_preview.get("min_damage", 0)), int(damage_preview.get("max_damage", 0)),
		int(total_damage_preview.get("min_damage", 0)), int(total_damage_preview.get("max_damage", 0)),
	])
	_set_value("Crit Chance", "%.1f%% (Total: %.1f%%)" % [
		float(derived.get("crit_chance", 0.0)) * 100.0,
		float(total_derived.get("crit_chance", 0.0)) * 100.0,
	])
	_set_value("Crit Damage", "%.2fx (Total: %.2fx)" % [
		float(derived.get("crit_damage", 1.0)),
		float(total_derived.get("crit_damage", 1.0)),
	])
	_set_value("Hit", "%.1f (Total: %.1f)" % [
		float(derived.get("hit", 0.0)), float(total_derived.get("hit", 0.0)),
	])
	_set_value("Flee", "%.1f (Total: %.1f)" % [
		float(derived.get("flee", 0.0)), float(total_derived.get("flee", 0.0)),
	])
	_set_value("Defense", "%.1f (Total: %.1f)" % [
		float(derived.get("defense", 0.0)), float(total_derived.get("defense", 0.0)),
	])
	_set_value("Magic Defense", "%.1f (Total: %.1f)" % [
		float(derived.get("magic_defense", 0.0)), float(total_derived.get("magic_defense", 0.0)),
	])
	_set_value("Max HP Derived", "%.0f (Total: %.0f)" % [
		float(derived.get("max_hp", 0.0)), float(total_derived.get("max_hp", 0.0)),
	])
	_set_value("Physical Attack", "%.1f (Total: %.1f)" % [
		float(derived.get("physical_attack", 0.0)), float(total_derived.get("physical_attack", 0.0)),
	])
	_set_value("Attack Cooldown", "%.2fs (Total: %.2fs)" % [
		float(derived.get("attack_cooldown", 0.0)), float(total_derived.get("attack_cooldown", 0.0)),
	])

	for stat_name in ["str", "dex", "agi", "vit", "wis", "int", "luk"]:
		var base_val := int(base_stats.get(stat_name, 0))
		var equip_val = int(equip_stats.get(stat_name, 0))
		var total_val: int = base_val + equip_val
		_set_value(stat_name.to_upper(), "%d + %d = %d" % [base_val, equip_val, total_val])


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_top = -250.0
	panel.offset_right = 280.0
	panel.offset_bottom = 250.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var title := Label.new()
	title.text = "Character Status"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.62))
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: visible = false)
	header.add_child(close_button)

	_add_separator(layout)
	for field in ["Name", "Level", "HP", "Tool", "Damage Range", "Crit Chance", "Crit Damage", "Hit", "Flee", "Defense", "Magic Defense", "Max HP Derived", "Physical Attack", "Attack Cooldown"]:
		_add_row(layout, field)

	_add_separator(layout)
	var stats_header := Label.new()
	stats_header.text = "Base + Equip = Total"
	stats_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	layout.add_child(stats_header)
	for stat_name in ["STR", "DEX", "AGI", "VIT", "WIS", "INT", "LUK"]:
		_add_row(layout, stat_name)
	_apply_character_status_fonts()


func _add_row(parent: Node, label_text: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)

	var value := Label.new()
	value.text = "N/A"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	value_labels[label_text] = value


func _apply_character_status_fonts() -> void:
	_apply_character_status_fonts_recursive(self)
	if value_labels.has("Name"):
		OathwakeTextStyle.apply_profile_to_label(value_labels["Name"], "player_name")


func _apply_character_status_fonts_recursive(node: Node) -> void:
	if node is Label:
		var label := node as Label
		if label.text == "Character Status" or label.text == "Base + Equip = Total":
			OathwakeTextStyle.apply_profile_to_label(label, "ui_title")
		else:
			OathwakeTextStyle.apply_profile_to_label(label, "base_ui")
	elif node is Button:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "ui_button")

	for child in node.get_children():
		_apply_character_status_fonts_recursive(child)


func _add_separator(parent: Node) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)


func _set_value(field_name: String, value: String) -> void:
	if not value_labels.has(field_name):
		return

	var label: Label = value_labels[field_name]
	label.text = value


func _get_player_combat_data() -> Dictionary:
	if player != null and player.has_method("get_combat_data"):
		return player.get_combat_data()

	return {}


func _get_held_item_data() -> Dictionary:
	if player != null and player.has_method("get_current_held_item_data"):
		return player.get_current_held_item_data()

	return {}


func _get_dictionary(data: Dictionary, key: String) -> Dictionary:
	var value = data.get(key, {})
	if value is Dictionary:
		return value

	return {}


func _on_player_tool_changed(_tool_name: String) -> void:
	refresh()
