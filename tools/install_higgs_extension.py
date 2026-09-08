import bpy,os
p=r"C:\Users\ramon\Downloads\higgsfield_blender-1.5.50.zip"
try:
    r=bpy.ops.extensions.package_install_files(directory=os.path.dirname(p),files=[{"name":os.path.basename(p)}],repo="user_default",enable_on_install=True,overwrite=True)
    print("PKG",r)
except Exception as e: print("ERR",repr(e))

