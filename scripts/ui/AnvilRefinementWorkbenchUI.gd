extends "res://scripts/ui/WorkbenchUISafe.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")

var refinement_calculator := RefinementCalculatorScript.new()
var refine_tab_button: Button
var refine_body: VBoxContainer
var refine_list: ItemList
var refine_detail_label: Label
var refine_cost_label: Label
var refine_message_label: Label
var refine_button: Button
var selected_refinement_key := ""


func _ready() -> void:
	super._ready()
	_build_refinement_extension()
	_update_refinement_availability()


func open(workstation_id := "workbench") -> void:
	super.open(workstation_id)
	_update_refinement_availability()
	if current_workstation_id != "anvil" and current_tab == "refine":
		_switch_tab("craft")


func refresh() -> void:
	if current_tab == "refine":
		if current_workstation_id != "anvil":
			current_tab = "craft"
			_sync_tab_visibility()
			super.refresh()
			return
		_refresh_refinement_list()
		_refresh_refinement_details()
		return
	super.refresh()


func _switch_tab(tab: String) -> void:
	if tab != "refine":
		super._switch_tab(tab)
		if refine_body != null:
			refine_body.visible = false
		_update_refinement_availability()
		return

	if current_workstation_id != "anvil":
		return
	current_tab = "refine"
	last_message = ""
	_sync_tab_visibility()
	refresh()


