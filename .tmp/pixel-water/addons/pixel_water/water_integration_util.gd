class_name WaterIntegrationUtil
extends RefCounted

## Small shared helpers used by the drop-in integration components.
## These helpers do not change PixelWaterWorld2D or the original demo bodies.

static func find_water(context: Node, world_x: float) -> PixelWaterWorld2D:
    if context == null or not context.is_inside_tree():
        return null

    var candidates: Array[Node] = []
    for group_name in ["pixel_water_world", "pixel_water_container", "water_simulator"]:
        var grouped := context.get_tree().get_nodes_in_group(group_name)
        for node in grouped:
            if node is PixelWaterWorld2D and not candidates.has(node):
                candidates.append(node)

    var best: PixelWaterWorld2D = null
    var best_distance := INF
    for node in candidates:
        var candidate := node as PixelWaterWorld2D
        if candidate == null:
            continue
        var dx := 0.0
        if world_x < candidate.world_left:
            dx = candidate.world_left - world_x
        elif world_x > candidate.world_right:
            dx = world_x - candidate.world_right
        if dx < best_distance:
            best_distance = dx
            best = candidate
    return best

static func collision_entries(body: Node2D) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if body == null or not body.is_inside_tree():
        return result

    var inverse_body := body.global_transform.affine_inverse()
    var shape_nodes := body.find_children("*", "CollisionShape2D", true, false)
    for node in shape_nodes:
        var collision := node as CollisionShape2D
        if collision == null or collision.disabled or collision.shape == null:
            continue
        result.append({
            "kind": "shape",
            "shape": collision.shape,
            "transform": inverse_body * collision.global_transform
        })

    var polygon_nodes := body.find_children("*", "CollisionPolygon2D", true, false)
    for node in polygon_nodes:
        var collision := node as CollisionPolygon2D
        if collision == null or collision.disabled or collision.polygon.size() < 3:
            continue
        result.append({
            "kind": "polygon",
            "polygon": collision.polygon,
            "transform": inverse_body * collision.global_transform
        })

    return result

static func collision_bounds_local(
    body: Node2D,
    fallback_size_px: Vector2 = Vector2(48.0, 48.0)
) -> Rect2:
    var entries := collision_entries(body)
    if entries.is_empty():
        var fallback := Vector2(
            maxf(fallback_size_px.x, 2.0),
            maxf(fallback_size_px.y, 2.0)
        )
        return Rect2(-fallback * 0.5, fallback)

    var min_point := Vector2(INF, INF)
    var max_point := Vector2(-INF, -INF)
    var found := false

    for entry in entries:
        var transform: Transform2D = entry["transform"]
        var points := _entry_outline_points(entry)
        for point in points:
            var p := transform * point
            min_point.x = minf(min_point.x, p.x)
            min_point.y = minf(min_point.y, p.y)
            max_point.x = maxf(max_point.x, p.x)
            max_point.y = maxf(max_point.y, p.y)
            found = true

    if not found:
        var fallback := Vector2(
            maxf(fallback_size_px.x, 2.0),
            maxf(fallback_size_px.y, 2.0)
        )
        return Rect2(-fallback * 0.5, fallback)

    var size := max_point - min_point
    size.x = maxf(size.x, 2.0)
    size.y = maxf(size.y, 2.0)
    return Rect2(min_point, size)

static func point_inside_entries(local_point: Vector2, entries: Array[Dictionary]) -> bool:
    if entries.is_empty():
        return true

    for entry in entries:
        var transform: Transform2D = entry["transform"]
        var p := transform.affine_inverse() * local_point
        var kind := String(entry.get("kind", ""))

        if kind == "polygon":
            var polygon: PackedVector2Array = entry["polygon"]
            if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(p, polygon):
                return true
            continue

        var shape := entry.get("shape") as Shape2D
        if shape == null:
            continue
        if shape is RectangleShape2D:
            var half := (shape as RectangleShape2D).size * 0.5
            if absf(p.x) <= half.x and absf(p.y) <= half.y:
                return true
        elif shape is CircleShape2D:
            var radius := (shape as CircleShape2D).radius
            if p.length_squared() <= radius * radius:
                return true
        elif shape is CapsuleShape2D:
            var capsule := shape as CapsuleShape2D
            var radius := capsule.radius
            var straight_half := maxf(capsule.height * 0.5 - radius, 0.0)
            if absf(p.y) <= straight_half and absf(p.x) <= radius:
                return true
            var cap_center_y := straight_half if p.y >= 0.0 else -straight_half
            if p.distance_squared_to(Vector2(0.0, cap_center_y)) <= radius * radius:
                return true
        elif shape is ConvexPolygonShape2D:
            var polygon := (shape as ConvexPolygonShape2D).points
            if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(p, polygon):
                return true

    return false

static func estimate_area_ratio(
    bounds: Rect2,
    entries: Array[Dictionary],
    columns: int = 8,
    rows: int = 8
) -> float:
    if entries.is_empty():
        return 1.0
    var cols := maxi(columns, 2)
    var row_count := maxi(rows, 2)
    var inside := 0
    var total := cols * row_count
    for y_index in range(row_count):
        var ty := (float(y_index) + 0.5) / float(row_count)
        var y := lerpf(bounds.position.y, bounds.end.y, ty)
        for x_index in range(cols):
            var tx := (float(x_index) + 0.5) / float(cols)
            var x := lerpf(bounds.position.x, bounds.end.x, tx)
            if point_inside_entries(Vector2(x, y), entries):
                inside += 1
    return clampf(float(inside) / float(maxi(total, 1)), 0.05, 1.0)

static func _entry_outline_points(entry: Dictionary) -> PackedVector2Array:
    if String(entry.get("kind", "")) == "polygon":
        return entry.get("polygon", PackedVector2Array())

    var shape := entry.get("shape") as Shape2D
    if shape == null:
        return PackedVector2Array()

    if shape is RectangleShape2D:
        var half := (shape as RectangleShape2D).size * 0.5
        return PackedVector2Array([
            Vector2(-half.x, -half.y),
            Vector2(half.x, -half.y),
            Vector2(half.x, half.y),
            Vector2(-half.x, half.y)
        ])

    if shape is CircleShape2D:
        var r := (shape as CircleShape2D).radius
        return PackedVector2Array([
            Vector2(-r, -r),
            Vector2(r, -r),
            Vector2(r, r),
            Vector2(-r, r)
        ])

    if shape is CapsuleShape2D:
        var capsule := shape as CapsuleShape2D
        var half_w := capsule.radius
        var half_h := capsule.height * 0.5
        return PackedVector2Array([
            Vector2(-half_w, -half_h),
            Vector2(half_w, -half_h),
            Vector2(half_w, half_h),
            Vector2(-half_w, half_h)
        ])

    if shape is ConvexPolygonShape2D:
        return (shape as ConvexPolygonShape2D).points

    if shape is SegmentShape2D:
        var segment := shape as SegmentShape2D
        return PackedVector2Array([segment.a, segment.b])

    return PackedVector2Array()
