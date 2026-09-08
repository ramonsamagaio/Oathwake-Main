"""QA-only contact sheets and animation made from actual Godot captures."""
from pathlib import Path
from PIL import Image,ImageDraw
OUT=Path(__file__).resolve().parents[1]/'docs/characters/mooncloak'
clips=['idle','walk','run','atkSwordN1','guard','dead']
board=Image.new('RGB',(640,480))
for i,clip in enumerate(clips):board.paste(Image.open(OUT/('pose-'+clip+'.png')),(0,i*80))
board.resize((1280,960),Image.Resampling.NEAREST).save(OUT/'godot-preview.png')
idle=Image.open(OUT/'pose-idle.png')
portrait=idle.crop((320,12,400,78))
portrait.resize((400,330),Image.Resampling.NEAREST).save(OUT/'mooncloak-front.png')
frames=[Image.open(OUT/('motion-%02d.png'%i)).crop((320,12,400,78)).resize((400,330),Image.Resampling.NEAREST) for i in range(16)]
frames[0].save(OUT/'mooncloak-walk.gif',save_all=True,append_images=frames[1:],duration=[31,32]*8,loop=0,disposal=2)
print('Engine review: six poses, eight directions; native front enlarged 5x.')
