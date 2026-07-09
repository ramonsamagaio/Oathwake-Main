extends Control

const RecipeBookScript := preload("res://scripts/systems/RecipeBook.gd")
const SpriteResolverScript := preload("res://scripts/systems/SpriteResolver.gd")
const RepairCalculatorScript := preload("res://scripts/systems/RepairCalculator.gd")
const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")

const TYPE_FILTERS := ["All", "Building", "Tool", "Weapon", "Material", "Food", "Alchemy"]
const TIER_FILTERS := ["All", "T1", "T2", "T3", "T4", "T5", "T6", "T7"]
const REPAIRABLE_TYPES := ["tool", "weapon", "armor", "accessory"]

var main
var player
var recipe_book := RecipeBookScript.new()
var sprite_resolver := SpriteResolverScript.new()
var repair_calculator := RepairCalculatorScript.new()
var recipes: Array = []
var filtered_recipes: Array = []
var selected_recipe_id := ""
var last_message := ""
var current_workstation_id := "workbench"

var current_tab := "craft"

var craft_tab_button: Button
var repair_tab_button: Button
var craft_body: HBoxContainer
var repair_body: VBoxContainer
var header_label: Label

var search_edit: LineEdit
var type_filter: OptionButton
var tier_filter: OptionButton
var recipe_list: ItemList
var title_label: Label
var output_icon: TextureRect
var detail_label: Label
var costs_label: Label
var message_label: Label
var craft_button: Button
var craft_five_button: Button
var craft_max_button: Button

var repair_list: ItemList
var repair_detail_label: Label
var repair_cost_label: Label
var repair_message_label: Label
var repair_button: Button


func _ready() -> void:
	add_to_group("workbench_ui")
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()


func setup(new_main, new_player) -> void:
	main = new_main
	player = new_player
	if main != null and main.get("inventory") != null and main.inventory.has_signal("changed"):
		main.inventory.changed.connect(refresh)
	refresh()


func open(workstation_id := "workbench") -> void:
	current_workstation_id = workstation_id if not workstation_id.is_empty() else "basic"
	visible = true
	last_message = ""
	if header_label != null:
		header_label.text = _get_workstation_display_name()
	refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	if current_tab == "craft":
		recipes = _get_workbench_recipes()
		_apply_filters()
		_refresh_recipe_list()
		_refresh_details()
	else:
		_refresh_repair_list()
		_refresh_repair_details()


func _switch_tab(tab: String) -> void:
	current_tab = tab
	craft_tab_button.disabled = tab == "craft"
	repair_tab_button.disabled = tab == "repair"
	craft_body.visible = tab == "craft"
	repair_body.visible = tab == "repair"
	refresh()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -430.0
	panel.offset_top = -270.0
	panel.offset_right = 430.0
	panel.offset_bottom = 270.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	header_label = Label.new()
	header_label.text = _get_workstation_display_name()
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var tabs := HBoxContainer.new()
	root.add_child(tabs)

	craft_tab_button = Button.new()
	craft_tab_button.text = "Craft"
	craft_tab_button.focus_mode = Control.FOCUS_NONE
	craft_tab_button.disabled = true
	craft_tab_button.pressed.connect(_switch_tab.bind("craft"))
	tabs.add_child(craft_tab_button)

	repair_tab_button = Button.new()
	repair_tab_button.text = "Repair"
	repair_tab_button.focus_mode = Control.FOCUS_NONE
	repair_tab_button.pressed.connect(_switch_tab.bind("repair"))
	tabs.add_child(repair_tab_button)

	craft_body = HBoxContainer.new()
	craft_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(craft_body)

	repair_body = VBoxContainer.new()
	repair_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(repair_body)

	_build_craft_body()
	_build_repair_body()
	repair_body.visible = false


