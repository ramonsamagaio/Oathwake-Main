import bpy,sys
print("MODULE",end=" ")
try:
 import higgsfield_blender as h
 print("OK",h)
except Exception as e: print("ERR",repr(e))
print("EXT_REPO",bpy.context.preferences.extensions.active_repo)

