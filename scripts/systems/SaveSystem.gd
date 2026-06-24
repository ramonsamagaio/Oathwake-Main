extends RefCounted


func save_json(path: String, data: Dictionary) -> String:
	var save_file := FileAccess.open(path, FileAccess.WRITE)
	if save_file == null:
		return "Could not save game to %s" % path

	save_file.store_string(JSON.stringify(data, "\t"))
	return ""


func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": "No save file found at %s" % path,
			"data": {},
		}

	var save_file := FileAccess.open(path, FileAccess.READ)
	if save_file == null:
		return {
			"ok": false,
			"error": "Could not load game from %s" % path,
			"data": {},
		}

	var json := JSON.new()
	var parse_error := json.parse(save_file.get_as_text())
	if parse_error != OK:
		return {
			"ok": false,
			"error": "Could not parse savegame.json at %s" % path,
			"data": {},
		}

	if not json.data is Dictionary:
		return {
			"ok": false,
			"error": "Save file has invalid data.",
			"data": {},
		}

	return {
		"ok": true,
		"error": "",
		"data": json.data,
	}
