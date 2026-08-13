from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORLD = ROOT / ".tmp/pixel-water/addons/pixel_water/pixel_water_world.gd"
BODY = ROOT / ".tmp/pixel-water/addons/pixel_water/buoyant_body.gd"
COMPONENT = ROOT / ".tmp/pixel-water/addons/pixel_water/water_buoyancy_2d.gd"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


world = WORLD.read_text(encoding="utf-8")
world = replace_once(world, "@export var max_bubbles: int = 64", "@export var max_bubbles: int = 128", "max bubbles")
world = replace_once(world, "@export var max_foam_particles: int = 100", "@export var max_foam_particles: int = 180", "max foam")

old_impact_foam = '''    if impact_energy_j > 18.0:\n        _spawn_foam(world_x, clampf(impact_energy_j / 120.0, 0.35, 0.85))\n'''
new_impact_foam = '''    # Energetic entries deserve a visible foam burst, but calm floating should not.\n    if impact_energy_j > 12.0:\n        var foam_intensity := clampf(impact_energy_j / 105.0, 0.38, 0.95)\n        var foam_count := 3 if impact_energy_j > 70.0 else 2\n        for foam_index in range(foam_count):\n            var offset := (float(foam_index) - float(foam_count - 1) * 0.5) * object_width_px * 0.16\n            _spawn_foam(world_x + offset, foam_intensity)\n'''
world = replace_once(world, old_impact_foam, new_impact_foam, "impact foam burst")

activity_fx = '''func register_object_activity_fx(\n    world_point: Vector2,\n    velocity_px_s: Vector2,\n    size_px: float,\n    submerged_fraction: float,\n    submerged_delta: float,\n    angular_velocity_rad_s: float = 0.0,\n    delta: float = 1.0 / 60.0\n) -> void:\n    # Visual-only reaction layer. It never changes depth or momentum, so adding\n    # bubbles/foam cannot re-introduce the old floating-object feedback loop.\n    if world_point.x < world_left or world_point.x >= world_right:\n        return\n    if depth_m_at(world_point.x) <= dry_depth_m:\n        return\n\n    var sy := surface_y_at(world_point.x)\n    var half_size := maxf(size_px * 0.5, cell_size_px)\n    var speed := velocity_px_s.length()\n    var edge_speed := absf(angular_velocity_rad_s) * half_size\n    var activity_speed := maxf(speed, edge_speed)\n    var wet := clampf(submerged_fraction, 0.0, 1.0)\n    var crossing := absf(submerged_delta)\n    var near_surface := absf(world_point.y - sy) <= half_size * 1.45\n\n    # Any material can carry/entrain air while moving under water. Density no\n    # longer gates bubbles, which is why cork/wood/plastic now react too.\n    if wet > 0.08 and activity_speed > 34.0 and _bubbles.size() < max_bubbles:\n        var bubble_rate := clampf(\n            1.6 + activity_speed / 52.0 + crossing * 30.0,\n            1.6,\n            18.0\n        )\n        var bubble_p := 1.0 - exp(-bubble_rate * maxf(delta, 0.0))\n        if _rng.randf() < bubble_p:\n            var bubble_count := 2 if activity_speed > 165.0 or crossing > 0.11 else 1\n            for _bubble_index in range(bubble_count):\n                if _bubbles.size() >= max_bubbles:\n                    break\n                var bubble_y := maxf(\n                    world_point.y + _rng.randf_range(-half_size * 0.25, half_size * 0.35),\n                    sy + cell_size_px * 0.75\n                )\n                _bubbles.append({\n                    "pos": Vector2(\n                        world_point.x + _rng.randf_range(-half_size * 0.65, half_size * 0.65),\n                        bubble_y\n                    ),\n                    "rise": _rng.randf_range(20.0, 48.0),\n                    "drift": _rng.randf_range(-9.0, 9.0),\n                    "size": cell_size_px * (0.5 if _rng.randf() < 0.55 else 1.0),\n                    "life": _rng.randf_range(3.6, 5.4)\n                })\n\n    # Foam is tied to surface-crossing energy, not mere presence at the surface.\n    # Fast entry/exit, translation or rotation can create it; resting floaters cannot.\n    var energetic_surface_motion := (\n        absf(velocity_px_s.y) > 52.0\n        or edge_speed > 68.0\n        or crossing > 0.022\n    )\n    if near_surface and energetic_surface_motion and activity_speed > 44.0:\n        var foam_rate := clampf(\n            4.5 + activity_speed / 24.0 + crossing * 58.0,\n            4.5,\n            24.0\n        )\n        var foam_p := 1.0 - exp(-foam_rate * maxf(delta, 0.0))\n        if _rng.randf() < foam_p:\n            var foam_count := 2 if activity_speed > 125.0 or crossing > 0.07 else 1\n            var intensity := clampf(0.38 + activity_speed / 420.0 + crossing * 1.8, 0.38, 0.95)\n            for foam_index in range(foam_count):\n                var offset := (float(foam_index) - float(foam_count - 1) * 0.5) * half_size * 0.65\n                _spawn_foam(world_point.x + offset, intensity)\n\n'''
world = replace_once(world, "func register_underwater_motion(\n", activity_fx + "func register_underwater_motion(\n", "activity fx insertion")
WORLD.write_text(world, encoding="utf-8")

body = BODY.read_text(encoding="utf-8")
body_anchor = '''    _apply_ground_piston_coupling(delta)\n\n    if submerged_fraction <= 0.0005:\n'''
body_new = '''    _apply_ground_piston_coupling(delta)\n\n    _water.register_object_activity_fx(\n        global_position,\n        linear_velocity,\n        maxf(object_size_px.x, object_size_px.y),\n        submerged_fraction,\n        submerged_fraction - _previous_submerged_fraction,\n        angular_velocity,\n        delta\n    )\n\n    if submerged_fraction <= 0.0005:\n'''
body = replace_once(body, body_anchor, body_new, "built-in body activity fx")
BODY.write_text(body, encoding="utf-8")

component = COMPONENT.read_text(encoding="utf-8")
component_anchor = '''    _apply_ground_piston_coupling(delta)\n\n    if submerged_fraction <= 0.0005:\n'''
component_new = '''    _apply_ground_piston_coupling(delta)\n\n    _water.register_object_activity_fx(\n        _body.global_position,\n        _body.linear_velocity,\n        maxf(object_size_px.x, object_size_px.y),\n        submerged_fraction,\n        submerged_fraction - _previous_submerged_fraction,\n        _body.angular_velocity,\n        delta\n    )\n\n    if submerged_fraction <= 0.0005:\n'''
component = replace_once(component, component_anchor, component_new, "drop-in component activity fx")
COMPONENT.write_text(component, encoding="utf-8")

print("Reactive bubbles/foam patch applied successfully.")
