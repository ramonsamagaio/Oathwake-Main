import bpy

def trigger_login():
    try:
        result = bpy.ops.higgsfield.login()
        print("HIGGSFIELD_LOGIN", result)
    except Exception as exc:
        print("HIGGSFIELD_LOGIN_ERROR", repr(exc))
    return None

bpy.app.timers.register(trigger_login, first_interval=8.0)
