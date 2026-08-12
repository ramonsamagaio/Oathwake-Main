class_name WaterObjectInspector
extends PanelContainer

var selected_body: BuoyantPixelBody2D
var _title: Label
var _material: OptionButton
var _mass: SpinBox
var _buoyancy: SpinBox
var _drag: SpinBox
var _status: Label
var _live: Label
var _syncing := false

func _ready() -> void:
    custom_minimum_size = Vector2(290.0, 0.0)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 7)
    margin.add_child(root)

    _title = Label.new()
    _title.text = "OBJECT LAB"
    _title.add_theme_font_size_override("font_size", 19)
    root.add_child(_title)

    var hint := Label.new()
    hint.text = "Click, drag and throw any object.\nTune it while the simulation keeps running."
    hint.modulate = Color(0.78, 0.82, 0.86)
    root.add_child(hint)

    root.add_child(HSeparator.new())

    _material = OptionButton.new()
    for material_name in WaterMaterialPresets.names():
        _material.add_item(material_name)
    _material.item_selected.connect(_on_material_selected)
    _add_field(root, "Material", _material)

    _mass = SpinBox.new()
    _mass.min_value = 0.05
    _mass.max_value = 250.0
    _mass.step = 0.05
    _mass.suffix = " kg"
    _mass.value_changed.connect(_on_mass_changed)
    _add_field(root, "Mass / weight", _mass)

    _buoyancy = SpinBox.new()
    _buoyancy.min_value = 0.10
    _buoyancy.max_value = 3.0
    _buoyancy.step = 0.05
    _buoyancy.value_changed.connect(_on_buoyancy_changed)
    _add_field(root, "Buoyancy multiplier", _buoyancy)

    _drag = SpinBox.new()
    _drag.min_value = 0.10
    _drag.max_value = 3.0
    _drag.step = 0.05
    _drag.value_changed.connect(_on_drag_changed)
    _add_field(root, "Hydrodynamic drag", _drag)

    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.text = "Select an object to inspect its physics."
    root.add_child(_status)

    _live = Label.new()
    _live.modulate = Color(0.66, 0.84, 0.92)
    root.add_child(_live)

    var button_row := HBoxContainer.new()
    root.add_child(button_row)
    var auto_mass := Button.new()
    auto_mass.text = "Mass from material"
    auto_mass.pressed.connect(_on_auto_mass)
    button_row.add_child(auto_mass)
    var reset := Button.new()
    reset.text = "Reset object"
    reset.pressed.connect(_on_reset)
    button_row.add_child(reset)

    set_process(true)

func _add_field(root: VBoxContainer, label_text: String, control: Control) -> void:
    var box := VBoxContainer.new()
    var label := Label.new()
    label.text = label_text
    label.modulate = Color(0.78, 0.82, 0.86)
    box.add_child(label)
    box.add_child(control)
    root.add_child(box)

func inspect(body: BuoyantPixelBody2D) -> void:
    selected_body = body
    _sync_from_body()

func _sync_from_body() -> void:
    if selected_body == null or not is_instance_valid(selected_body):
        return
    _syncing = true
    _title.text = selected_body.display_name.to_upper()
    var names := WaterMaterialPresets.names()
    var index := names.find(selected_body.material_name)
    if index >= 0:
        _material.select(index)
    _mass.value = selected_body.mass
    _buoyancy.value = selected_body.buoyancy_multiplier
    _drag.value = selected_body.drag_coefficient
    _status.text = "%s\nBulk density: %.0f kg/m³\nVolume: %.4f m³" % [
        selected_body.float_state_text(),
        selected_body.effective_density_kg_m3,
        selected_body.object_volume_m3
    ]
    _syncing = false

func _process(_delta: float) -> void:
    if selected_body == null or not is_instance_valid(selected_body):
        _live.text = ""
        return
    _live.text = "Now submerged: %d%%\nSpeed: %.2f m/s" % [
        int(selected_body.submerged_fraction * 100.0),
        selected_body.linear_velocity.length() / selected_body.pixels_per_meter
    ]
    _status.text = "%s\nBulk density: %.0f kg/m³\nVolume: %.4f m³" % [
        selected_body.float_state_text(),
        selected_body.effective_density_kg_m3,
        selected_body.object_volume_m3
    ]

func _on_material_selected(index: int) -> void:
    if _syncing or selected_body == null:
        return
    var names := WaterMaterialPresets.names()
    if index >= 0 and index < names.size():
        selected_body.set_material_preset(names[index], true)
        _sync_from_body()

func _on_mass_changed(value: float) -> void:
    if _syncing or selected_body == null:
        return
    selected_body.set_mass_kg(value)

func _on_buoyancy_changed(value: float) -> void:
    if _syncing or selected_body == null:
        return
    selected_body.set_buoyancy_multiplier(value)

func _on_drag_changed(value: float) -> void:
    if _syncing or selected_body == null:
        return
    selected_body.set_drag_coefficient(value)

func _on_auto_mass() -> void:
    if selected_body == null:
        return
    selected_body.set_material_preset(selected_body.material_name, true)
    _sync_from_body()

func _on_reset() -> void:
    if selected_body != null:
        selected_body.reset_to_spawn()
