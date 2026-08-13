class_name PixelWaterVisualFX2D
extends Node2D

## Presentation-only underwater pass for PixelWaterWorld2D.
##
## This node never changes water depth, momentum, buoyancy or object physics.
## It redraws the current wet columns on top of the world with a screen-reading
## shader, giving submerged content a blue tint, subtle depth darkening/blur and
## procedural pixel light shafts in sufficiently large water bodies.

@export_category("Master")
@export var fx_enabled: bool = true

@export_category("Underwater look")
@export_range(40.0, 500.0, 10.0) var full_effect_depth_px: float = 220.0
@export_range(0.0, 0.5, 0.01) var base_tint_strength: float = 0.14
@export_range(0.0, 0.3, 0.01) var deep_tint_extra: float = 0.055
@export_range(0.0, 0.25, 0.005) var depth_darkening: float = 0.055
@export_range(0.0, 2.0, 0.05) var max_blur_lod: float = 0.55
@export var shallow_tint: Color = Color(0.82, 0.94, 1.0, 1.0)
@export var deep_tint: Color = Color(0.72, 0.86, 0.98, 1.0)

@export_category("Large-water light shafts")
@export var light_shafts_enabled: bool = true
@export_range(40.0, 800.0, 10.0) var large_water_min_width_px: float = 220.0
@export_range(20.0, 400.0, 10.0) var large_water_min_depth_px: float = 90.0
@export_range(10.0, 3000.0, 10.0) var large_water_min_volume_liters: float = 220.0
@export_range(0.0, 0.5, 0.01) var ray_strength: float = 0.11
@export_range(1.0, 16.0, 1.0) var ray_pixel_step: float = 6.0
@export_range(80.0, 520.0, 5.0) var ray_period_px: float = 285.0
@export_range(0.0, 2.0, 0.01) var ray_speed: float = 0.20
@export var ray_color: Color = Color(0.72, 0.94, 1.0, 1.0)

const FX_SHADER := preload("res://addons/pixel_water/water_visual_fx.gdshader")

var _water: PixelWaterWorld2D
var _fx_material: ShaderMaterial

func _ready() -> void:
    _water = get_parent() as PixelWaterWorld2D
    if _water == null:
        push_error("PixelWaterVisualFX2D must be a child of PixelWaterWorld2D.")
        set_process(false)
        visible = false
        return

    # Absolute Z keeps this pass above normal world sprites/physics bodies while
    # CanvasLayer UI still renders above it.
    z_as_relative = false
    z_index = 80

    _fx_material = ShaderMaterial.new()
    _fx_material.shader = FX_SHADER
    material = _fx_material

    visible = fx_enabled
    set_process(fx_enabled)
    _sync_material()
    queue_redraw()

func set_fx_enabled(value: bool) -> void:
    fx_enabled = value
    visible = value
    set_process(value)
    if value:
        _sync_material()
        queue_redraw()

func is_fx_enabled() -> bool:
    return fx_enabled

func _process(_delta: float) -> void:
    if not fx_enabled or _water == null:
        return
    _sync_material()
    queue_redraw()

func _sync_material() -> void:
    if _fx_material == null:
        return
    _fx_material.set_shader_parameter("shallow_tint", shallow_tint)
    _fx_material.set_shader_parameter("deep_tint", deep_tint)
    _fx_material.set_shader_parameter("base_tint_strength", base_tint_strength)
    _fx_material.set_shader_parameter("deep_tint_extra", deep_tint_extra)
    _fx_material.set_shader_parameter("depth_darkening", depth_darkening)
    _fx_material.set_shader_parameter("max_blur_lod", max_blur_lod)
    _fx_material.set_shader_parameter("ray_color", ray_color)
    _fx_material.set_shader_parameter("ray_strength", ray_strength if light_shafts_enabled else 0.0)
    _fx_material.set_shader_parameter("ray_pixel_step", ray_pixel_step)
    _fx_material.set_shader_parameter("ray_period_px", ray_period_px)
    _fx_material.set_shader_parameter("ray_speed", ray_speed)

