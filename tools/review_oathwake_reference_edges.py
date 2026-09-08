"""QA-only comparisons from Godot captures and the supplied reference images."""
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/terrain/reference-edge-revision'
ref=Image.open(ROOT/'docs/resources/source_copies/harmony-meadow-user.png').convert('RGB')
before=Image.open(OUT/'world-0-before.png').convert('RGB')
after=Image.open(OUT/'world-0-after.png').convert('RGB')
# Reference crop shows the requested material finish. The two game crops are
# exactly the same camera/location; no changes to the production images.
board=Image.new('RGB',(1120,490),'#30352c');d=ImageDraw.Draw(board)
items=[('REFERENCIA',(450,440,610,600),ref,2,(8,34)),
       ('ANTES NO GODOT',(305,105,425,245),before,3,(348,34)),
       ('AGORA NO GODOT',(305,105,425,245),after,3,(736,34))]
for title,box,im,factor,pos in items:
    d.text((pos[0],12),title,fill='#ddd9be')
    crop=im.crop(box);crop=crop.resize((crop.width*factor,crop.height*factor),Image.Resampling.NEAREST)
    board.paste(crop,pos)
d.text((8,462),'Referencia e jogo tem escalas diferentes. Antes/agora: mesmo ponto, seed e camera.',fill='#ddd9be')
board.save(OUT/'reference-comparison.png')
# Broad comparison preserves the full native game view rather than re-framing
# an unrelated part of the procedural world.
board=Image.new('RGB',(1000,1400),'#30352c');d=ImageDraw.Draw(board)
d.text((8,5),'ANTES',fill='white');board.paste(before,(0,20))
d.text((8,705),'AGORA',fill='white');board.paste(after,(0,720))
board.save(OUT/'world-before-after.png')
print(str(OUT/'reference-comparison.png'))
