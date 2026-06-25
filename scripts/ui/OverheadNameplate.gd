extends Node2D

@export var always_visible := true

@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar


func _ready() -> void:
	visible = always_visible
	name_label.label_settings = _make_name_label_settings()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 1.0


func setup(display_name: String, current_health: int, max_health: int) -> void:
	if not is_node_ready():
		await ready

	name_label.text = display_name
	set_health(current_health, max_health)


func set_health(current_health: int, max_health: int) -> void:
	if not is_node_ready():
		await ready

	var safe_max: int = max(max_health, 1)
	health_bar.max_value = safe_max
	health_bar.value = clamp(current_health, 0, safe_max)
	var health_ratio: float = float(current_health) / float(safe_max)
	health_bar.modulate = Color(1.0, 0.25, 0.25, 1.0) if health_ratio <= 0.3 else Color.WHITE


func _make_name_label_settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_color = Color.WHITE
	settings.font_size = 12
	settings.outline_color = Color.BLACK
	settings.outline_size = 2

	var font_path := "res://assets/fonts/pixel_font.ttf"
	if FileAccess.file_exists(font_path):
		settings.font = load(font_path)

	return settings