func _draw() -> void:
    if not fx_enabled or _water == null:
        return

    var cell_size := maxf(_water.cell_size_px, 1.0)
    var cell_count := maxi(
        1,
        int(ceil((_water.world_right - _water.world_left) / cell_size))
    )
    var ray_mask := _build_large_water_mask(cell_count, cell_size)

    # Stable one-cell quads avoid giant-polygon triangulation. Vertex colors are
    # used only as shader data. Alpha is deliberately ZERO: if the shader ever
    # fails to compile, the fallback primitive is invisible instead of exposing
    # the red/green/blue data channels as giant colored blocks.
    for i in range(cell_count):
        var x0 := _water.world_left + float(i) * cell_size
        var x1 := minf(x0 + cell_size + 0.35, _water.world_right)
        var sample_x := minf(x0 + cell_size * 0.5, _water.world_right - 0.001)
        var depth_m := _water.depth_m_at(sample_x)
        if depth_m <= _water.dry_depth_m:
            continue

        var floor_y := _water.floor_y_at(sample_x)
        var surface_y := _water.surface_y_at(sample_x)
        if surface_y != surface_y or floor_y != floor_y:
            continue
        if absf(surface_y) > 1000000.0 or absf(floor_y) > 1000000.0:
            continue

        surface_y = clampf(surface_y, floor_y - 2000.0, floor_y)
        var depth_px := maxf(floor_y - surface_y, 0.0)
        if depth_px <= 0.5:
            continue

        var column_depth_factor := clampf(
            depth_px / maxf(full_effect_depth_px, 1.0),
            0.0,
            1.0
        )
        var ray_flag := 1.0 if ray_mask[i] != 0 else 0.0

        var points := PackedVector2Array([
            Vector2(x0, surface_y),
            Vector2(x1, surface_y),
            Vector2(x1, floor_y),
            Vector2(x0, floor_y)
        ])
        var top_data := Color(0.0, ray_flag, column_depth_factor, 0.0)
        var bottom_data := Color(1.0, ray_flag, column_depth_factor, 0.0)
        var colors := PackedColorArray([
            top_data,
            top_data,
            bottom_data,
            bottom_data
        ])
        draw_polygon(points, colors)

func _build_large_water_mask(cell_count: int, cell_size: float) -> PackedByteArray:
    var mask := PackedByteArray()
    mask.resize(cell_count)
    if not light_shafts_enabled:
        return mask

    var run_start := -1
    var run_max_depth_px := 0.0

    for i in range(cell_count + 1):
        var wet := false
        var depth_px := 0.0
        if i < cell_count:
            var sample_x := minf(
                _water.world_left + (float(i) + 0.5) * cell_size,
                _water.world_right - 0.001
            )
            var depth_m := _water.depth_m_at(sample_x)
            wet = depth_m > _water.dry_depth_m
            depth_px = maxf(depth_m * _water.pixels_per_meter, 0.0)

        if wet:
            if run_start < 0:
                run_start = i
                run_max_depth_px = 0.0
            run_max_depth_px = maxf(run_max_depth_px, depth_px)
            continue

        if run_start >= 0:
            _mark_large_water_run(
                mask,
                run_start,
                i,
                run_max_depth_px,
                cell_size
            )
            run_start = -1
            run_max_depth_px = 0.0

    return mask

func _mark_large_water_run(
    mask: PackedByteArray,
    first: int,
    end_exclusive: int,
    max_depth_px: float,
    cell_size: float
) -> void:
    if end_exclusive <= first:
        return

    var width_px := float(end_exclusive - first) * cell_size
    if width_px < large_water_min_width_px or max_depth_px < large_water_min_depth_px:
        return

    var left_x := _water.world_left + float(first) * cell_size
    var right_x := minf(
        _water.world_left + float(end_exclusive) * cell_size,
        _water.world_right
    )
    var liters := _water.volume_liters_in_range(left_x, right_x)
    if liters < large_water_min_volume_liters:
        return

    for i in range(first, mini(end_exclusive, mask.size())):
        mask[i] = 1
