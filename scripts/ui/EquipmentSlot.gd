extends Button

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const OathwakeUISkin := preload("res://scripts/ui/OathwakeUISkin.gd")

signal equip_selected(slot_id: String)
signal equip_right_clicked(slot_id: String)
signal equip_drag_dropped(slot_id: String, from_slot_index: int, from_inventory_id: String)

var slot_id: String = ""
var item_id: String = ""
var amount: int = 0
var display_name: String = ""
var durability: float = 0.0
var is_broken := false
var _item_icon: TextureRect


func setup(new_slot_id: String, equip_data: Dictionary) -> void:
	_ensure_overlay_controls()
	slot_id = new_slot_id
	item_id = str(equip_data.get("item_id", ""))
	amount = int(equip_data.get("amount", 0))
	_update_display()


func _update_display() -> void:
	# The UILayoutWorkbench owns the final slot rectangle. A minimum size here used
	# to silently expand authored 41x46 slots to 150x52, causing item icons and input
	# hitboxes to overlap neighboring equipment slots at runtime.
	custom_minimum_size = Vector2.ZERO
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	if item_id.is_empty() or amount <= 0:
		text = ""
		icon = null
		expand_icon = false
		tooltip_text = "Empty %s Slot" % slot_id.capitalize()
		display_name = ""
		durability = 0.0
		is_broken = false
		_set_item_texture(null)
		_apply_slot_style()
		_layout_overlay_controls()
		OathwakeTextStyle.apply_profile_to_control(self, "base_ui")
		return

	var item_data := _get_item_data(item_id)
	display_name = str(item_data.get("display_name", item_id.capitalize()))
	is_broken = false
	if item_data.has("durability"):
		durability = float(item_data.get("durability", 0.0))
		var meta = _get_metadata_durability()
		if meta <= 0.0:
			is_broken = true
	text = ""
	icon = null
	expand_icon = false
	tooltip_text = _make_tooltip(item_data)
	_set_item_texture(_get_texture(item_id))
	_apply_slot_style()
	_layout_overlay_controls()
	OathwakeTextStyle.apply_profile_to_control(self, "base_ui")


