# BoneLab BASESKIN Retarget Reference

## Goal

Juno is again the canonical active 2D rig. BASESKIN is a frozen byte-identical snapshot of the complete Juno payload created for retarget experiments and regression checks.

## Current Oathwake / Alabaster target semantics

The visible 2D limb chains are not a name-for-name match with common 3D humanoid skeletons.

```text
root
└─ spine
   └─ trunk
      └─ neck
         └─ head

shoulderL  (attachment / pivot)
└─ armL    (first visible upper-arm segment)
   └─ forarmL
      └─ handL

shoulderR  (attachment / pivot)
└─ armR
   └─ forarmR
      └─ handR

hipL       (attachment / pivot)
└─ legL    (first visible upper-leg segment)
   └─ leg2L
      └─ footL
         └─ toeL

hipR       (attachment / pivot)
└─ legR
   └─ leg2R
      └─ footR
         └─ toeR
```

The important rule is that `shoulderL/R` and `hipL/R` are attachment pivots. They must not be treated as the direct equivalents of the first deforming Mixamo arm/leg segments.

## Canonical 3D interchange skeleton

Use the Mixamo humanoid hierarchy as the first canonical bridge because the existing V7 retarget implementation already reads a `Skeleton3D`, captures REST transforms and composes pose deltas using the real source hierarchy.

```text
mixamorig:Hips
├─ Spine → Spine1 → Spine2 → Neck → Head
├─ LeftShoulder → LeftArm → LeftForeArm → LeftHand
├─ RightShoulder → RightArm → RightForeArm → RightHand
├─ LeftUpLeg → LeftLeg → LeftFoot → LeftToeBase
└─ RightUpLeg → RightLeg → RightFoot → RightToeBase
```

## Proposed semantic map

```text
Mixamo source                 Juno / BASESKIN target
----------------------------------------------------
Hips                         root + root-motion policy
Spine                        spine
Spine1 / Spine2              trunk, distributed torso contribution
Neck                         neck
Head                         head

LeftArm                      armL
LeftForeArm                  forarmL
LeftHand                     handL
RightArm                     armR
RightForeArm                 forarmR
RightHand                    handR

LeftUpLeg                    legL
LeftLeg                      leg2L
LeftFoot                     footL
LeftToeBase                  toeL
RightUpLeg                   legR
RightLeg                     leg2R
RightFoot                    footR
RightToeBase                 toeR
```

Mixamo shoulder joints can contribute clavicle/attachment orientation, but their rotation should not replace the `armL/R` motion. Hip/root translation and yaw need an explicit 3D-to-2D root-motion policy rather than direct angle copying.

## Retarget pipeline

```text
Mixamo FBX --------------------------┐
Rokoko export on Mixamo skeleton ----+--> canonical Skeleton3D
Cascadeur animation on Mixamo rig ---┘
                                             |
                                             v
                                  capture REST + POSE
                                             |
                                             v
                              global delta = REST^-1 * POSE
                                             |
                                             v
                          semantic + axis projection 3D -> 2D
                                             |
                                             v
                          nodeXfm(root) + boneRot(target bones)
                                             |
                                             v
                                      Juno / BASESKIN
```

## Why source files are not expected to look alike

Alabaster/Juno gameplay animation data is already a baked 2D representation. Frames carry root/node transforms (`nodeXfm`) and scalar target-bone rotations (`boneRot`). Mixamo, Cascadeur and Rokoko interchange normally arrives as 3D joint animation data in formats such as FBX/glTF/BVH. The common thing is the evolving pose, not the serialization.

Therefore the correct bridge is semantic retargeting from a sampled 3D pose into Juno's 2D pose vocabulary. Trying to normalize the raw source files into an Alabaster-shaped file before understanding REST space, hierarchy and axes would discard exactly the information required to retarget correctly.

## V7 direction

Keep the V7 approach: sample the imported 3D skeleton, compare POSE against REST in hierarchical/global space, then project that delta into Juno's 2D bone semantics. Do not return to direct name-copy or raw Euler-copy retargeting.
