extends RefCounted
class_name AlabasterJunoAtlas

# Lossless palette-packed form of the user-provided 672x240 juno.png.
# Split into text parts so the lab stays self-contained in Git.
const PNG_PARTS := [
	"res://data/labs/alabaster/juno_atlas_00.part",
	"res://data/labs/alabaster/juno_atlas_01.part",
	"res://data/labs/alabaster/juno_atlas_02.part",
	"res://data/labs/alabaster/juno_atlas_03.part"
]

static func create_texture() -> Texture2D:
	var encoded := ""
	for path in PNG_PARTS:
		if not FileAccess.file_exists(path):
			push_error("AlabasterJunoAtlas: missing atlas part %s" % path)
			return null
		encoded += FileAccess.get_file_as_string(path).strip_edges()
	var raw := Marshalls.base64_to_raw(encoded)
	var image := Image.new()
	var err := image.load_png_from_buffer(raw)
	if err != OK:
		push_error("AlabasterJunoAtlas: failed to decode embedded juno.png, error %s" % err)
		return null
	return ImageTexture.create_from_image(image)
