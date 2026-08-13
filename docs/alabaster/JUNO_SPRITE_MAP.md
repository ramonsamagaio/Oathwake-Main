# Juno sprite-sheet map

Source: supplied `juno.json` default figure + supplied 672×240 `juno.png`. Atlas coordinates use `[x, y, width, height]`.

This is the reference map for the Godot lab and for the later annotated image of the sheet.

## Main character pieces

| Rig node | GFX | Atlas range | Facing | Pivot X/Y | Z | Texture rule |
|---|---:|---|---|---|---:|---|
| `root/top` secondary | 1 | `[288,84,12,8]` | `FACE_8_MIRR` | `0.5 / 0.5` | -7 | `ROTATE` |
| `top` | 0 | `[288,0,12,12]` | `FACE_16` | `0.5 / 0.333333` | -1 | `ROTATE` |
| `head` | 0 | `[0,0,20,20]` | `FACE_16_MIRR` | `0.5 / 0.5` | 2 | `ROTATE` |
| `head` detail | 1 | `[588,36,8,8]` | simple | `0.375 / 0.5` | -1 | none |
| `headGear` | 0 | `[528,108,16,16]` | `FACE_16_MIRR` | `0.4375 / 0.5` | 0 | none |
| `tailEnd` idle | 0 | `[360,100,8,28]` | `FACE_4_MIRR` | `0.5 / 0.0714286` | -2 | `ROTATE_SCALE` |
| `eyes` default | 0 | `[180,0,12,8]` | `FACE_16_MIRR_FO` | `0.5 / 0.125` | 4 | `ROTATE` |
| `eyes` down | 0 | `[180,32,12,8]` | `FACE_16_MIRR_FO` | `0.5 / 0.125` | 4 | `ROTATE` |
| `eyes` up | 0 | `[180,64,12,8]` | `FACE_16_MIRR_FO` | `0.5 / 0.125` | 4 | `ROTATE` |
| `eyes` side | 0 | `[180,96,12,8]` | front-only / flipped | `0.5 / 0.125` | 4 | `ROTATE` |
| `armL` primary | 0 | `[632,64,8,8]` | `FACE_8_MIRR` | `0.375 / 0.375` | 1 | `ROTATE` |
| `armL` joint/segment | 1 | `[608,76,8,8]` | `FACE_4_MIRR` | `0.375 / 0.875` | 0 | `PARENT_ROTATE_CUT` |
| `armR` primary | 0 | `[608,36,8,8]` | `FACE_4_MIRR_FLIP` | `0.375 / 0.25` | 1 | `ROTATE` |
| `armR` joint/segment | 1 | `[608,60,8,8]` | `FACE_4_MIRR_FLIP` | `0.375 / 0.875` | 0 | `PARENT_ROTATE_CUT` |
| `handL` | 0 | `[632,0,8,8]` | `FACE_8_MIRR` | `0.375 / 1.0` | 2 | `PARENT_ROTATE_SCALE` |
| `handR` | 0 | `[632,0,8,8]` | `FACE_8_MIRR_FLIP` | `0.375 / 1.0` | 2 | `PARENT_ROTATE_SCALE` |
| `fingerL` | 0 | `[632,40,8,8]` | `FACE_8_MIRR` | `0.375 / 0.5` | 2 | `PARENT_ROTATE` |
| `fingerR` | 0 | `[632,40,8,8]` | `FACE_8_MIRR_FLIP` | `0.375 / 0.5` | 2 | `PARENT_ROTATE` |
| `bottom` front layer | 0 | `[480,48,12,12]` | `FACE_16_MIRR` | `0.5 / 0.416667` | 1 | `ROTATE` |
| `bottom` back layer | 1 | `[480,36,12,12]` | `FACE_16_MIRR` | `0.5 / 0.42` | -3 | `ROTATE` |
| `legL` | 0 | `[544,0,8,12]` | `FACE_8` | `0.375 / 0.833333` | 4 | `PARENT_ROTATE_SCALE` |
| `legR` | 0 | `[480,0,8,12]` | `FACE_8` | `0.375 / 0.833333` | 4 | `PARENT_ROTATE_SCALE` |
| `footL` | 0 | `[608,0,8,12]` | `FACE_4_MIRR_FLIP` | `0.5 / 0.75` | 0 | `PARENT_ROTATE_SCALE` |
| `footR` | 0 | `[608,0,8,12]` | `FACE_4_MIRR` | `0.5 / 0.75` | 0 | `PARENT_ROTATE_SCALE` |
| `toeL` | 0 | `[348,84,8,8]` | `FACE_16_MIRR_FLIP` | `0.25 / 0.375` | 0 | `ROTATE` |
| `toeR` | 0 | `[348,84,8,8]` | `FACE_16_MIRR` | `0.25 / 0.375` | 0 | `ROTATE` |

## Other authored variants in the same sheet

These are not required for the first WASD test but are preserved in the source mapping:

- head sleep: `[180,116,20,20]`;
- tail subtle: `[308,100,16,28]`;
- tail wave: `[324,100,12,28]`;
- tail swing left/right family: `[384,100,16,28]`;
- finger stretched: `[632,96,8,8]`;
- arm alternate: `[488,108,8,8]`;
- hyper-eye rows around `x=180, y=24/56/88`;
- flashback and pre-marble variants occupy separate atlas regions and are retained in the runtime source data.

## Rig hierarchy

```text
root
├── top
│   ├── head
│   │   ├── headGear
│   │   ├── tail
│   │   │   └── tailEnd
│   │   └── eyes
│   ├── shoulderL
│   │   └── armL
│   │       └── handL
│   │           └── fingerL
│   │               └── weaponL
│   └── shoulderR
│       └── armR
│           └── handR
│               └── fingerR
│                   └── weaponR
├── bottom
│   ├── hipL
│   │   └── legL
│   │       └── footL
│   │           └── toeL
│   └── hipR
│       └── legR
│           └── footR
│               └── toeR
└── weaponBelt
```

Important base positions from the supplied figure:

- `root`: `[0,0,1.3125]`
- `top`: `[0,0,0.4375]`
- `head`: `[0,0,0.4375]`
- shoulders: `±0.1666667` on X, `-0.125` on Z
- arm child offsets: `±0.0833333` on X, `-0.3125` on Z
- hips: `±0.125` on X
- legs: `-0.5` on Z
- feet: another `-0.5` on Z
- toes: `+0.25` on Y

## Facing convention used by the reconstruction

`FACE_16` uses 22.5° sectors. The lab maps 0° to South/front, 90° to East/right, 180° to North/back, and 270° to West/left. `FACE_8` and `FACE_4` use the same convention with 45° and 90° sectors.

`*_MIRR` modes reuse the authored half of the atlas and horizontally mirror the opposite half. `*_FLIP` modes invert the requested horizontal orientation. Front-only modes hide pieces outside their valid sector.

The `refAngles` arrays in the source are not discarded. They are treated as authored orientation references after a directional cell has been selected, which allows the selected pixel piece to rotate only through the residual angle instead of continuously smearing one flat sprite around 360°.

## Animation subset loaded by the WASD lab

- `idle`: source `frameCnt=32`, source `frameRepeat=3`;
- `walk`: source `frameCnt=30`, source `frameRepeat=2`;
- `run`: source key data is loaded exactly from the supplied figure subset.

The lab evaluates the sparse `nodeXfm` keys over the same node hierarchy. This is the critical part of the Alabaster-style approach: movement comes primarily from the rig and directional sprite selection, not from a conventional full-body sprite sheet for every animation frame.