func _build_craft_body() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(310, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_body.add_child(left)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search recipes"
	search_edit.text_changed.connect(_on_filters_changed)
	left.add_child(search_edit)

	var filters := HBoxContainer.new()
	left.add_child(filters)

	type_filter = OptionButton.new()
	for filter_name in TYPE_FILTERS:
		type_filter.add_item(filter_name)
	type_filter.item_selected.connect(_on_filter_selected)
	filters.add_child(type_filter)

	tier_filter = OptionButton.new()
	for filter_name in TIER_FILTERS:
		tier_filter.add_item(filter_name)
	tier_filter.item_selected.connect(_on_filter_selected)
	filters.add_child(tier_filter)

	recipe_list = ItemList.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.item_selected.connect(_on_recipe_selected)
	left.add_child(recipe_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_body.add_child(right)

	title_label = Label.new()
	title_label.text = "Select a recipe"
	right.add_child(title_label)

	output_icon = TextureRect.new()
	output_icon.custom_minimum_size = Vector2(72, 72)
	output_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	output_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(output_icon)

	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 120)
	right.add_child(detail_label)

	costs_label = Label.new()
	costs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	costs_label.custom_minimum_size = Vector2(0, 110)
	right.add_child(costs_label)

	var buttons := HBoxContainer.new()
	right.add_child(buttons)

	craft_button = Button.new()
	craft_button.text = "Craft"
	craft_button.focus_mode = Control.FOCUS_NONE
	craft_button.pressed.connect(_on_craft_pressed)
	buttons.add_child(craft_button)

	craft_five_button = Button.new()
	craft_five_button.text = "Craft x5"
	craft_five_button.focus_mode = Control.FOCUS_NONE
	craft_five_button.pressed.connect(_on_craft_five_pressed)
	buttons.add_child(craft_five_button)

	craft_max_button = Button.new()
	craft_max_button.text = "Craft Max"
	craft_max_button.focus_mode = Control.FOCUS_NONE
	craft_max_button.pressed.connect(_on_craft_max_pressed)
	buttons.add_child(craft_max_button)

	message_label = Label.new()
	message_label.text = ""
	right.add_child(message_label)


func _build_repair_body() -> void:
	var header_label := Label.new()
	header_label.text = "Repair Items"
	repair_body.add_child(header_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	repair_body.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(310, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	repair_list = ItemList.new()
	repair_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	repair_list.item_selected.connect(_on_repair_item_selected)
	left.add_child(repair_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	repair_detail_label = Label.new()
	repair_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_detail_label.custom_minimum_size = Vector2(0, 140)
	right.add_child(repair_detail_label)

	repair_cost_label = Label.new()
	repair_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_cost_label.custom_minimum_size = Vector2(0, 100)
	right.add_child(repair_cost_label)

	repair_button = Button.new()
	repair_button.text = "Repair"
	repair_button.focus_mode = Control.FOCUS_NONE
	repair_button.disabled = true
	repair_button.pressed.connect(_on_repair_pressed)
	right.add_child(repair_button)

	repair_message_label = Label.new()
	repair_message_label.text = ""
	right.add_child(repair_message_label)


func _refresh_repair_list() -> void:
	if repair_list == null:
		return
	repair_list.clear()
	var items := _get_repairable_items()
	for index in range(items.size()):
		var entry: Dictionary = items[index]
		var slot: Dictionary = entry.get("slot", {})
		var item_id := str(slot.get("item_id", ""))
		var item_data := _get_item_data(item_id)
		var display_name := str(item_data.get("display_name", item_id.capitalize()))
		var current_dura := ItemInstanceHelper.get_current_durability(slot)
		var max_dura := ItemInstanceHelper.get_max_durability(item_id)
		var broken_text := " [BROKEN]" if ItemInstanceHelper.is_broken(slot) else ""
		var label := "%s (%d/%d)%s" % [display_name, current_dura, max_dura, broken_text]
		repair_list.add_item(label, sprite_resolver.get_texture_for_item(item_id))
		repair_list.set_item_metadata(index, index)


func _get_repairable_items() -> Array:
	var items := []
	if main == null or main.get("inventory") == null:
		return items

	var inventory = main.inventory
	var slot_count = inventory.get_slot_count()
	for i in range(slot_count):
		var slot: Dictionary = inventory.get_slot(i)
		var item_id := str(slot.get("item_id", ""))
		if item_id.is_empty():
			continue
		var item_data := _get_item_data(item_id)
		var item_type := str(item_data.get("item_type", ""))
		if not REPAIRABLE_TYPES.has(item_type):
			continue
		if not repair_calculator.can_repair(slot):
			continue
		items.append({"slot": slot, "source": "inventory", "index": i})

	var eq_system = _get_equipment_system()
	if eq_system != null:
		for slot_id in ["weapon", "tool", "armor", "accessory"]:
			var slot_data = eq_system.get_equipped_slot(slot_id)
			if not slot_data is Dictionary:
				continue
			var item_id := str(slot_data.get("item_id", ""))
			if item_id.is_empty():
				continue
			if not repair_calculator.can_repair(slot_data):
				continue
			var slot_copy = slot_data.duplicate(true)
			items.append({"slot": slot_copy, "source": "equipment", "slot_id": slot_id})

	return items


func _refresh_repair_details() -> void:
	repair_button.disabled = true
	repair_detail_label.text = ""
	repair_cost_label.text = ""
	repair_message_label.text = last_message

	var selected_indices := repair_list.get_selected_items()
	if selected_indices.is_empty():
		return

	var items := _get_repairable_items()
	var meta_index: int = int(repair_list.get_item_metadata(selected_indices[0]))
	if meta_index < 0 or meta_index >= items.size():
		return

	var entry: Dictionary = items[meta_index]
	var slot: Dictionary = entry.get("slot", {})
	var item_id := str(slot.get("item_id", ""))
	var item_data := _get_item_data(item_id)
	var display_name := str(item_data.get("display_name", item_id.capitalize()))
	var current_dura := ItemInstanceHelper.get_current_durability(slot)
	var max_dura := ItemInstanceHelper.get_max_durability(item_id)

	repair_detail_label.text = "%s\nDurability: %d / %d\n%s" % [
		display_name,
		current_dura,
		max_dura,
		"[BROKEN]" if ItemInstanceHelper.is_broken(slot) else "",
	]

	var cost: Array = repair_calculator.get_repair_cost(slot)
	if cost.is_empty():
		repair_cost_label.text = "Cannot repair this item."
		return

	var cost_lines := ["Repair Cost:"]
	var can_afford := true
	for cost_entry in cost:
		var resource := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		var owned = main.inventory.get_count(resource) if main.inventory != null else 0
		var marker := "OK" if owned >= amount else "Missing"
		if owned < amount:
			can_afford = false
		cost_lines.append("%s %d/%d %s" % [_get_item_display_name(resource), owned, amount, marker])

	repair_cost_label.text = "\n".join(cost_lines)
	repair_button.disabled = not can_afford


func _on_repair_item_selected(_index: int) -> void:
	_refresh_repair_details()


func _on_repair_pressed() -> void:
	var selected_indices := repair_list.get_selected_items()
	if selected_indices.is_empty():
		return

	var items := _get_repairable_items()
	var meta_index: int = int(repair_list.get_item_metadata(selected_indices[0]))
	if meta_index < 0 or meta_index >= items.size():
		return

	var entry: Dictionary = items[meta_index]
	var slot: Dictionary = entry.get("slot", {})
	var item_id := str(slot.get("item_id", ""))
	var source := str(entry.get("source", ""))
	var inventory = main.inventory

	if not repair_calculator.repair_item(slot, inventory):
		last_message = "Repair failed - missing materials"
		_refresh_repair_details()
		return

	if source == "equipment":
		var slot_id := str(entry.get("slot_id", ""))
		var eq_system = _get_equipment_system()
		if eq_system != null:
			eq_system.set_equipped_slot(slot_id, slot)
			eq_system.changed.emit()
	elif source == "inventory":
		var inv_index: int = int(entry.get("index", -1))
		if inv_index >= 0:
			var metadata: Dictionary = slot.get("metadata", {})
			inventory.set_slot(inv_index, item_id, int(slot.get("amount", 1)))
			if not metadata.is_empty():
				inventory.set_slot_metadata(inv_index, metadata)

	last_message = "%s repaired!" % _get_item_display_name(item_id)
	refresh()


func _get_equipment_system():
	if main == null:
		return null
	return main.get("equipment_system")


func _get_workbench_recipes() -> Array:
	var result := []
	for recipe in recipe_book.get_all_recipes():
		if not recipe is Dictionary:
			continue

		var output_item_id := _get_recipe_output_item_id(recipe)
		if output_item_id.is_empty():
			continue
		if not _has_item(output_item_id):
			continue

		var workstation := str(recipe.get("workstation", "basic"))
		if workstation.is_empty():
			workstation = "basic"
		if workstation == "basic" or workstation == current_workstation_id:
			result.append(recipe)

	result.sort_custom(_compare_recipes)
	return result


func _apply_filters() -> void:
	filtered_recipes.clear()
	var query: String = search_edit.text.strip_edges().to_lower() if search_edit != null else ""
	var selected_type: String = str(TYPE_FILTERS[type_filter.selected]).to_lower() if type_filter != null else "all"
	var selected_tier: int = tier_filter.selected if tier_filter != null else 0

	for recipe in recipes:
		var display_name := str(recipe.get("display_name", recipe.get("id", "")))
		var recipe_id := str(recipe.get("id", ""))
		if not query.is_empty() and not display_name.to_lower().contains(query) and not recipe_id.to_lower().contains(query):
			continue

		var recipe_type := str(recipe.get("type", "material")).to_lower()
		if selected_type != "all" and recipe_type != selected_type:
			continue

		var tier := int(recipe.get("tier", 1))
		if selected_tier > 0 and tier != selected_tier:
			continue

		filtered_recipes.append(recipe)

	if selected_recipe_id.is_empty() and not filtered_recipes.is_empty():
		selected_recipe_id = str((filtered_recipes[0] as Dictionary).get("id", ""))


func _refresh_recipe_list() -> void:
	if recipe_list == null:
		return

	recipe_list.clear()
	var selected_index := -1
	for index in range(filtered_recipes.size()):
		var recipe: Dictionary = filtered_recipes[index]
		var recipe_id := str(recipe.get("id", ""))
		var output_item_id := _get_recipe_output_item_id(recipe)
		var craftable_text := "" if _can_craft(recipe, 1) else " Missing"
		var label := "T%d %s%s" % [
			int(recipe.get("tier", 1)),
			str(recipe.get("display_name", recipe_id.capitalize())),
			craftable_text,
		]
		recipe_list.add_item(label, sprite_resolver.get_texture_for_item(output_item_id))
		recipe_list.set_item_metadata(index, recipe_id)
		if recipe_id == selected_recipe_id:
			selected_index = index

	if selected_index >= 0:
		recipe_list.select(selected_index)


func _refresh_details() -> void:
	var recipe := _get_selected_recipe()
	var has_selection := not recipe.is_empty()
	craft_button.disabled = not has_selection or not _can_craft(recipe, 1)
	craft_five_button.disabled = not has_selection or not _can_craft(recipe, 5)
	craft_max_button.disabled = not has_selection or _get_max_craft_count(recipe) <= 0

	if not has_selection:
		title_label.text = "Select a recipe"
		output_icon.texture = null
		detail_label.text = ""
		costs_label.text = ""
		message_label.text = last_message
		return

	var output_item_id := _get_recipe_output_item_id(recipe)
	var output_amount := int(recipe.get("output_amount", 1))
	var item_data := _get_item_data(output_item_id)
	title_label.text = str(recipe.get("display_name", recipe.get("id", "")))
	output_icon.texture = sprite_resolver.get_texture_for_item(output_item_id)
	detail_label.text = "Output: %s x%d\nTier: %d\nType: %s\nWorkstation: %s\n%s" % [
		str(item_data.get("display_name", output_item_id.capitalize())),
		output_amount,
		int(recipe.get("tier", 1)),
		str(recipe.get("type", "material")),
		str(recipe.get("workstation", "basic")),
		str(item_data.get("description", "")),
	]
	costs_label.text = _get_costs_text(recipe)
	message_label.text = last_message


func _try_craft_selected(count: int) -> void:
	var recipe := _get_selected_recipe()
	if recipe.is_empty():
		return

	var craft_count: int = int(min(count, _get_max_craft_count(recipe)))
	if craft_count <= 0:
		last_message = "Not enough resources"
		_refresh_details()
		return

	var output_item_id := _get_recipe_output_item_id(recipe)
	var output_amount: int = int(recipe.get("output_amount", 1)) * craft_count
	if main == null or main.get("inventory") == null or not main.inventory.can_add_item(output_item_id, output_amount):
		last_message = "Inventory full"
		_refresh_details()
		return

	var cost: Array = recipe.get("cost", [])
	for cost_entry in cost:
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0)) * craft_count
		if not item_id.is_empty() and amount > 0:
			main.spend_resource(item_id, amount)

	main.add_item_to_inventory(output_item_id, output_amount)
	last_message = "Crafted %s x%d" % [str(recipe.get("display_name", output_item_id.capitalize())), craft_count]
	refresh()


func _can_craft(recipe: Dictionary, count: int) -> bool:
	if main == null or main.get("inventory") == null:
		return false

	var output_item_id := _get_recipe_output_item_id(recipe)
	var output_amount := int(recipe.get("output_amount", 1)) * count
	if output_item_id.is_empty() or not main.inventory.can_add_item(output_item_id, output_amount):
		return false

	var cost: Array = recipe.get("cost", [])
	for cost_entry in cost:
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0)) * count
		if item_id.is_empty() or amount <= 0:
			continue
		if not main.can_spend_resource(item_id, amount):
			return false

	return true


