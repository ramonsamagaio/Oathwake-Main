class_name WaterMaterialPresets
extends RefCounted

# Approximate bulk densities in kg/m^3. Hollow objects use an effective bulk density.
const PRESETS := {
    "Cork": {
        "density": 240.0,
        "drag": 1.05,
        "color": Color("#9b5f36"),
        "label": "Cork"
    },
    "Pine wood": {
        "density": 520.0,
        "drag": 1.00,
        "color": Color("#b97943"),
        "label": "Pine wood"
    },
    "Oak wood": {
        "density": 700.0,
        "drag": 1.00,
        "color": Color("#80502f"),
        "label": "Oak wood"
    },
    "Hollow plastic": {
        "density": 180.0,
        "drag": 0.85,
        "color": Color("#ef7b2d"),
        "label": "Hollow plastic"
    },
    "Rubber": {
        "density": 930.0,
        "drag": 1.15,
        "color": Color("#a83d76"),
        "label": "Rubber"
    },
    "Ice": {
        "density": 917.0,
        "drag": 0.85,
        "color": Color("#bfe9f3"),
        "label": "Ice"
    },
    "Aluminum": {
        "density": 2700.0,
        "drag": 0.80,
        "color": Color("#aab5c0"),
        "label": "Aluminum"
    },
    "Glass": {
        "density": 2500.0,
        "drag": 0.90,
        "color": Color("#76c7d5"),
        "label": "Glass"
    },
    "Stone": {
        "density": 2600.0,
        "drag": 1.10,
        "color": Color("#777a78"),
        "label": "Stone"
    },
    "Steel": {
        "density": 7850.0,
        "drag": 0.75,
        "color": Color("#59636e"),
        "label": "Steel"
    }
}

static func names() -> Array[String]:
    var result: Array[String] = []
    for key in PRESETS.keys():
        result.append(str(key))
    return result

static func get_preset(material_name: String) -> Dictionary:
    if PRESETS.has(material_name):
        return PRESETS[material_name]
    return PRESETS["Pine wood"]
