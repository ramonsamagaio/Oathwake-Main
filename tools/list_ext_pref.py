import bpy
print([x for x in dir(bpy.context.preferences.extensions) if not x.startswith("__")])

