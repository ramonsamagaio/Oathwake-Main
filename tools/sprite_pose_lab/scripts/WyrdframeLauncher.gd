extends Node

@onready var app_window: Window = $WyrdframeWindow


func _ready() -> void:
	app_window.force_native = true
	app_window.transient = false
	app_window.exclusive = false
	app_window.unresizable = false
	app_window.min_size = Vector2i(1100, 700)
	app_window.show()
	app_window.mode = Window.MODE_MAXIMIZED
