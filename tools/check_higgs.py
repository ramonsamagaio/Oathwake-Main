import bpy
print("EXT_PREF",[x for x in dir(bpy.context.preferences.extensions) if "enable" in x or "package" in x or "repo" in x])
print("ADDON",__import__("addon_utils").check("higgsfield_blender"))

