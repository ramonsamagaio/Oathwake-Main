extends CharacterBody2D

@export var move_speed_px_s: float = 180.0
@export var jump_speed_px_s: float = 360.0
@onready var swimmer: WaterSwimmer2D = $WaterSwimmer2D

var gravity_px_s2 := 980.0

func _ready() -> void:
    gravity_px_s2 = float(ProjectSettings.get_setting(
        "physics/2d/default_gravity",
        980.0
    ))

func _physics_process(delta: float) -> void:
    velocity.x = Input.get_axis("ui_left", "ui_right") * move_speed_px_s

    if not is_on_floor():
        velocity.y += gravity_px_s2 * delta
    elif Input.is_action_just_pressed("ui_accept"):
        velocity.y = -jump_speed_px_s

    # This is the only integration line an existing CharacterBody2D needs.
    # Keep the user's controller, animations, collisions and move_and_slide().
    velocity = swimmer.apply_water_motion(velocity, delta)

    move_and_slide()
