extends "res://scripts/creatures/CreatureSystemLab.gd"

const TEST_FLOOR_COLOR := Color("11141b")
const GRID_COLOR := Color(0.18, 0.21, 0.28, 0.55)
const CENTER_GRID_COLOR := Color(0.28, 0.33, 0.42, 0.65)
const TEST_AREA := Rect2(Vector2(345.0, 130.0), Vector2(1190.0, 640.0))
const CREATURE_BOUNDS := Rect2(Vector2(370.0, 150.0), Vector2(1140.0, 590.0))


func _ready() -> void:
	super._ready()
	for creature: ProceduralCreature in _creatures:
		_configure_lab_creature(creature)
	queue_redraw()


func _select_creature(index: int) -> void:
	super._select_creature(index)
	if _active != null:
		_configure_lab_creature(_active)
		# Bounds in this polish layer are slightly tighter than the base lab.
		# Reseed only after those final bounds exist so the first route is valid.
		_active.reseed(_active.random_seed)


func _spawn_stress_test() -> void:
	super._spawn_stress_test()
	for creature: ProceduralCreature in _stress_instances:
		_configure_lab_creature(creature)
		# Stress clones used to keep a route chosen before their final bounds were
		# installed, which made some of them walk into an edge for an entire route.
		creature.reseed(creature.random_seed)


func _configure_lab_creature(creature: ProceduralCreature) -> void:
	if creature == null:
		return
	# Preserve common lab wiring such as the LOD anchor, then tighten the roaming
	# contract for the visible test area.
	super._configure_lab_creature(creature)
	creature.set_movement_bounds(CREATURE_BOUNDS)

	# No creature-specific forced wander here. Each solver owns its own motion
	# character now, so authoring values match what production will actually use.


func _draw() -> void:
	# Same floor language as AlabasterMechanicLab: #11141b, 64 px grid and
	# stronger center axes. The UI panel remains a separate Control layer.
	draw_rect(Rect2(Vector2.ZERO, Vector2(1600.0, 900.0)), TEST_FLOOR_COLOR, true)

	for x in range(0, 1601, 64):
		draw_line(Vector2(x, 0), Vector2(x, 900), GRID_COLOR, 1.0)
	for y in range(0, 901, 64):
		draw_line(Vector2(0, y), Vector2(1600, y), GRID_COLOR, 1.0)

	draw_line(Vector2(0, 450), Vector2(1600, 450), CENTER_GRID_COLOR, 1.0)
	draw_line(Vector2(800, 0), Vector2(800, 900), CENTER_GRID_COLOR, 1.0)

	# A restrained outline makes the actual roaming contract visible without
	# changing the Mechanic Lab floor underneath it.
	draw_rect(TEST_AREA, Color(0.38, 0.46, 0.55, 0.28), false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(355, 112),
		"PROCEDURAL CREATURE SYSTEM LAB",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		22,
		Color("c7d4c7")
	)
