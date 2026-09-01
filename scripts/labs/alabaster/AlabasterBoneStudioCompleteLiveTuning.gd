extends "res://scripts/labs/alabaster/AlabasterBoneStudioJunoBaseLiveTuning.gd"

# Compatibility leaf kept as the stable dynamic-load target for Bone Studio.
# The inherited chain already provides DEFAULT, JUNO, DUMMY and JUNO BASE:
# LiveTuningDefault owns DEFAULT and JunoBaseLiveTuning adds JUNO BASE while
# removing the legacy Male target. Keeping this leaf intentionally empty avoids
# duplicating parent constants/controls and preserves the proven parser chain.