func _get_item_data(requested_item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(requested_item_id):
		return {}
	return content_db.get_item(requested_item_id)


func _get_texture(requested_item_id: String) -> Texture2D:
	var resolver_class = load("res://scripts/systems/SpriteResolver.gd")
	if resolver_class == null:
		return null
	var resolver = resolver_class.new()
	return resolver.get_texture_for_item(requested_item_id)


func _get_metadata_durability() -> float:
	var equip_system = _get_equipment_system()
	if equip_system == null or not equip_system.has_method("get_equipped_slot"):
		return 0.0
	var equip_data = equip_system.get_equipped_slot(slot_id)
	var meta = equip_data.get("metadata", {})
	if meta is Dictionary:
		return float(meta.get("current_durability", 0.0))
	return 0.0


func _get_equipment_system():
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return null
	return main.get("equipment_system")


func _pressed() -> void:
	equip_selected.emit(slot_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		equip_right_clicked.emit(slot_id)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty() or amount <= 0:
		return null

	var preview := TextureRect.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = _item_icon.texture if _item_icon != null else null
	preview.z_index = 1000
	preview.top_level = true
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size = Vector2(48, 48)
	set_drag_preview(preview)
	return {
		"type": "equipment_slot",
		"slot_id": slot_id,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if str(data.get("type", "")) != "inventory_slot":
		return false
	var from_inventory_id := str(data.get("inventory_id", ""))
	if from_inventory_id != "player":
		return false
	var main = get_tree().get_first_node_in_group("main")
	var inventory = main.get("inventory") if main != null else null
	if inventory != null and inventory.has_method("get_slot"):
		var from_index := int(data.get("slot_index", -1))
		var slot_data = inventory.get_slot(from_index)
		var item_id := str(slot_data.get("item_id", ""))
		if not item_id.is_empty():
			var content_db := get_node_or_null("/root/ContentDB")
			if content_db != null and content_db.has_method("has_item") and content_db.has_item(item_id):
				var item_data: Dictionary = content_db.get_item(item_id)
				var item_type := str(item_data.get("item_type", "")).to_lower()
				if item_type == "tool" or item_type == "weapon":
					return true
	var equip_system = _get_equipment_system()
	if equip_system == null or not equip_system.has_method("can_equip_item"):
		return false
	if main == null:
		return false
	if inventory == null or not inventory.has_method("get_slot"):
		return false
	var from_index := int(data.get("slot_index", -1))
	var slot_data = inventory.get_slot(from_index)
	var drag_item_id := str(slot_data.get("item_id", ""))
	if drag_item_id.is_empty():
		return false
	return equip_system.can_equip_item(drag_item_id, slot_id)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	equip_drag_dropped.emit(
		slot_id,
		int(data.get("slot_index", -1)),
		str(data.get("inventory_id", "player"))
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_overlay_controls()


func _ensure_overlay_controls() -> void:
	if _item_icon == null:
		_item_icon = TextureRect.new()
		_item_icon.name = "ItemIcon"
		_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_item_icon.z_index = 5
		add_child(_item_icon)


func _layout_overlay_controls() -> void:
	if _item_icon == null:
		return
	var margin := Vector2(size.x * 0.14, size.y * 0.14)
	_item_icon.position = margin
	_item_icon.size = Vector2(maxf(0.0, size.x - margin.x * 2.0), maxf(0.0, size.y - margin.y * 2.0))


func _set_item_texture(texture: Texture2D) -> void:
	if _item_icon == null:
		return
	_item_icon.texture = texture
	_item_icon.visible = texture != null


func _make_tooltip(item_data: Dictionary) -> String:
	var lines := [
		"%s (%s)" % [display_name, item_id],
		"Type: %s" % str(item_data.get("item_type", "N/A")),
		"Slot: %s" % str(item_data.get("equipment_slot", slot_id)),
		"Tier: %s" % str(item_data.get("tier", "N/A")),
	]
	var description := str(item_data.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	if item_data.has("durability"):
		var max_dura := float(item_data.get("durability", 0.0))
		var current_dura := _get_metadata_durability()
		if current_dura > 0.0:
			lines.append("Durability: %.0f / %.0f" % [current_dura, max_dura])
		else:
			lines.append("Durability: BROKEN")
	if item_data.get("item_type") == "tool":
		lines.append("Tool: %s T%s" % [str(item_data.get("tool_type", "N/A")), str(item_data.get("tool_tier", "N/A"))])
		lines.append("Damage: %s" % str(item_data.get("tool_damage", "N/A")))
	var defense := int(item_data.get("defense", 0))
	if defense > 0:
		lines.append("Defense: %d" % defense)
	var magic_defense := int(item_data.get("magic_defense", 0))
	if magic_defense > 0:
		lines.append("Magic Def: %d" % magic_defense)
	var max_hp_bonus := int(item_data.get("max_hp_bonus", 0))
	if max_hp_bonus > 0:
		lines.append("Max HP +%d" % max_hp_bonus)
	var hit_bonus := int(item_data.get("hit_bonus", 0))
	if hit_bonus > 0:
		lines.append("Hit +%d" % hit_bonus)
	var flee_bonus := int(item_data.get("flee_bonus", 0))
	if flee_bonus > 0:
		lines.append("Flee +%d" % flee_bonus)
	var combat_value: Variant = item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		if combat.has("attack_power"):
			lines.append("Attack: %s" % str(combat.get("attack_power", "N/A")))
		if combat.has("damage_type"):
			lines.append("Damage Type: %s" % str(combat.get("damage_type", "N/A")))
	var stats_bonus: Variant = item_data.get("stats_bonus", {})
	if stats_bonus is Dictionary:
		for stat in stats_bonus.keys():
			lines.append("+%s %s" % [str(stats_bonus[stat]), stat.capitalize()])
	return "\n".join(lines)


func _apply_slot_style() -> void:
	if is_broken:
		var broken_style := StyleBoxFlat.new()
		broken_style.bg_color = Color(0.45, 0.08, 0.07, 0.92)
		broken_style.border_color = Color(0.95, 0.22, 0.18, 1.0)
		broken_style.set_border_width_all(2)
		broken_style.corner_radius_top_left = 4
		broken_style.corner_radius_top_right = 4
		broken_style.corner_radius_bottom_left = 4
		broken_style.corner_radius_bottom_right = 4
		add_theme_stylebox_override("normal", broken_style)
		add_theme_stylebox_override("hover", broken_style)
		add_theme_stylebox_override("pressed", broken_style)
		return

	OathwakeUISkin.apply_slot_button(self, "empty")