func _get_max_craft_count(recipe: Dictionary) -> int:
	if main == null or main.get("inventory") == null:
		return 0

	var output_item_id := _get_recipe_output_item_id(recipe)
	var output_amount = max(int(recipe.get("output_amount", 1)), 1)
	var max_count := 999
	var cost: Array = recipe.get("cost", [])
	for cost_entry in cost:
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		max_count = min(max_count, int(floor(float(main.inventory.get_count(item_id)) / float(amount))))

	if max_count == 999:
		max_count = 1

	var fitting_count := max_count
	while fitting_count > 0 and not main.inventory.can_add_item(output_item_id, output_amount * fitting_count):
		fitting_count -= 1

	return max(fitting_count, 0)


func _get_costs_text(recipe: Dictionary) -> String:
	if main == null:
		return ""
	if main.inventory == null:
		return ""

	var lines := ["Costs:"]
	var cost: Array = recipe.get("cost", [])
	if cost.is_empty():
		lines.append("Free")
		return "\n".join(lines)

	for cost_entry in cost:
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		var owned = main.inventory.get_count(item_id)
		var marker := "OK" if owned >= amount else "Missing"
		lines.append("%s %d/%d %s" % [_get_item_display_name(item_id), owned, amount, marker])

	return "\n".join(lines)


