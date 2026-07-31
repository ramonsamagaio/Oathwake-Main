class_name PinnedActiveFrameProjectedShadow
extends "res://scripts/effects/ProfiledProjectedShadow.gd"

# Compatibility entry point kept for existing scenes, validators and runtime
# references. Solar shadows now warp the current frame's alpha silhouette toward
# the real feet, trunk or prop contact pixels. Local-light shadows keep using the
# exact active-frame projection from the parent chain.
