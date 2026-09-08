import bpy

zip_path = r"C:\Users\ramon\Downloads\higgsfield_blender-1.5.50.zip"
print("HIGGSFIELD_INSTALL_START", zip_path)
try:
    result = bpy.ops.preferences.extension_install(
        filepath=zip_path,
        enable_on_install=True,
        repo="",
    )
    print("HIGGSFIELD_EXTENSION_RESULT", result)
except Exception as exc:
    print("HIGGSFIELD_EXTENSION_ERROR", repr(exc))
try:
    result = bpy.ops.preferences.addon_install(filepath=zip_path, overwrite=True)
    print("HIGGSFIELD_ADDON_RESULT", result)
except Exception as exc:
    print("HIGGSFIELD_ADDON_ERROR", repr(exc))
print("HIGGSFIELD_INSTALL_DONE")
