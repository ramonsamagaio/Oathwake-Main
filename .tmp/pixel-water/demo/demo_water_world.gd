extends PixelWaterWorld2D

## Demo-only presentation tuning.
## The reusable solver stays untouched, while the showcase can make energetic
## interactions more readable. A second turbulence pass uses the exact same
## Froude/curvature threshold as the core, so calm water does not foam more.

@export_range(1.0, 3.0, 0.1) var turbulence_foam_multiplier: float = 2.0

func _physics_process(delta: float) -> void:
    super._physics_process(delta)

    var extra := maxf(turbulence_foam_multiplier - 1.0, 0.0)
    if extra <= 0.001:
        return

    # Reuse the core energy test rather than spawning decorative foam blindly.
    # At 2x this roughly doubles emission only while the surface is genuinely
    # energetic; once it settles, both passes naturally emit nothing.
    _emit_turbulence_foam(delta * extra)
