extends Node

const APPLY_INTERVAL := 0.35

var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	call_deferred("_apply")


func _process(delta: float) -> void:
	_timer += delta
	if _timer < APPLY_INTERVAL:
		return
	_timer = 0.0
	_apply()


func _apply() -> void:
	var main := get_tree().current_scene
	if main == null or main.name != "Main":
		return
	var ui := main.get_node_or_null("UI")
	if ui == null:
		return

	_show_and_place_button(ui.get_node_or_null("PlayerStatsButton") as Button, -252, -172, -4, -140)
	_show_and_place_button(ui.get_node_or_null("SpawnMonsterButton") as Button, -252, -132, -4, -100)
	_show_and_place_button(ui.get_node_or_null("SaveButton") as Button, -252, -52, -132, -20)
	_show_and_place_button(ui.get_node_or_null("LoadButton") as Button, -124, -52, -4, -20)

	_place_panel(ui.get_node_or_null("PlayerStatsPanel") as Control, -252, -420, -4, -140)
	_place_panel(ui.get_node_or_null("MonsterSpawnPanel") as Control, -370, -620, -4, -140)


func _show_and_place_button(button: Button, left: float, top: float, right: float, bottom: float) -> void:
	if button == null:
		return
	button.visible = true
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = left
	button.offset_top = top
	button.offset_right = right
	button.offset_bottom = bottom
	button.focus_mode = Control.FOCUS_NONE


func _place_panel(panel: Control, left: float, top: float, right: float, bottom: float) -> void:
	if panel == null:
		return
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = right
	panel.offset_bottom = bottom
