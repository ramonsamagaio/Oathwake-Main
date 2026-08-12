extends PixelWaterWorld2D

## Demo-only presentation tuning.
## The showcase doubles energetic foam without changing calm-water behavior.
## It also hardens conservative airborne water: packets that carry real volume
## do not expire just because a visual TTL elapsed. They remain simulated until
## they land back in the water/terrain or physically leave the configured world.

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

func _simulate_droplets(delta: float) -> void:
    for i in range(_droplets.size() - 1, -1, -1):
        var d: Dictionary = _droplets[i]
        var pos: Vector2 = d.get("pos", Vector2.ZERO)
        var vel: Vector2 = d.get("vel", Vector2.ZERO)
        var life := float(d.get("life", 0.0)) - delta
        var amount := maxf(float(d.get("amount_m3", 0.0)), 0.0)
        var carries_real_water := amount > 0.000000001

        vel.y += gravity_px_s2 * delta
        pos += vel * delta
        d["pos"] = pos
        d["vel"] = vel
        d["life"] = life

        var inside_x := pos.x >= world_left and pos.x < world_right
        if inside_x:
            var floor_y := floor_y_at(pos.x)
            var sy := surface_y_at(pos.x)
            var has_water := depth_m_at(pos.x) > dry_depth_m
            var landing_y := sy if has_water else floor_y

            if pos.y >= landing_y:
                deposit_water_at(
                    pos.x,
                    amount,
                    vel.x / pixels_per_meter,
                    cell_size_px * 1.5
                )
                if has_water and carries_real_water:
                    _add_radial_momentum(
                        pos.x,
                        10.0,
                        clampf(absf(vel.y) / pixels_per_meter * 0.025, 0.01, 0.12)
                    )
                _droplets.remove_at(i)
                continue

        # Massless visual spray may expire normally. A conservative packet may
        # not disappear due to TTL while still inside the simulated world.
        if not carries_real_water and life <= 0.0:
            _droplets.remove_at(i)
            continue

        # Crossing the configured horizontal domain is an actual outflow loss.
        if pos.x < world_left - 80.0 or pos.x > world_right + 80.0:
            _droplets.remove_at(i)
            continue

        # Defensive fallback. Inside the domain this should already have landed
        # against floor_y, but never destroy conserved water if a large timestep
        # skips below the world floor.
        if pos.y > 900.0:
            if carries_real_water and inside_x:
                deposit_water_at(
                    pos.x,
                    amount,
                    vel.x / pixels_per_meter,
                    cell_size_px * 1.5
                )
            _droplets.remove_at(i)
            continue

        _droplets[i] = d
