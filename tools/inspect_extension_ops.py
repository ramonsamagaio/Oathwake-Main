import bpy
for op in (bpy.ops.extensions.package_install,bpy.ops.extensions.package_install_files,bpy.ops.preferences.extension_url_drop):
 print(op.idname(),[(p.identifier,p.type,p.is_required) for p in op.get_rna_type().properties])

