"""Native stone silhouettes/facets -> Pixelorama coordinates, never image resampling.

Pillow is used only after the editable PXO round trip, for QA and contact sheets.
The twenty existing procedural records retain their exact frame/anchor contracts.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import author_oathwake_native as native
from author_oathwake_native import Canvas, color

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/resources/native/stones'
DEST = ROOT / 'assets/sprites/world/procedural/terrain/oathwake_tilesets/resources/stones_native'
# Charcoal crevices, warm slate planes, restrained ochre reflected light.
P = list(map(color, ['393b3a','4b4c48','5d5f57','717269','85857a','999788','aba591']))
M = list(map(color, ['414b38','566346','6d7951','8a9060','a0a06d']))
C = list(map(color, ['533e33','78533e','9a6d4b','b88a5a','c6a275']))


def facet(c, top, foot, crack=None, chips=()):
    """Six-to-eight-vertex top, three-point base: every piece is positioned by hand."""
    a,b,d,e,f,g = top
    left,low,right = foot
    shape=Canvas(c.w,c.h)
    shape.polygon([a,b,d,e,right,low,left,g],P[0],'stone')
    mask=set(shape.p)
    c.paste(shape,0,0)
    c.polygon([g,f,e,right,low,left],P[1],'stone',mask)
    c.polygon([f,e,right,low,(f[0]-1,low[1]-1)],P[1],'stone',mask)
    c.polygon([g,f,(f[0]-1,low[1]-1),left],P[2],'stone',mask)
    c.polygon([(g[0]+1,g[1]),(f[0]-2,f[1]),(f[0]-3,low[1]-5),
               (left[0]+3,left[1]-2)],P[3],'stone',mask)
    c.polygon([(e[0],e[1]+1),(right[0]-1,right[1]-4),(low[0]+4,low[1]-4),
               (f[0]+3,f[1]+3)],P[2],'stone',mask)
    c.polygon(top,P[3],'stone',mask)
    cx=sum(x for x,y in top)//6;cy=sum(y for x,y in top)//6
    inset=[(x+(1 if x<cx else -1),y+(1 if y<cy else -1)) for x,y in top]
    c.polygon(inset,P[4],'stone',mask)
    c.polygon([(a[0]+1,a[1]),(b[0],b[1]+1),(cx+1,cy-1),
               (cx-3,cy+2),(g[0]+2,g[1]-1)],P[5],'stone',mask)
    c.polygon([(cx+2,cy+1),(e[0]-1,e[1]),(f[0],f[1]-1),(cx,cy+3)],P[3],'stone',mask)
    # Lit bevel occupies the upper-left edge, not an all-around bright outline.
    c.path([g,a,b],P[5],'stone',mask)
    c.path([g,(g[0]+1,g[1]+2),(left[0]+1,left[1]-2)],P[4],'stone',mask)
    c.path([f,(f[0],f[1]+2),(low[0]-1,low[1]-2)],P[2],'stone',mask)
    c.path([d,e],P[3],'stone',mask)
    c.path([left,low,right],P[0],'stone',mask)
    c.path([e,right],P[1],'stone',mask)
    # Shallow chips at the foot break the flat faces into visible mineral slabs.
    if low[1]-f[1]>=10:
        c.polygon([(left[0]+1,left[1]-4),(left[0]+5,left[1]-5),
                   (left[0]+6,left[1]-1),(left[0]+2,left[1])],P[2],'stone',mask)
        c.path([(left[0]+2,left[1]-5),(left[0]+4,left[1]-5)],P[4],'stone',mask)
        c.polygon([(low[0]+3,low[1]-7),(right[0]-2,right[1]-4),
                   (right[0]-2,right[1]-1),(low[0]+2,low[1]-2)],P[0],'stone',mask)
        c.path([(f[0]-4,f[1]+4),(f[0]-6,f[1]+5),(f[0]-5,f[1]+8)],P[2],'stone',mask)
    # Short broken mineral planes, individually specified; no surface noise.
    for x,y in chips:
        c.path([(x,y),(x+2,y),(x+3,y-1)],P[5],'stone',mask)
        c.path([(x+1,y+1),(x+3,y+1)],P[3],'stone',mask)
    if crack:
        c.path(crack,P[1],'stone',mask)
        c.path([(x+1,y) for x,y in crack[1:]],P[4],'stone',mask)


def big(i):
    c=Canvas(48,48)
    # Different rock architectures; no scaling/mirroring an existing bitmap.
    if i==0: # squat broken granite
        facet(c,[(13,18),(24,12),(34,16),(37,24),(26,29),(10,26)],[(8,39),(23,46),(39,39)],[(25,14),(26,19),(23,22),(26,29)],[(16,20),(29,19)])
        facet(c,[(31,32),(37,29),(43,33),(44,39),(38,43),(29,39)],[(29,44),(37,46),(44,44)])
    elif i==1: # paired low blocks
        facet(c,[(25,22),(32,16),(39,20),(41,27),(33,31),(23,28)],[(22,40),(33,44),(43,37)],chips=[(29,24)])
        facet(c,[(7,25),(17,18),(26,20),(29,29),(20,34),(6,32)],[(5,40),(19,46),(30,40)],[(20,20),(18,25),(21,29),(20,34)],[(10,27)])
    elif i==2: # upright fractured block
        facet(c,[(16,11),(23,8),(31,12),(34,20),(25,24),(13,20)],[(10,38),(24,46),(36,38)],[(28,12),(27,17),(29,20)],[(18,15)])
        facet(c,[(31,29),(37,25),(42,29),(44,35),(38,39),(29,35)],[(28,41),(37,46),(44,42)],chips=[(33,31)])
        facet(c,[(7,36),(11,33),(17,35),(18,40),(13,43),(6,41)],[(6,44),(12,46),(18,44)])
    elif i==3: # inclined broad slab
        facet(c,[(9,25),(18,16),(32,15),(39,24),(31,31),(9,33)],[(7,41),(29,46),(41,36)],[(28,16),(26,23),(29,27),(31,31)],[(13,27),(32,22)])
    elif i==4: # low stratified shelves
        facet(c,[(10,31),(25,27),(38,30),(42,36),(31,41),(8,39)],[(7,43),(29,46),(42,42)],chips=[(17,34),(31,34)])
        facet(c,[(11,22),(22,17),(31,19),(35,26),(26,31),(10,29)],[(10,34),(25,38),(36,32)],[(27,19),(26,24),(29,28)],[(15,25)])
    elif i==5: # production tall angular boulder
        facet(c,[(13,15),(23,9),(33,13),(37,22),(27,28),(10,24)],[(8,39),(25,46),(39,38)],[(27,11),(26,17),(23,20),(26,24),(27,28)],[(15,20),(30,17)])
        facet(c,[(29,34),(35,31),(40,34),(41,39),(36,42),(28,39)],[(28,43),(35,46),(42,43)])
    elif i==6: # horizontally split twin
        facet(c,[(25,20),(33,16),(40,20),(42,28),(35,33),(24,29)],[(23,39),(35,45),(43,38)],[(34,18),(32,23),(35,27)],[(27,23)])
        facet(c,[(8,24),(16,17),(25,20),(28,29),(19,34),(6,30)],[(5,39),(18,46),(29,40)],chips=[(12,25)])
    elif i==7: # narrow column with a low shoulder
        facet(c,[(15,13),(23,10),(29,14),(31,21),(24,26),(13,22)],[(10,38),(24,46),(33,37)],[(25,12),(24,19),(27,22)],[(16,17)])
        facet(c,[(30,27),(35,25),(41,30),(42,35),(36,39),(28,35)],[(28,42),(36,45),(43,40)],chips=[(32,31)])
    elif i==8: # stepped block
        facet(c,[(11,16),(23,12),(32,17),(35,25),(26,30),(10,26)],[(9,40),(25,46),(38,38)],[(24,14),(23,21),(27,25)],[(15,21),(28,21)])
        facet(c,[(8,32),(13,30),(19,33),(20,37),(14,41),(6,37)],[(5,42),(13,46),(21,43)])
    else: # low asymmetric crag
        facet(c,[(8,24),(17,17),(30,18),(36,25),(28,31),(6,30)],[(5,39),(25,45),(37,37)],[(22,18),(20,23),(23,28)],[(11,27)])
        facet(c,[(31,28),(36,25),(42,28),(44,35),(38,39),(29,35)],[(28,41),(38,46),(44,41)],chips=[(33,31)])
    return c


def small(i):
    c=Canvas(32,32)
    forms=[
        ([(10,12),(16,7),(21,10),(23,17),(17,21),(8,17)],[(7,26),(16,30),(25,24)]),
        ([(7,17),(15,11),(22,14),(25,20),(18,24),(6,22)],[(5,27),(17,30),(26,26)]),
        ([(11,10),(17,8),(23,13),(24,19),(16,22),(9,18)],[(7,25),(16,30),(25,25)]),
        ([(8,15),(17,11),(24,15),(25,21),(18,25),(7,21)],[(7,27),(18,30),(26,26)]),
        ([(10,12),(15,8),(21,11),(23,17),(16,22),(8,18)],[(6,25),(16,30),(24,24)]),
        ([(9,16),(16,11),(22,15),(24,22),(16,26),(7,22)],[(6,27),(16,30),(25,27)]),
        ([(8,16),(17,12),(23,16),(25,21),(18,25),(7,22)],[(6,27),(17,30),(26,26)]),
        ([(11,13),(18,9),(24,14),(25,20),(17,24),(9,19)],[(7,26),(17,30),(26,25)]),
    ]
    top,foot=forms[i]
    facet(c,top,foot,[top[1],(top[1][0]-1,top[1][1]+5),top[4]],[(top[0][0]+2,top[0][1]+2)])
    return c


def copper():
    c=Canvas(16,16)
    facet(c,[(4,4),(8,2),(12,5),(13,9),(8,12),(2,8)],[(1,12),(7,15),(14,12)])
    for x,y in [(4,5),(9,7),(6,11)]:
        c.polygon([(x,y-1),(x+2,y),(x+2,y+2),(x,y+3),(x-1,y+1)],C[0],'copper',set(c.p))
        c.polygon([(x,y),(x+1,y),(x+1,y+2),(x,y+2)],C[2],'copper')
        c.dot(x,y,C[4],'copper');c.dot(x+1,y,C[3],'copper')
    return c


def mossy():
    c=Canvas(64,80)
    facet(c,[(17,25),(31,17),(45,22),(50,36),(36,44),(13,37)],[(10,61),(34,75),(53,59)],[(36,20),(34,29),(39,34),(36,44)],[(22,30),(42,30)])
    facet(c,[(40,49),(48,45),(57,51),(59,59),(50,65),(38,59)],[(36,70),(50,77),(60,70)],chips=[(44,54)])
    facet(c,[(10,57),(17,52),(25,56),(27,64),(18,69),(7,63)],[(6,71),(17,78),(28,72)],chips=[(12,60)])
    mask=set(c.p)
    # Moss grows on shelves, never as a turf diamond attached to the base.
    for poly in [[(17,27),(22,24),(29,23),(28,27),(25,29),(21,30),(22,33),(16,35),(14,33)],
                 [(41,24),(45,25),(48,31),(47,35),(43,34),(42,30),(39,29)],
                 [(39,50),(44,47),(49,48),(51,50),(46,52),(44,55),(39,56)],
                 [(10,58),(16,55),(20,56),(20,59),(15,61),(11,61)]]:
        c.polygon(poly,M[1],'moss',mask)
        upper=[p for p in poly if p[1]<sum(q[1] for q in poly)/len(poly)]
        if len(upper)>2:c.polygon(upper,M[2],'moss',mask)
    for path in [[(18,27),(21,26),(23,26)],[(24,25),(26,24)],[(15,32),(18,31)],
                 [(42,26),(44,27),(45,29)],[(42,50),(45,49)],[(13,58),(16,57)]]:
        c.path(path,M[3],'moss',mask)
    return c


def build():
    big_atlas=Canvas(240,96);small_atlas=Canvas(128,64)
    records=[]
    for family,count,size,cols,atlas,name,prefix,builder in [
      ('rock',10,48,5,big_atlas,'oathwake-rocks','romestead_rock_',big),
      ('stone',8,32,4,small_atlas,'oathwake-stones','romestead_stone_',small)]:
        for i in range(count):
            c=builder(i);x=(i%cols)*size;y=(i//cols)*size
            assert len(c.components())==1,(family,i,[len(k) for k in c.components()])
            atlas.paste(c,x,y)
            records.append({'resource':family+str(i+1),'sprite':prefix+str(i+1),'atlas':name,
                            'region':[x,y,size,size],'pixels':len(c.p),'colors':len(set(c.p.values()))})
    for rid,sid,name,c in [('copper_ore_node','romestead_copper_ore','oathwake-copper',copper()),
                            ('mossy_rock1','romestead_mossy_boulder','oathwake-mossy-boulder',mossy())]:
        assert len(c.components())==1
        records.append({'resource':rid,'sprite':sid,'atlas':name,'region':[0,0,c.w,c.h],
                        'pixels':len(c.p),'colors':len(set(c.p.values()))})
    return {'oathwake-rocks':big_atlas,'oathwake-stones':small_atlas,
            'oathwake-copper':copper(),'oathwake-mossy-boulder':mossy()},records


def verify(publish=False):
    from PIL import Image,ImageDraw
    atlases,records=build()
    for name,c in atlases.items():
        im=Image.open(OUT/(name+'.png')).convert('RGBA')
        assert im.size==(c.w,c.h) and im.tobytes()==c.bytes(),name+' PXO export mismatch'
        assert (OUT/(name+'.pxo')).stat().st_size>0
        assert set(im.getchannel('A').tobytes())=={0,255}
    original=json.loads((OUT/'sprites-before.json').read_text())
    current=json.loads((ROOT/'data/sprites.json').read_text())
    resources=json.loads((ROOT/'data/resources.json').read_text())
    assert resources==json.loads((OUT/'resources-before.json').read_text()),'Resource gameplay changed during art slice'
    expected=json.loads(json.dumps(original))
    for rec in records:
        sid=rec['sprite'];s=original[sid]
        assert [s['region'][k] for k in ('x','y','w','h')]==rec['region']
        expected[sid]['texture_path']='res://'+str((DEST/(rec['atlas']+'.png')).relative_to(ROOT)).replace('\\','/')
    assert current==original or current==expected,'Unexpected concurrent sprite catalog changes; reconcile before publishing'
    if publish:
        DEST.mkdir(parents=True,exist_ok=True)
        for name in atlases:
            for ext in ['.png','.pxo']:shutil.copy2(OUT/(name+ext),DEST/(name+ext))
            import_file=DEST/(name+'.png.import')
            if import_file.exists():
                settings=import_file.read_text()
                settings=settings.replace('process/fix_alpha_border=true','process/fix_alpha_border=false')
                import_file.write_text(settings)
        # Replace only exact texture strings inside selected sprite records, keeping formatting/order.
        text=(ROOT/'data/sprites.json').read_text()
        for rec in records:
            sid=rec['sprite'];start=text.index('\n\t"'+sid+'": {');end=text.find('\n\t}',start)+4
            part=text[start:end]
            before=original[sid]['texture_path'];after=expected[sid]['texture_path']
            assert before in part or after in part
            text=text[:start]+part.replace(before,after)+text[end:]
        assert json.loads(text)==expected
        (ROOT/'data/sprites.json').write_text(text)
    report={'records':records,'authorship':'Explicit native silhouettes, planes and cracks in Pixelorama',
            'alpha':'binary','components_per_sprite':1,'gameplay_unchanged':True,
            'atlases':{n:{'size':[c.w,c.h],'rgba_sha256':hashlib.sha256(c.bytes()).hexdigest()} for n,c in atlases.items()},
            'published':publish or current==expected}
    (OUT/'qa.json').write_text(json.dumps(report,indent=2)+'\n')
    # Native and integer-enlarged exports; original catalog frames are shown beside them.
    board=Image.new('RGB',(1250,980),(50,54,48));d=ImageDraw.Draw(board)
    for i,rec in enumerate(records):
        col=i%5;row=i//5;bx=col*250;by=row*220
        s=original[rec['sprite']];old=Image.open(ROOT/s['texture_path'].removeprefix('res://')).convert('RGBA')
        x,y,w,h=rec['region'];old=old.crop((x,y,x+w,y+h))
        new=Image.open(OUT/(rec['atlas']+'.png')).convert('RGBA').crop((x,y,x+w,y+h))
        d.text((bx+8,by+8),rec['resource']+'   antes / novo',fill=(204,200,174))
        for im,px in [(old,bx+2),(new,bx+125)]:
            zoom=2 if h<=80 else 1
            bigim=im.resize((w*zoom,h*zoom),Image.Resampling.NEAREST)
            board.paste(bigim,(px,by+30),bigim)
        board.paste(new,(bx+90,by+188-h//2),new)
    board.save(OUT/'review.png')
    print(json.dumps({'verified':len(records),'atlases':len(atlases),'published':report['published']}))


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--verify' in sys.argv or '--publish' in sys.argv:verify('--publish' in sys.argv)
    else:
        for name in ['sprites','resources']:
            p=OUT/(name+'-before.json')
            if not p.exists():shutil.copy2(ROOT/('data/'+name+'.json'),p)
        atlases,records=build();native.OUT=OUT
        calls=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}]
        for name,c in atlases.items():calls+=native.requests_for(name,c)[0]
        (OUT/'requests.json').write_text(json.dumps(calls))
        (OUT/'manifest.json').write_text(json.dumps({'records':records},indent=2))
        print(json.dumps({'sprites':len(records),'pixels':sum(len(c.p) for c in atlases.values()),'requests':len(calls)}))