func _build_refinement_extension() -> void:
	if craft_tab_button == null or craft_body == null:
		return
	var tabs := craft_tab_button.get_parent()
	var root := craft_body.get_parent()
	if tabs == null or root == null:
		return

	refine_tab_button = Button.new()
	refine_tab_button.text = "Refine"
	refine_tab_button.focus_mode = Control.FOCUS_NONE
	refine_tab_button.pressed.connect(_switch_tab.bind("refine"))
	tabs.add_child(refine_tab_button)

	refine_body = VBoxContainer.new()
	refine_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refine_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(refine_body)

	var title := Label.new()
	title.text = "Anvil Refinement"
	refine_body.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	refine_body.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	refine_list = ItemList.new()
	refine_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refine_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	refine_list.item_selected.connect(_on_refinement_item_selected)
	left.add_child(refine_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	refine_detail_label = Label.new()
	refine_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refine_detail_label.custom_minimum_size = Vector2(0, 175)
	right.add_child(refine_detail_label)

	refine_cost_label = Label.new()
	refine_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refine_cost_label.custom_minimum_size = Vector2(0, 120)
	right.add_child(refine_cost_label)

	refine_button = Button.new()
	refine_button.text = "Refine"
	refine_button.focus_mode = Control.FOCUS_NONE
	refine_button.disabled = true
	refine_button.pressed.connect(_on_refine_pressed)
	right.add_child(refine_button)

	refine_message_label = Label.new()
	refine_message_label.text = ""
	right.add_child(refine_message_label)
	refine_body.visible = false


func _sync_tab_visibility() -> void:
	var refining := current_tab == "refine"
	craft_tab_button.disabled = current_tab == "craft"
	repair_tab_button.disabled = current_tab == "repair"
	if refine_tab_button != null:
		refine_tab_button.disabled = refining or current_workstation_id != "anvil"
	craft_body.visible = current_tab == "craft"
	repair_body.visible = current_tab == "repair"
	if refine_body != null:
		refine_body.visible = refining


func _update_refinement_availability() -> void:
	if refine_tab_button == null:
		return
	var available := current_workstation_id == "anvil"
	refine_tab_button.visible = available
	refine_tab_button.disabled = not available or current_tab == "refine"
	if not available and refine_body != null:
		refine_body.visible = false


func _refresh_refinement_list() -> void:
	if refine_list == null:
		return
	refine_list.clear()
	var entries := _get_refinable_items()
	var selected_index := -1
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var slot: Dictionary = entry.get("slot", {})
		var item_id := str(slot.get("item_id", ""))
		var item_data := _get_item_data(item_id)
		var level := RefinementCalculatorScript.get_refinement_level(slot)
		var max_level := refinement_calculator.get_max_refinement_level(slot)
		var name := RefinementCalculatorScript.get_refined_display_name(item_data, slot)
		var status := " MAX" if level >= max_level else ""
		var source_label := "Equipped" if str(entry.get("source", "")) == "equipment" else "Inventory"
		refine_list.add_item("T%d %s [%s]%s" % [int(item_data.get("tier", 1)), name, source_label, status], sprite_resolver.get_texture_for_item(item_id))
		refine_list.set_item_metadata(index, entry)
		if str(entry.get("key", "")) == selected_refinement_key:
			selected_index = index

	if selected_index >= 0:
		refine_list.select(selected_index)
	elif not entries.is_empty():
		refine_list.select(0)
		selected_refinement_key = str((entries[0] as Dictionary).get("key", ""))


func _get_refinable_items() -> Array:
	var entries: Array = []
	if main == null or main.get("inventory") == null:
		return entries

	var inventory = main.inventory
	for index in range(int(inventory.get_slot_count())):
		var slot: Dictionary = inventory.get_slot(index)
		if not refinement_calculator.is_refinable(slot):
			continue
		entries.append({
			"key": "inventory:%d" % index,
			"source": "inventory",
			"index": index,
			"slot": slot.duplicate(true),
		})

	var equipment_system = _get_equipment_system()
	if equipment_system != null and equipment_system.has_method("get_equipment_slots"):
		var equipment_slots: Dictionary = equipment_system.get_equipment_slots()
		var slot_ids: Array = equipment_slots.keys()
		slot_ids.sort()
		for slot_id_variant in slot_ids:
			var slot_id := str(slot_id_variant)
			var slot_variant: Variant = equipment_slots[slot_id_variant]
			if not slot_variant is Dictionary:
				continue
			var slot: Dictionary = slot_variant
			if not refinement_calculator.is_refinable(slot):
				continue
			entries.append({
				"key": "equipment:%s" % slot_id,
				"source": "equipment",
				"slot_id": slot_id,
				"slot": slot.duplicate(true),
			})
	return entries


func _refresh_refinement_details() -> void:
	if refine_button == null:
		return
	refine_button.disabled = true
	refine_button.text = "Refine"
	refine_detail_label.text = ""
	refine_cost_label.text = ""
	refine_message_label.text = last_message

	var entry := _get_selected_refinement_entry()
	if entry.is_empty():
		refine_detail_label.text = "No weapons or armor available for refinement."
		return

	var slot: Dictionary = entry.get("slot", {})
	var item_id := str(slot.get("item_id", ""))
	var item_data := _get_item_data(item_id)
	var level := RefinementCalculatorScript.get_refinement_level(slot)
	var max_level := refinement_calculator.get_max_refinement_level(slot)
	var preview := refinement_calculator.get_preview(slot)
	var current_data: Dictionary = preview.get("current", {})
	var next_data: Dictionary = preview.get("next", {})
	var detail_lines := [
		RefinementCalculatorScript.get_refined_display_name(item_data, slot),
		"Refinement: +%d / +%d" % [level, max_level],
		"Tier: %d | Type: %s" % [int(item_data.get("tier", 1)), str(item_data.get("item_type", ""))],
	]
	_append_refinement_stat_preview(detail_lines, current_data, next_data)
	refine_detail_label.text = "\n".join(detail_lines)

	if level >= max_level:
		refine_cost_label.text = "Maximum refinement reached."
		refine_button.text = "Maximum +%d" % max_level
		return

	var cost := refinement_calculator.get_refinement_cost(slot)
	if cost.is_empty():
		refine_cost_label.text = "This item has no valid refinement cost."
		return

	var can_afford := true
	var cost_lines := ["Cost for +%d:" % (level + 1)]
	for cost_variant in cost:
		if not cost_variant is Dictionary:
			continue
		var cost_entry: Dictionary = cost_variant
		var resource := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		var owned := int(main.inventory.get_count(resource))
		var marker := "OK" if owned >= amount else "Missing"
		if owned < amount:
			can_afford = false
		cost_lines.append("%s %d/%d %s" % [_get_item_display_name(resource), owned, amount, marker])
	refine_cost_label.text = "\n".join(cost_lines)
	refine_button.text = "Refine to +%d" % (level + 1)
	refine_button.disabled = not can_afford


func _append_refinement_stat_preview(lines: Array, current_data: Dictionary, next_data: Dictionary) -> void:
	var item_type := str(current_data.get("item_type", "")).to_lower()
	if item_type == "weapon":
		var current_combat_variant: Variant = current_data.get("combat", {})
		var next_combat_variant: Variant = next_data.get("combat", {})
		var current_combat: Dictionary = current_combat_variant if current_combat_variant is Dictionary else {}
		var next_combat: Dictionary = next_combat_variant if next_combat_variant is Dictionary else {}
		lines.append("Attack: %d -> %d" % [int(current_combat.get("attack_power", 0)), int(next_combat.get("attack_power", 0))])
		return

	for stat_name in ["defense", "magic_defense", "max_hp_bonus"]:
		var current_value := int(current_data.get(stat_name, 0))
		var next_value := int(next_data.get(stat_name, 0))
		if current_value <= 0 and next_value <= 0:
			continue
		lines.append("%s: %d -> %d" % [stat_name.replace("_", " ").capitalize(), current_value, next_value])


func _get_selected_refinement_entry() -> Dictionary:
	if refine_list == null:
		return {}
	var selected := refine_list.get_selected_items()
	if selected.is_empty():
		return {}
	var metadata: Variant = refine_list.get_item_metadata(selected[0])
	return metadata if metadata is Dictionary else {}


func _on_refinement_item_selected(index: int) -> void:
	var metadata: Variant = refine_list.get_item_metadata(index)
	if metadata is Dictionary:
		selected_refinement_key = str((metadata as Dictionary).get("key", ""))
	last_message = ""
	_refresh_refinement_details()


func _on_refine_pressed() -> void:
	if current_workstation_id != "anvil" or main == null or main.get("inventory") == null:
		return
	var entry := _get_selected_refinement_entry()
	if entry.is_empty():
		return

	var slot: Dictionary = (entry.get("slot", {}) as Dictionary).duplicate(true)
	var item_id := str(slot.get("item_id", ""))
	if not refinement_calculator.refine_item(slot, main.inventory):
		last_message = "Refinement failed - missing materials"
		_refresh_refinement_details()
		return

	var source := str(entry.get("source", ""))
	if source == "inventory":
		var index := int(entry.get("index", -1))
		if index >= 0:
			main.inventory.set_slot(index, item_id, int(slot.get("amount", 1)), slot.get("metadata", {}))
	elif source == "equipment":
		var equipment_system = _get_equipment_system()
		var slot_id := str(entry.get("slot_id", ""))
		if equipment_system != null and not slot_id.is_empty():
			equipment_system.set_equipped_slot(slot_id, slot)
			equipment_system.changed.emit()

	var new_level := RefinementCalculatorScript.get_refinement_level(slot)
	last_message = "%s refined to +%d!" % [_get_item_display_name(item_id), new_level]
	refresh()
