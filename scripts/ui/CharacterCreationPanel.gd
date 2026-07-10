## Lightweight placeholder character creator; appearance is saved but not rendered yet.
class_name CharacterCreationPanel
extends Control

signal create_requested(player_name: String, world_name: String, appearance: Dictionary)
signal cancelled

var _slot_id := ""
var _name_edit: LineEdit
var _gender: OptionButton
var _hair: OptionButton
var _skin: OptionButton
var _eyes: OptionButton
var _create_button: Button


func _ready() -> void:
	_build_ui()
	hide()


func open_for(slot_id: String) -> void:
	_slot_id = slot_id
	_name_edit.text = ""
	_gender.select(0)
	_refresh_hair_options()
	_update_create_enabled()
	show()
	_name_edit.grab_focus()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.06, 0.92)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(590, 220)
	panel.size = Vector2(420, 470)
	add_child(panel)
	var title := Label.new()
	title.text = "Create Character"
	panel.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Enter character name"
	_name_edit.text_changed.connect(func(_text): _update_create_enabled())
	panel.add_child(_name_edit)
	_gender = _add_option(panel, "Gender", ["Masculino", "Feminino"])
	_gender.item_selected.connect(func(_index): _refresh_hair_options())
	_hair = _add_option(panel, "Hair", [])
	_skin = _add_option(panel, "Skin", ["skin_01", "skin_02"])
	_eyes = _add_option(panel, "Eyes", ["eyes_01", "eyes_02"])
	_create_button = Button.new()
	_create_button.text = "Create / Start"
	_create_button.pressed.connect(_on_create_pressed)
	panel.add_child(_create_button)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func(): hide(); cancelled.emit())
	panel.add_child(cancel_button)


func _add_option(parent: VBoxContainer, label_text: String, values: Array) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for value in values:
		option.add_item(str(value))
	parent.add_child(option)
	return option


func _refresh_hair_options() -> void:
	_hair.clear()
	var values := ["hair_m_01", "hair_m_02"] if _gender.selected == 0 else ["hair_f_01", "hair_f_02"]
	for value in values:
		_hair.add_item(value)


func _update_create_enabled() -> void:
	_create_button.disabled = _name_edit.text.strip_edges().is_empty()


func _on_create_pressed() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		return
	var appearance := {
		"gender": "masculino" if _gender.selected == 0 else "feminino",
		"hair": _hair.get_item_text(_hair.selected),
		"skin": _skin.get_item_text(_skin.selected),
		"eyes": _eyes.get_item_text(_eyes.selected),
	}
	hide()
	create_requested.emit(player_name, "World", appearance)
