class_name ProceduralTerrainSampler
extends RefCounted

var profile: ProceduralTerrainProfile

var _macro_noise := FastNoiseLite.new()
var _moisture_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()


func _init(new_profile: ProceduralTerrainProfile = null) -> void:
	if new_profile != null:
		configure(new_profile)


func configure(new_profile: ProceduralTerrainProfile) -> void:
	profile = new_profile
	if profile == null:
		return

	_configure_noise(_macro_noise, profile.world_seed + 101, profile.macro_frequency)
	_configure_noise(_moisture_noise, profile.world_seed + 307, profile.moisture_frequency)
	_configure_noise(_detail_noise, profile.world_seed + 911, profile.detail_frequency)


func sample(world_position: Vector2) -> Dictionary:
	if profile == null:
		return {
			"macro": 0.0,
			"moisture": 0.0,
			"detail": 0.0,
			"grassness": 0.0,
			"grass_density": 0.0,
			"terrain_id": 0,
		}

	var macro := _normalized_noise(_macro_noise, world_position)
	var moisture := _normalized_noise(_moisture_noise, world_position)
	var detail := _normalized_noise(_detail_noise, world_position)

	var grassness := clampf(
		(macro * 0.42) + (moisture * 0.43) + (detail * 0.15) - profile.dirt_bias,
		0.0,
		1.0
	)
	var threshold := profile.grass_tile_threshold
	var density := 0.0
	if grassness >= threshold:
		var range_above_threshold := maxf(0.001, 1.0 - threshold)
		density = clampf((grassness - threshold) / range_above_threshold, 0.0, 1.0)
		density = lerpf(profile.minimum_tuft_density, 1.0, density)

	return {
		"macro": macro,
		"moisture": moisture,
		"detail": detail,
		"grassness": grassness,
		"grass_density": density,
		"terrain_id": 1 if grassness >= threshold else 0,
	}


func is_grass(world_position: Vector2) -> bool:
	return int(sample(world_position).get("terrain_id", 0)) == 1


func grass_density_at(world_position: Vector2) -> float:
	return float(sample(world_position).get("grass_density", 0.0))


func _configure_noise(noise: FastNoiseLite, noise_seed: int, frequency: float) -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.52
	noise.fractal_lacunarity = 2.0


func _normalized_noise(noise: FastNoiseLite, world_position: Vector2) -> float:
	return clampf((noise.get_noise_2d(world_position.x, world_position.y) + 1.0) * 0.5, 0.0, 1.0)
