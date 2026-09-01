extends "res://scripts/labs/alabaster/AlabasterBoneStudioJunoBaseLiveTuning.gd"

# Stable dynamic-load target for Bone Studio Live Tuning. The inherited chain
# owns the complete target set (JUNO, JUNO BASE, DUMMY, DEFAULT). This leaf keeps
# one important cross-workspace contract: when Live Tuning changes the body, the
# shared Import/Retarget + Animator preview selector must reflect that same body
# without replacing the rig a second time.


func _replace_host_rig(profile_id: String) -> bool:
	var replaced := super._replace_host_rig(profile_id)
	if replaced:
		_sync_host_editor_selector(profile_id)
	return replaced


func _sync_host_editor_selector(profile_id: String) -> void:
	if host == null:
		return
	# Live Tuning already installed the correct production rig. Calling the public
	# setter here would construct another rig, so synchronize only the editor UI
	# state and retained profile id through the host's dedicated helper.
	if host.has_method("_sync_editor_preview_selector"):
		host.call("_sync_editor_preview_selector", profile_id)
	if "_editor_preview_profile_id" in host:
		host.set("_editor_preview_profile_id", profile_id)
