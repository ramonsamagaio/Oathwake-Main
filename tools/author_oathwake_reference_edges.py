"""Reference-led native terrain edges, exported only through Pixelorama MCP.

Source masks supply the verified tile connections, not the edge lighting.
Contours inside the join guards and clustered edge colors are drawn anew.
"""
import hashlib,json,shutil,sys
from pathlib import Path
from functools import lru_cache
from PIL import Image
import author_oathwake_native as native
from author_oathwake_native import Canvas
from author_oathwake_terrain import noise
from author_oathwake_road import weights,OFFSETS

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/terrain/reference-edge-revision'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'
ROLES={'plainsgrass2':'sand','plainsgrass3':'earth','short_grass':'olive','plainsgrass1':'forest','tall_grass':'deep'}
BASE={'sand':(190,160,102),'earth':(139,113,77),'olive':(119,119,78),
      'forest':(106,109,71),'deep':(87,97,66)}
RIMS={'sand':[(171,141,86),(201,174,115),(214,188,132)],
      'earth':[(151,125,82),(179,150,96),(199,171,114)],
      'olive':[(134,130,79),(170,157,92),(193,179,109)],
      'forest':[(116,121,76),(135,139,87),(154,155,98)],
      'deep':[(97,109,69),(111,122,77),(130,137,87)]}
# Deliberate clumps and bare intervals, unlike a continuous bright outline.
RHYTHM=[0,0,1,2,1,0,0,0,2,1,0,0,1,2,1,0]
PROFILE=[0,0,1,1,0,-1,0,0,0,-1,-1,0,1,1,0,0]
PROFILES=[
 [0,0,1,1,2,1,1,0,-1,-1,0,1,0,0,0,0],
 [0,0,-1,-2,-1,0,1,2,1,1,0,0,-1,-1,0,0],
 [0,0,1,2,2,1,0,-1,-2,-1,0,0,1,1,0,0],
 [0,0,0,-1,-1,-2,-1,0,1,1,2,1,0,-1,0,0]]
CLEAR=(0,0,0,0)

def rgb_delta(rgb,d):return tuple(max(0,min(255,round(v+d))) for v in rgb)

