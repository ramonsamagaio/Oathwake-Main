extends CanvasLayer

## Demo-only master switch for the presentation layer.
## Physics keeps running exactly the same while the visual pass is hidden.

var _checkbox: CheckBox
var _fx: Node

func _ready() -> void:
    layer = 11

    _checkbox = CheckBox.new()
    _checkbox.text = "Underwater Visual FX"
    _checkbox.button_pressed = true
    _checkbox.position = Vector2(468.0, 80.0)
    _checkbox.custom_minimum_size = Vector2(170.0, 28.0)
    _checkbox.modulate = Color(0.82, 0.94, 0.97)
    add_child(_checkbox)

    call_deferred("_bind_visual_fx")

func _bind_visual_fx() -> void:
    var water := get_parent().get_node_or_null("Water")
    if water == null:
        _checkbox.disabled = true
        return

    _fx = water.get_node_or_null("WaterVisualFX")
    if _fx == null:
        _checkbox.disabled = true
        return

    if _fx.has_method("is_fx_enabled"):
        _checkbox.button_pressed = bool(_fx.call("is_fx_enabled"))
    _checkbox.toggled.connect(_on_fx_toggled)

func _on_fx_toggled(enabled: bool) -> void:
    if _fx != null and is_instance_valid(_fx) and _fx.has_method("set_fx_enabled"):
        _fx.call("set_fx_enabled", enabled)
