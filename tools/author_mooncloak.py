"""Duplicate Wayfarer's native part atlas and author Mooncloak through Pixelorama.
No reference image is resampled. PNG/PXO artwork is exported only by Pixelorama.
"""
import hashlib,json,shutil,sys
from pathlib import Path
from PIL import Image,ImageDraw
import author_oathwake_native as native
from author_oathwake_native import Canvas,color
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/characters/mooncloak'
ASSET=ROOT/'assets/sprites/characters'
P=list(map(color,['17181f','222431','303447','454b64','5c637e','787e95']))
B=list(map(color,['262024','3b3030','58433a','795e4c','9d8065']))
S=list(map(color,['795546','ad8061','d4ac86']))
E=list(map(color,['285578','408db2','75cee8','d5f4fc']))

def hood(tile,row):
    c=Canvas(20,20)
    # Cloth starts filled. Outline ink is applied ONLY at the one-pixel boundary,
    # so unpainted polygon leftovers cannot become a thick black hood/rim.
    c.polygon([(8,4),(12,4),(14,6),(15,9),(16,12),(16,15),(14,18),(11,19),
               (8,19),(5,17),(3,14),(4,10),(5,7)],P[2])
    c.polygon([(3,0),(3,3),(4,5),(6,6),(6,8),(3,7),(2,5),(2,2)],P[2])
    c.polygon([(17,0),(17,3),(16,5),(14,7),(15,8),(17,6),(18,3),(18,1)],P[2])
    # Side views stagger the horns instead of keeping two frontal prongs.
    if tile in (3,4,5):
        for p in list(c.p):
            if p[0]<5 and p[1]<5:c.p.pop(p,None);c.kind.pop(p,None)
    mask=set(c.p)
    edge={p for p in mask if any((p[0]+dx,p[1]+dy) not in mask for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])}
    inside=mask-edge
    c.polygon([(5,10),(6,7),(9,5),(11,5),(9,8),(7,11),(5,15)],P[3],mask=inside)
    c.polygon([(11,6),(13,7),(14,10),(14,13),(12,11),(10,9)],P[3],mask=inside)
    c.path([(6,9),(7,8),(7,7),(9,6)],P[4],mask=inside)
    c.path([(11,7),(12,8),(12,9)],P[4],mask=inside)
    face=Canvas(20,20)
    void=color('12151c')
    if tile<=4:
        shift=min(tile,3);up=-2 if row==5 else (-1 if row==6 else 0)
        left=5+shift;right=15 if tile<3 else 16
        face.polygon([(left+1,12+up),(10+shift,10+up),(right-1,12+up),
                      (right,15+up),(right-2,17),(10+shift//2,18),(left+1,17),(left,15+up)],void,mask=inside)
        opening=set(face.p)
        # Narrow illuminated fold directly bordering the opening, not another
        # thick dark ring. Its shadow falls inside the recess.
        fold={p for p in inside-opening if any((p[0]+dx,p[1]+dy) in opening for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])}
        for x,y in fold:c.dot(x,y,P[3] if x<10+shift and y<16 else P[2])
        c.paste(face,0,0)
        if tile<3:
            for x,y in [(7+shift,14+up),(12+shift,14+up)]:
                c.dot(x,y,E[2],mask=opening);c.dot(x,y-1,E[1],mask=opening)
                c.dot(x+1,y,E[3],mask=opening)
        else:
            c.dot(14,14+up,E[2],mask=opening);c.dot(15,14+up,E[3],mask=opening)
            c.dot(15,13+up,E[1],mask=opening)
    else:
        c.polygon([(8,7),(11,5),(14,8),(15,13),(12,17),(7,17),(5,14)],P[3],mask=inside)
        c.path([(10,7),(11,9),(10,12),(11,15),(10,18)],P[2],mask=inside)
        c.path([(6,11),(7,9),(8,8)],P[4],mask=inside)
    for x,y in edge:c.dot(x,y,P[0],'outline')
    # A soft lit edge keeps narrow tips from reading as solid black rectangles.
    for x,y in [(3,3),(3,4),(4,6),(17,2),(17,3),(16,5)]:
        c.dot(x,y,P[2],mask=mask)
    assert all(p in edge for p,v in c.p.items() if v==P[0]),'Outline ink extends into hood interior'
    assert len(c.components())==1,(tile,row,'detached hood pixels')
    return c

def part(entry,source):
    p=entry['packed'];w,h=p['w'],p['h'];node=entry['owners'][0]['node']
    tile=entry['tile_index'];row=entry['owners'][0]['row']
    if node=='head' and w==20:return hood(tile,row)
    c=Canvas(w,h)
    if node in ('headGear','tailEnd'):return c
    for y in range(h):
        for x in range(w):
            r,g,b,a=source.getpixel((p['x']+x,p['y']+y))
            if not a:continue
            lum=(r+g+b)/3
            level=max(0,min(5,int(lum/39)))
            value=P[level]
            if node.startswith(('foot','toe')):value=B[min(4,int(lum/43))]
            elif node.startswith(('hand','finger')):
                value=S[min(2,int(lum/78))] if y>=h-2 else P[min(3,level)]
            elif node=='bottom' and y<5:value=B[min(4,int(lum/40))]
            c.dot(x,y,value)
    mask=set(c.p)
    if node=='head': # neck cell: enclosed cowl, never exposed skin
        for y in range(h):
            for x in range(w):
                if (x,y) in mask:c.dot(x,y,P[1 if y<h-2 else 2])
    elif node=='top':
        # Plates and crossed leather carry straps remain direction-aware.
        for y in [4,7,10]:
            c.path([(2,y),(w-3,y)],P[1],mask=mask)
            c.path([(3,y-1),(w-4,y-1)],P[3],mask=mask)
        if w==12 and h==12:
            for y in range(2,11):
                x=(2+y//2) if tile<8 else (9-y//2)
                c.dot(x,y,B[1],mask=mask);c.dot(x+1,y,B[3],mask=mask)
            c.path([(3,1),(4,2),(6,3),(8,2),(9,1)],P[3],mask=mask)
        else:c.path([(3,4),(5,5),(8,4)],B[3],mask=mask)
    elif node=='bottom':
        c.path([(2,3),(9,3)],B[3],mask=mask)
        c.path([(5,2),(6,2),(6,4),(5,4)],B[4],mask=mask)
        c.path([(3,7),(3,9),(2,11)],P[3],mask=mask)
        c.path([(8,6),(9,9)],P[2],mask=mask)
    elif node.startswith('arm'):
        for y in [2,5]:
            c.path([(1,y),(w-2,y)],P[3],mask=mask)
            c.path([(2,y-1),(w-3,y-1)],P[4],mask=mask)
    elif node.startswith('leg'):
        c.polygon([(2,2),(4,1),(6,3),(5,7),(3,9),(1,6)],P[2],mask=mask)
        c.path([(3,2),(3,5),(2,6)],P[4],mask=mask)
        c.path([(2,9),(5,9)],P[1],mask=mask)
    elif node.startswith('foot'):
        c.path([(1,3),(6,3)],B[4],mask=mask)
        c.path([(1,4),(6,4)],B[2],mask=mask)
        c.path([(2,h-3),(4,h-3)],B[3],mask=mask)
    return c

def equipment(direction):
    # Eight authored cardinal/diagonal views, each with independent cloth and gear.
    c=Canvas(32,32);g=Canvas(32,32)
    side=direction in (2,6);back=direction in (0,1,7)
    if side:
        contour=[(12,1),(18,1),(21,5),(23,12),(25,21),(23,20),(24,29),(19,26),
                 (18,30),(15,27),(11,29),(11,22),(7,25),(9,15),(10,7)]
    else:
        contour=[(11,1),(20,1),(24,5),(25,11),(28,17),(26,17),(29,26),(24,23),
                 (25,30),(21,28),(20,31),(17,27),(15,30),(13,27),(10,31),(8,27),
                 (5,29),(7,20),(3,24),(5,15),(7,9),(7,5)]
    c.polygon(contour,P[0]);mask=set(c.p)
    c.polygon([(11,2),(19,2),(22,8),(24,17),(23,26),(19,24),(17,29),(15,23),
               (11,27),(9,24),(10,15),(8,16),(10,7)],P[2],mask=mask)
    c.polygon([(11,4),(14,3),(13,11),(11,18),(10,24),(8,26),(10,16)],P[3],mask=mask)
    c.polygon([(17,5),(20,7),(21,15),(23,25),(20,24),(18,16)],P[3],mask=mask)
    c.path([(14,9),(15,15),(14,23),(13,26)],P[1],mask=mask)
    c.path([(11,7),(10,12),(8,17)],P[4],mask=mask)
    if back:c.path([(15,5),(16,8),(17,5)],P[4],mask=mask)
    # Bow carried diagonally, silhouette separated from arrows on the other side.
    bow=[(26,1),(28,1),(26,4),(25,9),(26,14),(25,20),(22,25),(19,27)]
    g.path(bow,P[0]);g.path([(27,2),(25,6),(24,10),(25,15),(24,20),(21,24)],P[3])
    g.path([(26,2),(20,25)],B[2])
    g.polygon([(4,10),(9,7),(13,17),(9,23),(6,19)],B[1])
    g.path([(5,11),(8,11),(11,18),(9,21)],B[3])
    for x,y in [(3,4),(6,2),(8,4)]:
        g.path([(x,y),(x+5,y+11)],B[3])
        g.path([(x-1,y),(x-1,y+2),(x+1,y+4)],P[4])
        g.dot(x,y,P[5]);g.dot(x+1,y+2,P[3])
    if side:
        # Keep the slim side silhouette; reposition only integer-authored pixels.
        g.p={((x+3 if x<16 else x-3),y):v for (x,y),v in g.p.items()}
        g.kind={p:'gear' for p in g.p}
    if direction in (5,6,7):
        for canvas in (c,g):
            canvas.p={(31-x,y):v for (x,y),v in canvas.p.items()};canvas.kind={p:'gear' for p in canvas.p}
    return c,g

def build():
    source=Image.open(ASSET/'WAYFARER.png').convert('RGBA')
    data=json.loads((ROOT/'docs/characters/wayfarer/atlas-manifest.json').read_text())
    main=Canvas(*source.size);records=[]
    for e in data['entries']:
        c=part(e,source);p=e['packed'];main.paste(c,p['x'],p['y'])
        records.append({'key':e['key'],'packed':p,'node':e['owners'][0]['node'],'pixels':len(c.p)})
    gear=Canvas(256,64)
    for i in range(8):
        cape,pack=equipment(i);gear.paste(cape,i*32,0);gear.paste(pack,i*32,32)
    return {'MOONCLOAK':main,'MOONCLOAK_GEAR':gear},records

def verify():
    canvases,records=build();before=json.loads((OUT/'source-hashes.json').read_text())
    for path,sha in before.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==sha,path+' changed'
    for name,c in canvases.items():
        im=Image.open(ASSET/(name+'.png')).convert('RGBA')
        assert im.size==(c.w,c.h) and im.tobytes()==c.bytes(),name+' round trip mismatch'
        assert set(im.getchannel('A').tobytes())=={0,255}
        assert (ASSET/(name+'.pxo')).stat().st_size>0
        im.resize((im.width*4,im.height*4),Image.Resampling.NEAREST).save(OUT/(name.lower()+'-zoom.png'))
    (OUT/'asset-qa.json').write_text(json.dumps({'wayfarer_unchanged':True,'roundtrip_rgba_exact':True,
        'part_cells':len(records),'native_atlas':[144,284],'authorship':'Pixelorama integer coordinates; duplicated Wayfarer layout',
        'atlases':{n:{'size':[c.w,c.h],'pixels':len(c.p),'sha256':hashlib.sha256(c.bytes()).hexdigest()} for n,c in canvases.items()}},indent=2))
    print('Mooncloak: exact RGBA round trip; Wayfarer preserved; 286 part cells.')

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--verify' in sys.argv:verify()
    else:
        hashes=OUT/'source-hashes.json'
        if not hashes.exists():hashes.write_text(json.dumps({str(ASSET/('WAYFARER'+ext)):hashlib.sha256((ASSET/('WAYFARER'+ext)).read_bytes()).hexdigest() for ext in ['.png','.pxo']},indent=2))
        for ext in ['.png','.pxo']:
            dest=ASSET/('MOONCLOAK'+ext)
            if not dest.exists():shutil.copy2(ASSET/('WAYFARER'+ext),dest)
        source=Path('C:/Users/ramon/AppData/Local/Temp/codex-clipboard-dc14d0c9-b1a8-4f3a-8d6e-70ef34266eb7.png')
        if not (OUT/'reference-user.png').exists():shutil.copy2(source,OUT/'reference-user.png')
        canvases,records=build();native.OUT=ASSET
        calls=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}]
        for name,c in canvases.items():
            if '--body-only' not in sys.argv or name=='MOONCLOAK':calls+=native.requests_for(name,c)[0]
        (OUT/'author-requests.json').write_text(json.dumps(calls))
        (OUT/'manifest.json').write_text(json.dumps({'entries':records},indent=2))
        print(json.dumps({'cells':len(records),'pixels':sum(len(c.p) for c in canvases.values()),'calls':len(calls)}))