def ground(name,role):
    source=Image.open(OUT/'before'/(name+'.png')).convert('RGBA')
    atlas=Canvas(*source.size)
    fill=list(source.crop((32,16,48,32)).get_flattened_data())
    mean=tuple(sum(p[k] for p in fill)/len(fill) for k in range(3))
    for frame in range(source.width//16*source.height//16):
        ox,oy=frame%4*16,frame//4*16
        old={(x,y):source.getpixel((ox+x,oy+y)) for y in range(16) for x in range(16)}
        def filled(x,y):return old[max(0,min(15,x)),max(0,min(15,y))][3]==255
        solid={p for p,co in old.items() if co[3]==255}
        # Remove the former sawtooth rhythm while retaining two native pixels
        # of the exact boundary contract between neighboring atlas pieces.
        for y in range(2,14):
            for x in range(2,14):
                neighbors=sum(filled(x+dx,y+dy) for dy in [-1,0,1] for dx in [-1,0,1])
                if neighbors>=6:solid.add((x,y))
                elif neighbors<=3:solid.discard((x,y))
        def outside(x,y):return (max(0,min(15,x)),max(0,min(15,y))) not in solid
        for y in range(16):
            for x in range(16):
                old_co=old[x,y]
                if (x,y) not in solid:
                    # Retain the existing explicitly authored shadow at joins.
                    if 0<old_co[3]<255:
                        atlas.dot(ox+x,oy+y,(52,49,36,old_co[3]))
                    continue
                distances=[(abs(dx)+abs(dy),dx,dy) for dy in range(-4,5) for dx in range(-4,5)
                    if 0<abs(dx)+abs(dy)<=4 and outside(x+dx,y+dy)]
                distance,nx,ny=min(distances) if distances else (5,0,0)
                # Fine original ground grain is retained only away from rims.
                # A rim's obsolete bright/dark relief is deliberately discarded.
                if distance>=5 and old_co[3]==255:
                    delta=max(-5,min(5,sum(old_co[k]-mean[k] for k in range(3))/3))
                else:
                    n=noise(x,y,83)
                    delta=-2 if n<.23 else 2 if n>.77 else 0
                co=rgb_delta(BASE[role],delta)
                phase=(x//2+2*(y//2)+(frame%4)*3+(frame//4)*5)%16
                clump=RHYTHM[phase]
                if distance<=2 and clump:
                    shade=clump if distance==1 else max(0,clump-1)
                    if ny>0 and nx>=0:shade=max(0,shade-1)
                    co=RIMS[role][shade]
                elif distance==3 and clump==2:
                    co=RIMS[role][0]
                elif distance==1:
                    co=rgb_delta(BASE[role],-4 if ny>0 else 1)
                atlas.dot(ox+x,oy+y,(*co,255))
        # Reference edge accents are small shaped leaf/chip groups, not dots
        # or a scalar highlight around the entire contour. Draw their pixels
        # explicitly, including a little silhouette outside the former rim.
        edge_points=[(x,y) for x,y in solid if 1<=x<=14 and 1<=y<=14
                     and any((x+dx,y+dy) not in solid for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])]
        edge_points.sort(key=lambda p:(p[0]*7+p[1]*11+frame*13)%31)
        anchors=[]
        separation=81 if role=='olive' else 45
        for x,y in edge_points:
            if all((x-ax)**2+(y-ay)**2>=separation for ax,ay in anchors):anchors.append((x,y))
        pattern=['...h...','..hhm..','.hhml..','hhml...','.llmm..','..dd...'] if role=='olive' else (['..h..','.hhm.','hml..','.ld..'] if role in ['forest','deep'] else ['.hh.','hml.','.ld.'])
        shift=3 if role=='olive' else 2
        for ax,ay in anchors:
            for dy,row in enumerate(pattern):
                for dx,ch in enumerate(row):
                    if ch=='.':continue
                    x,y=ax+dx-shift,ay+dy-shift
                    if not (0<=x<16 and 0<=y<16):continue
                    guarded=x in (0,1,14,15) or y in (0,1,14,15)
                    if guarded and old[x,y][3]!=255:continue
                    if ch=='d' and (x,y) not in solid:continue
                    reach=3 if role=='olive' else 2
                    if (x,y) not in solid and not any((x+xx,y+yy) in solid for yy in range(-reach,reach+1) for xx in range(-reach,reach+1) if abs(xx)+abs(yy)<=reach):continue
                    co=rgb_delta(BASE[role],-7) if ch=='d' else RIMS[role][{'l':0,'m':1,'h':2}[ch]]
                    atlas.dot(ox+x,oy+y,(*co,255))
    return atlas

@lru_cache(maxsize=2048)
def road_geometry(mask,variant):
    cells=[(x,y) for bit,(x,y) in enumerate(OFFSETS) if mask&(1<<bit)]
    def density(x,y):
        wx,wy=weights(x),weights(y)
        return sum(wx[dx+1]*wy[dy+1] for dx,dy in cells)
    coverage={}
    for y in range(-4,20):
        for x in range(-4,20):
            # Periodic authored steps join exactly at neighboring cell edges.
            guard=x%16 in (0,1,14,15) or y%16 in (0,1,14,15)
            wear=0.0 if guard else (PROFILES[variant][x%16]+PROFILES[(variant+1)%4][y%16])*.05
            coverage[x,y]=density(x,y)>.50+wear
    # A concave join may produce a tiny detached chip after the profile cut.
    # Keep components connected to a neighbor or the actual road center only.
    remaining={(x,y) for y in range(16) for x in range(16) if coverage[x,y]}
    while remaining:
        start=next(iter(remaining));remaining.remove(start);component={start};queue=[start]
        for x,y in queue:
            for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if p in remaining:remaining.remove(p);component.add(p);queue.append(p)
        anchored=any(x in (0,15) or y in (0,15) for x,y in component)
        anchored=anchored or bool(mask&256 and (8,8) in component)
        if not anchored:
            for p in component:coverage[p]=False
    remaining={(x,y) for y in range(16) for x in range(16) if not coverage[x,y]}
    while remaining:
        start=next(iter(remaining));remaining.remove(start);component={start};queue=[start]
        for x,y in queue:
            for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if p in remaining:remaining.remove(p);component.add(p);queue.append(p)
        open_edge=any(x in (0,15) or y in (0,15) for x,y in component)
        logical_hole=not (mask&256) and (8,8) in component
        if not open_edge and not logical_hole:
            for p in component:coverage[p]=True
    return coverage

def road_tile(mask,variant):
    covered=road_geometry(mask,variant);result=[]
    for y in range(16):
        for x in range(16):
            if not covered[x,y]:result.append(CLEAR);continue
            near=[(abs(dx)+abs(dy),dx,dy) for dy in range(-3,4) for dx in range(-3,4)
                  if 0<abs(dx)+abs(dy)<=3 and not covered[x+dx,y+dy]]
            distance,nx,ny=min(near) if near else (4,0,0)
            grain=noise(x,y,61+variant*113)
            patch=noise(x//3,y//3,714+variant*17)
            d=(-2 if grain<.2 else 2 if grain>.8 else 0)+(-2 if patch<.3 else 2 if patch>.75 else 0)
            co=rgb_delta(BASE['earth'],d)
            clump=RHYTHM[(x//2+2*(y//2)+variant*3)%16]
            if distance<=2 and clump:
                co=RIMS['earth'][clump if distance==1 else max(0,clump-1)]
            elif distance==1:co=rgb_delta(BASE['earth'],-4)
            result.append((*co,255))
    return result

def road():
    c=Canvas(256,2048)
    for frame in range(2048):
        for i,co in enumerate(road_tile(frame%512,frame//512)):
            if co[3]:c.dot(frame%16*16+i%16,frame//16*16+i//16,co)
    return c

def build(include_road=True):
    for name,role in ROLES.items():yield name,ground(name,role)
    if include_road:yield 'oathwake_road',road()

def verify(publish=False):
    records=[];boundary=0
    for name,c in build():
        im=Image.open(OUT/(name+'.png')).convert('RGBA')
        assert im.size==(c.w,c.h) and im.tobytes()==c.bytes(),name
        assert (OUT/(name+'.pxo')).stat().st_size>0
        before=Image.open(OUT/'before'/(name+'.png')).convert('RGBA')
        if name!='oathwake_road':
            for y in range(im.height):
                for x in range(im.width):
                    if x%16 in (0,1,14,15) or y%16 in (0,1,14,15):
                        assert im.getpixel((x,y))[3]==before.getpixel((x,y))[3],(name,x,y)
                        boundary+=1
            assert im.getchannel('A').crop((32,16,48,32)).getextrema()==(255,255)
            for cy in range(im.height//16):
                for cx in range(4):
                    cell=Canvas(16,16)
                    for y in range(16):
                        for x in range(16):
                            co=im.getpixel((cx*16+x,cy*16+y))
                            if co[3]:cell.dot(x,y,co)
                    for component in cell.components():
                        assert any(before.getpixel((cx*16+x,cy*16+y))[3] for x,y in component),('Detached new terrain cluster',name,cx,cy)
        else:
            alpha=im.getchannel('A')
            assert set(alpha.tobytes())=={0,255}
            for v in range(1,4):
                for y in range(512):
                    for x in range(256):
                        if x%16 in (0,1,14,15) or y%16 in (0,1,14,15):
                            assert alpha.getpixel((x,y))==alpha.getpixel((x,y+v*512)),('road variant join',v,x,y)
        records.append({'file':name+'.png','rgba_sha256':hashlib.sha256(c.bytes()).hexdigest(),
            'size':[c.w,c.h],'pixels':len(c.p),'changed_pixels':sum(a!=b for a,b in zip(before.get_flattened_data(),im.get_flattened_data()))})
    report={'assets':records,'join_alpha_pixels_checked':boundary,'pixelorama_roundtrip':True}
    (OUT/'asset-qa.json').write_text(json.dumps(report,indent=2))
    # Reuse the independent exported-pixel road assembly check before publish.
    import verify_oathwake_terrain as topology_qa
    candidate_manifest=json.loads((ROOT/'docs/terrain/oathwake-road-manifest.json').read_text())
    candidate_manifest['file']=str(OUT/'oathwake_road.png')
    candidate_manifest['expected_rgba_sha256']=records[-1]['rgba_sha256']
    candidate_manifest['alpha_variant_policy']='identical_two_pixel_join_guard'
    (OUT/'oathwake-road-manifest.json').write_text(json.dumps(candidate_manifest,indent=2))
    topology_qa.DOC=OUT
    topology_qa.verify_road()
    if publish:
        terrain_path=ROOT/'docs/terrain/oathwake-tilesets-manifest.json'
        manifest=json.loads(terrain_path.read_text())
        for result in records:
            src=OUT/result['file']
            for ext in ['.png','.pxo']:shutil.copy2(src.with_suffix(ext),(DEST/result['file']).with_suffix(ext))
            if result['file']=='oathwake_road.png':continue
            rec=next(r for r in manifest['assets'] if r['file']==result['file'])
            original=Image.open(rec['source']).convert('RGBA');new=Image.open(src).convert('RGBA')
            assert hashlib.sha256(Path(rec['source']).read_bytes()).hexdigest()==rec['source_sha256']
            a=list(original.get_flattened_data());b=list(new.get_flattened_data())
            rec.update(expected_rgba_sha256=result['rgba_sha256'],changed_pixels=sum(x!=y for x,y in zip(a,b)),
                       alpha_changes=sum(x[3]!=y[3] for x,y in zip(a,b)),pixel_count=result['pixels'],
                       revision='2026-09-08 reference-led clustered border reconstruction; reference-edge-revision/asset-qa.json')
        terrain_path.write_text(json.dumps(manifest,indent=2)+'\n')
        road_path=ROOT/'docs/terrain/oathwake-road-manifest.json';r=json.loads(road_path.read_text())
        r['expected_rgba_sha256']=records[-1]['rgba_sha256'];r['revision']='Reference-led clustered borders, native binary alpha'
        r['alpha_variant_policy']='identical_two_pixel_join_guard'
        road_path.write_text(json.dumps(r,indent=2)+'\n')
    print(json.dumps({'verified':len(records),'join_pixels':boundary,'published':publish}))

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--verify' in sys.argv or '--publish' in sys.argv:verify('--publish' in sys.argv)
    else:
        native.OUT=OUT;calls=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}];records=[]
        selection=[('oathwake_road',road())] if '--road-only' in sys.argv else build('--ground-only' not in sys.argv)
        for name,c in selection:
            req,rec=native.requests_for(name,c);calls+=req;records.append(rec)
        (OUT/'requests.json').write_text(json.dumps(calls))
        (OUT/'expected.json').write_text(json.dumps(records,indent=2))
        print(json.dumps({'atlases':len(records),'requests':len(calls)}))
