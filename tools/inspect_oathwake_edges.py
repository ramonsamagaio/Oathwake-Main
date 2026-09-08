"""Read-only image diagnostics and immutable snapshots for the border revision."""
from pathlib import Path
import json,shutil
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/terrain/reference-edge-revision'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'
NAMES=['plainsgrass1','plainsgrass2','plainsgrass3','short_grass','tall_grass','oathwake_road']
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'before').mkdir(exist_ok=True)
for n in NAMES:
    for ext in ['.png','.pxo']:
        backup=OUT/'before'/(n+ext)
        if not backup.exists():shutil.copy2(DEST/(n+ext),backup)
for name in ['oathwake-tilesets-manifest.json','oathwake-road-manifest.json']:
    backup=OUT/'before'/name
    if not backup.exists():shutil.copy2(ROOT/'docs/terrain'/name,backup)
board=Image.new('RGB',(768,480),'#b9a372');d=ImageDraw.Draw(board)
for j,name in enumerate(['short_grass','plainsgrass3','plainsgrass1']):
    im=Image.open(DEST/(name+'.png')).convert('RGBA')
    large=im.crop((0,0,64,96)).resize((256,384),Image.Resampling.NEAREST)
    board.paste(large,(j*256,24),large)
    d.text((j*256+5,5),name,fill='#262b24')
board.save(OUT/'before-atlas-cells.png')
ref=Image.open(ROOT/'docs/resources/source_copies/harmony-meadow-user.png')
arid=Image.open(ROOT/'docs/resources/source_copies/harmony-arid-user.png')
board=Image.new('RGB',(960,450),'#30352c');d=ImageDraw.Draw(board)
for i,(im,box,label) in enumerate([(ref,(450,440,610,600),'REFERENCE meadow / sand'),
    (ref,(785,390,945,550),'REFERENCE earth / sand'),
    (arid,(560,365,720,525),'REFERENCE arid')]):
    crop=im.crop(box).resize((320,320),Image.Resampling.NEAREST)
    board.paste(crop,(i*320,30));d.text((i*320+6,8),label,fill='white')
board.save(OUT/'reference-crops.png')
print(json.dumps({'snapshots':len(NAMES),'output':str(OUT)}))
