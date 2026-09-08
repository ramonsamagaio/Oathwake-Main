extends RefCounted
## Harmonize runtime-generated augment layers with the authored Pixelorama sheets.
## Alpha and geometry stay unchanged; resources and lighting are never processed.

static func style_generated_texture(texture: Texture2D, layer_name: String) -> Texture2D:
	var image := texture.get_image()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source := image.get_pixel(x,y)
			if source.a <= 0.0:
				continue
			var result := source
			match layer_name:
				"ProceduralRoads":
					result = Color("8a7654")
					if source.r < 0.65:
						result = Color("847050")
					elif source.r > 0.74:
						result = Color("92805c")
				"ProceduralWater":
					if source.r > source.b:
						result = Color("4e5240")
					elif source.b > 0.53:
						result = Color("647971")
					elif source.b < 0.44:
						result = Color("354d4b")
					else:
						result = Color("46625b")
				"ProceduralGroundDetails":
					# Generated soil marks, grass and rubble use the same olive/umber family.
					var luminance := source.r * 0.30 + source.g * 0.59 + source.b * 0.11
					var green := source.g > source.r
					result = Color("65704d") if green else Color("8a7654")
					if luminance < 0.38:
						result = Color("45513e") if green else Color("625640")
					elif luminance > 0.53:
						result = Color("899065") if green else Color("b9a372")
				"ProceduralCliffFinish":
					result = Color("34363a") if source.r < 0.3 else Color("79796a")
			result.a = source.a
			image.set_pixel(x,y,result)
	return ImageTexture.create_from_image(image)
