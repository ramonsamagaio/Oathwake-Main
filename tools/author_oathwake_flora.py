"""Twelve native 32px plants: authored integer leaf contours, no source resampling.

Production PNG/PXO come only from Pixelorama coordinate edits. Pillow below is
limited to round-trip checking and review boards made from exported pixels.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

import author_oathwake_native as native
from author_oathwake_native import Canvas, color

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/resources/native/flora'
DEST = ROOT / 'assets/sprites/world/procedural/terrain/oathwake_tilesets'
NAME = 'flora_ground_plants'
L = list(map(color, ['293730','344638','42543f','536548','7a895b','a2a976','b6b888']))
D = list(map(color, ['393b30','4e5038','686744','8a8051','a39065','c0ac7c','d0c6a0']))
BLUE = list(map(color, ['343c43','4b5968','737e8b','a2a7a0']))
IVORY = list(map(color, ['626348','817959','a69d76','d0c6a0']))
PURPLE = list(map(color, ['423e49','625669','8b7b92','aa929a']))


def leaf(c, points, ridge, shade=3, pal=L):
    """Explicit native contour + light-facing plane; under-edge remains dark."""
    mask = Canvas(32,32)
    mask.polygon(points, pal[1])
    c.paste(mask,0,0)
    inside = {p for p in mask.p if all((p[0]+dx,p[1]+dy) in mask.p
              for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])}
    for x,y in inside:
        c.dot(x,y,pal[shade])
    # Larger leaves have an asymmetric light-facing plane, not just a thin vein.
    if len(inside)>9 and len(ridge)>1:
        plane=[ridge[-1],points[1],ridge[0]]
        c.polygon(plane,pal[min(4,shade+1)],mask=inside)
    # The ridge belongs to the lit half, deliberately interrupted near its base.
    c.path(ridge,pal[min(5,shade+1)],'leaf',set(mask.p))


def lance(c, base, left, tip, right, ridge, shade=3,pal=L):
    leaf(c,[base,left,tip,right],ridge,shade,pal)


def heart(c,points,ridge,shade=3):
    leaf(c,points,ridge,shade)


def stem(c,points,pal=L):
    c.path(points,pal[1],'stem')
    # A second, lit stem pixel at the foot keeps flowers visually attached.
    x,y=points[0]
    c.dot(x+1,y,pal[3],'stem')


def bloom(c,x,y,pal=IVORY):
    pattern=['.02.','2332','1321','.10.']
    for dy,row in enumerate(pattern):
        for dx,s in enumerate(row):
            if s!='.':c.dot(x+dx-1,y+dy-1,pal[int(s)],'petal')


def rosette():
    c=Canvas(32,32)
    lance(c,(15,29),(9,16),(8,10),(15,18),[(14,25),(12,18),(9,12)],2)
    lance(c,(16,29),(16,16),(21,9),(20,23),[(17,26),(18,18),(20,12)],3)
    lance(c,(16,28),(5,24),(2,18),(13,21),[(14,26),(8,23),(4,20)],3)
    heart(c,[(16,29),(6,29),(3,25),(3,22),(8,21),(12,24)],[(12,27),(8,25),(5,23)],3)
    heart(c,[(16,29),(21,19),(27,17),(26,23),(23,27)],[(18,27),(22,22),(25,19)],3)
    heart(c,[(15,30),(20,25),(26,25),(29,28),(24,30),(19,31)],[(18,29),(23,27),(27,28)],3)
    heart(c,[(15,30),(10,30),(7,27),(10,24),(13,25),(16,29)],[(14,29),(11,26),(9,27)],4)
    lance(c,(16,29),(13,22),(14,15),(18,23),[(16,27),(15,22),(14,18)],4)
    return c


def fern():
    c=Canvas(32,32)
    for path in [[(16,30),(12,24),(8,16),(5,13)],[(16,30),(16,22),(19,14),(23,9)],[(16,30),(22,24),(27,21)]]:
        stem(c,path)
    for pts,ridge,s in [
        ([(10,21),(4,20),(2,17),(7,17)],[(8,19),(4,18)],2),
        ([(8,18),(7,12),(5,9),(4,14)],[(6,13),(7,16)],3),
        ([(12,24),(10,17),(12,14),(14,20)],[(12,17),(12,22)],3),
        ([(13,26),(6,25),(3,22),(9,22)],[(11,25),(6,23)],3),
        ([(19,15),(17,11),(18,8),(21,11)],[(19,14),(19,10)],2),
        ([(21,12),(23,7),(25,6),(24,10)],[(22,11),(24,8)],3),
        ([(19,17),(24,12),(28,12),(24,16)],[(21,16),(26,13)],3),
        ([(17,21),(13,15),(14,12),(17,16)],[(16,19),(15,14)],3),
        ([(17,22),(22,18),(27,18),(24,21),(21,23)],[(19,22),(24,19)],4),
        ([(16,27),(12,21),(13,18),(16,22)],[(15,24),(14,20)],3),
        ([(17,27),(22,23),(25,24),(22,27)],[(19,26),(23,25)],3),
        ([(22,24),(24,19),(27,16),(26,21)],[(24,21),(26,18)],2),
        ([(16,30),(9,29),(6,26),(11,26)],[(14,29),(9,27)],3),
        ([(16,30),(21,27),(27,27),(24,30)],[(19,29),(24,28)],3)]:
        leaf(c,pts,ridge,s)
    return c


def grass(dry=False,curved=False):
    c=Canvas(32,32);p=D if dry else L
    blades=[((15,30),(9,19),(5,14),(11,26)),((15,30),(8,27),(3,23),(9,29)),
        ((15,30),(12,16),(10,7),(15,23)),((16,30),(15,18),(18,5),(18,23)),
        ((17,30),(19,18),(24,11),(21,25)),((17,30),(23,24),(28,22),(24,28)),
        ((15,30),(10,24),(8,19),(14,25)),((16,30),(17,23),(21,18),(20,27))]
    if curved:
        blades=[((15,30),(8,23),(2,22),(10,27)),((15,30),(10,17),(6,12),(13,22)),
            ((15,30),(15,12),(19,8),(17,20)),((16,30),(20,17),(27,15),(22,22)),
            ((16,30),(23,25),(29,26),(23,28)),((15,30),(10,28),(5,26),(12,30)),
            ((16,30),(19,23),(25,20),(21,27))]
    for i,(b,l,t,r) in enumerate(blades):
        mid=(round((l[0]+r[0])/2),round((l[1]+r[1])/2))
        lance(c,b,l,t,r,[b,mid,t],2+i%3,p)
    # Low overlapping blades give the tuft a rooted, leafy body. These are
    # individual bent leaves, with gaps above the foot, never a ground patch.
    for b,l,t,r,ridge,s in [
      ((12,30),(7,23),(5,20),(10,24),[(12,29),(9,24),(6,21)],3),
      ((13,30),(11,21),(12,14),(14,25),[(13,28),(12,22),(12,17)],3),
      ((15,30),(15,22),(18,17),(17,27),[(15,29),(16,24),(18,19)],4),
      ((17,30),(20,26),(25,25),(21,29),[(18,29),(22,27),(24,26)],3),
      ((19,30),(20,22),(24,18),(22,27),[(20,29),(21,24),(23,20)],3),
      ((16,31),(13,28),(11,24),(15,26),[(16,30),(14,28),(12,25)],4),
      ((18,31),(17,26),(18,23),(20,29),[(18,30),(18,26)],3)]:
        lance(c,b,l,t,r,ridge,s,p)
    return c


def nettle():
    c=Canvas(32,32)
    stem(c,[(16,30),(15,20),(16,8)])
    for pts,vein,s in [
      ([(16,13),(12,10),(13,6),(15,4),(18,7),(17,11)],[(15,11),(15,6)],3),
      ([(15,18),(10,17),(9,15),(7,14),(8,10),(12,12)],[(14,16),(10,13)],3),
      ([(16,19),(17,13),(21,10),(23,11),(22,14),(23,15),(20,18)],[(17,17),(20,13)],3),
      ([(16,24),(9,23),(7,21),(5,20),(6,16),(10,17),(13,20)],[(14,22),(9,19)],2),
      ([(16,25),(19,19),(23,17),(26,17),(25,21),(26,22),(22,24)],[(18,23),(23,20)],3),
      ([(16,30),(10,29),(7,26),(8,24),(12,24),(14,26)],[(14,28),(10,26)],3),
      ([(16,30),(19,26),(24,25),(26,27),(22,30),(19,31)],[(18,29),(23,27)],4)]:
        heart(c,pts,vein,s)
    return c


def flower(kind):
    c=Canvas(32,32)
    heads={
      'ivory':[(10,12),(17,7),(24,13)],
      'blue':[(9,13),(16,6),(23,10)],
      'purple':[(11,10),(17,5),(23,13)]}[kind]
    pal={'ivory':IVORY,'blue':BLUE,'purple':PURPLE}[kind]
    for x,y in heads:stem(c,[(16,30),(x,22),(x,y+1)])
    for x,y in heads:
        leaf(c,[(x,y+11),(x-4,y+8),(x-5,y+5),(x-2,y+6)],[(x-1,y+9),(x-3,y+7)],3)
        leaf(c,[(x,y+10),(x+2,y+6),(x+5,y+5),(x+3,y+9)],[(x+1,y+9),(x+3,y+7)],2)
    for pts,vein,s in [
      ([(16,29),(10,25),(5,18),(10,19),(15,25)],[(14,26),(8,21)],2),
      ([(15,29),(12,19),(13,15),(16,21)],[(15,26),(14,20)],3),
      ([(16,28),(19,19),(24,16),(23,21),(20,25)],[(18,25),(22,19)],3),
      ([(16,30),(8,29),(5,25),(10,25),(14,27)],[(13,28),(8,26)],3),
      ([(16,30),(21,25),(27,23),(25,27),(20,30)],[(19,28),(24,25)],3),
      ([(16,30),(13,27),(13,23),(17,25),(19,29)],[(16,28),(15,25)],4)]:
        leaf(c,pts,vein,s)
    leaf(c,[(15,29),(9,24),(8,20),(12,20),(16,26)],[(14,27),(11,23),(10,21)],3)
    leaf(c,[(16,30),(18,23),(20,21),(23,23),(20,28)],[(18,28),(20,24)],4)
    for x,y in heads:
        if kind=='purple':
            for dx,dy in [(-1,4),(1,2),(0,0)]:bloom(c,x+dx,y+dy,pal)
        elif kind=='blue':
            bloom(c,x-1,y+3,pal);bloom(c,x,y,pal)
        else:
            stem(c,[(x,y+5),(x-3,y+3)])
            bloom(c,x-3,y+2,pal);bloom(c,x+1,y,pal)
    return c


def sword():
    c=Canvas(32,32)
    specs=[((16,30),(7,23),(2,15),(11,20)),((16,30),(10,15),(9,5),(15,17)),
      ((16,30),(17,14),(23,6),(22,20)),((16,30),(22,23),(29,17),(25,27)),
      ((16,30),(6,30),(3,26),(11,26)),((16,30),(12,21),(15,11),(18,24)),
      ((16,30),(22,26),(28,27),(24,31))]
    for i,(b,l,t,r) in enumerate(specs):
        lance(c,b,l,t,r,[b,((l[0]+r[0])//2,(l[1]+r[1])//2),t],2+i%3)
    return c


def clover():
    c=Canvas(32,32)
    for pts,vein,s in [
      ([(16,29),(11,23),(9,18),(10,15),(14,15),(17,18),(17,24)],[(15,25),(13,19),(12,17)],2),
      ([(16,29),(19,19),(22,16),(26,17),(27,20),(24,24),(20,26)],[(18,26),(23,20)],3),
      ([(16,29),(8,27),(4,24),(3,20),(6,19),(11,21),(14,25)],[(13,26),(8,23),(5,21)],3),
      ([(16,30),(10,31),(6,29),(6,26),(9,24),(12,25),(16,28)],[(13,28),(10,26),(8,27)],3),
      ([(16,30),(20,26),(24,25),(28,27),(27,29),(24,31),(19,31)],[(19,29),(24,27)],3),
      ([(16,29),(13,23),(14,20),(17,19),(20,22),(18,27)],[(16,27),(16,23),(17,21)],4)]:
        heart(c,pts,vein,s)
    return c


def sorrel():
    c=Canvas(32,32)
    for path in [[(16,30),(9,22),(8,16)],[(16,30),(16,19),(19,12)],[(16,30),(23,22),(26,18)]]:stem(c,path)
    for pts,vein,s in [
      ([(9,24),(5,21),(4,16),(6,13),(9,14),(11,18),(11,22)],[(8,22),(7,16)],3),
      ([(16,23),(14,18),(15,13),(18,9),(21,10),(21,14),(18,20)],[(16,20),(18,13)],3),
      ([(21,25),(22,19),(26,15),(29,15),(29,19),(25,23)],[(23,23),(27,18)],2),
      ([(16,29),(10,28),(6,25),(6,23),(10,22),(14,25)],[(13,27),(9,24)],3),
      ([(16,30),(19,25),(24,24),(27,26),(24,29),(19,31)],[(19,28),(24,26)],3),
      ([(16,30),(13,25),(13,21),(16,19),(19,21),(18,27)],[(16,27),(16,22)],4)]:
        leaf(c,pts,vein,s)
    return c


def build():
    names=['broad_rosette','fern','meadow_grass','nettle','ivory_herb','dry_sedge',
           'sword_leaves','blue_herb','low_clover','purple_herb','sorrel','bent_grass']
    plants=[rosette(),fern(),grass(),nettle(),flower('ivory'),grass(True),
            sword(),flower('blue'),clover(),flower('purple'),sorrel(),grass(curved=True)]
    atlas=Canvas(192,64)
    for i,c in enumerate(plants):
        assert len(c.components())==1,(names[i],[len(a) for a in c.components()])
        assert all(1<=x<=30 and 2<=y<=31 for x,y in c.p)
        atlas.paste(c,(i%6)*32,(i//6)*32)
    records=[{'name':n,'cell':[i%6,i//6],'pixels':len(c.p),'components':len(c.components()),
       'bounds':[min(x for x,y in c.p),min(y for x,y in c.p),max(x for x,y in c.p)+1,max(y for x,y in c.p)+1]}
       for i,(n,c) in enumerate(zip(names,plants))]
    return atlas,records


def verify(publish=False):
    from PIL import Image,ImageDraw
    atlas,plants=build()
    im=Image.open(OUT/(NAME+'.png')).convert('RGBA')
    assert (OUT/(NAME+'.pxo')).stat().st_size>0
    assert im.size==(192,64) and im.tobytes()==atlas.bytes(),'Pixelorama export differs from native coordinates'
    assert set(im.getchannel('A').tobytes())=={0,255}
    report={'size':list(im.size),'rgba_sha256':hashlib.sha256(im.tobytes()).hexdigest(),
      'colors':len(set(atlas.p.values())),'plants':plants,'alpha':'binary',
      'authorship':'Integer leaf contours and pixel edits in Pixelorama; no image resampling.'}
    (OUT/'qa.json').write_text(json.dumps(report,indent=2))
    # Review image only: integer enlargement, never fed into a production sprite.
    board=Image.new('RGB',(960,430),(35,40,35));d=ImageDraw.Draw(board)
    for i,p in enumerate(plants):
        x=(i%6)*160;y=(i//6)*205
        crop=im.crop((i%6*32,i//6*32,i%6*32+32,i//6*32+32))
        large=crop.resize((128,128),Image.Resampling.NEAREST)
        board.paste(large,(x+16,y+24),large)
        board.paste(crop,(x+16,y+165),crop)
        d.text((x+52,y+167),p['name'].replace('_','\n'),fill=(192,194,174))
    board.save(OUT/'review.png')
    terrain_capture=OUT/'on-terrain-native.png'
    if terrain_capture.exists():
        capture=Image.open(terrain_capture)
        capture.resize((capture.width*2,capture.height*2),Image.Resampling.NEAREST).save(OUT/'on-terrain.png')
    if publish:
        for ext in ['.png','.pxo']:shutil.copy2(OUT/(NAME+ext),DEST/(NAME+ext))
        manifest_path=ROOT/'docs/terrain/oathwake-tilesets-manifest.json'
        manifest=json.loads(manifest_path.read_text())
        rec=next(r for r in manifest['assets'] if r['file']==NAME+'.png')
        assert hashlib.sha256(Path(rec['source']).read_bytes()).hexdigest()==rec['source_sha256']
        original=Image.open(rec['source']).convert('RGBA')
        before=list(original.get_flattened_data());after=list(im.get_flattened_data())
        rec.update(expected_rgba_sha256=report['rgba_sha256'],
            changed_pixels=sum(a!=b for a,b in zip(before,after)),
            alpha_changes=sum(a[3]!=b[3] for a,b in zip(before,after)),
            pixel_count=len(atlas.p),
            revision='2026-09-08 native 32x32 Pixelorama botanical contours; docs/resources/native/flora/qa.json')
        manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'verified':len(plants),'pixels':len(atlas.p),'colors':report['colors'],'published':publish}))


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--verify' in sys.argv or '--publish' in sys.argv:verify('--publish' in sys.argv)
    else:
        for ext in ['.png','.pxo']:
            backup=OUT/('before'+ext)
            if not backup.exists():shutil.copy2(DEST/(NAME+ext),backup)
        atlas,plants=build()
        native.OUT=OUT
        calls,record=native.requests_for(NAME,atlas)
        (OUT/'requests.json').write_text(json.dumps([{'tool':'pixelorama_status'}, {'tool':'pixelorama_project_info'}]+calls))
        (OUT/'expected.json').write_text(json.dumps(record,indent=2))
        print(json.dumps({'plants':len(plants),'pixels':len(atlas.p),'requests':len(calls)}))