func _get_recipe_output_item_id(recipe: Dictionary) -> String:
	return str(recipe.get("output_item_id", recipe.get("id", "")))


func _get_selected_recipe() -> Dictionary:
	if selected_recipe_id.is_empty():
		return {}

	for recipe in recipes:
		if str((recipe as Dictionary).get("id", "")) == selected_recipe_id:
			return recipe

	return {}


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	return content_db.get_item(item_id)


func _has_item(item_id: String) -> bool:
	var content_db := get_node_or_null("/root/ContentDB")
	return content_db != null and content_db.has_method("has_item") and content_db.has_item(item_id)


func _get_item_display_name(item_id: String) -> String:
	var item_data := _get_item_data(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _get_workstation_display_name() -> String:
	if current_workstation_id == "basic":
		return "Basic Crafting"
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_all_buildings"):
		var buildings: Dictionary = content_db.get_all_buildings()
		for building_id in buildings.keys():
			var building_data = buildings[building_id]
			if building_data is Dictionary and str(building_data.get("workstation_id", "")) == current_workstation_id:
				return str(building_data.get("display_name", current_workstation_id.capitalize()))
	return current_workstation_id.capitalize()


func _compare_recipes(a, b) -> bool:
	var recipe_a: Dictionary = a
	var recipe_b: Dictionary = b
	var key_a := "%04d|%s|%s" % [
		int(recipe_a.get("tier", 1)),
		str(recipe_a.get("type", "")),
		str(recipe_a.get("display_name", "")),
	]
	var key_b := "%04d|%s|%s" % [
		int(recipe_b.get("tier", 1)),
		str(recipe_b.get("type", "")),
		str(recipe_b.get("display_name", "")),
	]
	return key_a < key_b


func _on_filters_changed(_new_text := "") -> void:
	refresh()


func _on_filter_selected(_index: int) -> void:
	refresh()


func _on_recipe_selected(index: int) -> void:
	selected_recipe_id = str(recipe_list.get_item_metadata(index))
	last_message = ""
	_refresh_details()


func _on_craft_pressed() -> void:
	_try_craft_selected(1)


func _on_craft_five_pressed() -> void:
	_try_craft_selected(5)


func _on_craft_max_pressed() -> void:
	var recipe := _get_selected_recipe()
	_try_craft_selected(_get_max_craft_count(recipe))
