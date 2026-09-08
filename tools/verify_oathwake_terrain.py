"""Validate Pixelorama exports, original preservation and native tile connections."""
import hashlib
import json
from pathlib import Path
from PIL import Image,ImageDraw
from collections import deque

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/terrain'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'

def verify_road():
    manifest=json.loads((DOC/'oathwake-road-manifest.json').read_text())
    path=Path(manifest['file'])
    atlas=Image.open(path).convert('RGBA')
    assert atlas.size==tuple(manifest['size']) and path.with_suffix('.pxo').stat().st_size>0
    assert hashlib.sha256(atlas.tobytes()).hexdigest()==manifest['expected_rgba_sha256']
    alpha=atlas.getchannel('A')
    varied_contours=manifest.get('alpha_variant_policy')=='identical_two_pixel_join_guard'
    for variant in range(1,4):
        if not varied_contours:
            assert alpha.crop((0,0,256,512)).tobytes()==alpha.crop((0,variant*512,256,(variant+1)*512)).tobytes(), 'Variant changes joins'
        else:
            for y in range(512):
                for x in range(256):
                    if x%16 in (0,1,14,15) or y%16 in (0,1,14,15):
                        assert alpha.getpixel((x,y))==alpha.getpixel((x,y+variant*512)), 'Variant changes join guard'
    offsets=manifest['neighbor_order']
    def pixel(mask,x,y,variant=0): return atlas.getpixel(((mask%16)*16+x,(mask//16)*16+y+variant*512))
    assert pixel(256,0,0)[3]==0, 'Outer corner is still square'
    assert pixel(1|8|128,0,0)[3]==255, 'Missing concave corner fringe'
    assert all(pixel(511,x,y)[3]==255 for y in range(16) for x in range(16)), 'Interior hole'
    # Inspect exported atlas assembled into independent 1/2/3-wide U-bends and a
    # T-junction. Flooding real opaque pixels catches disconnections and pinholes.
    cases=[]
    for width in (1,2,3):
        cells={(x,y) for y in range(width) for x in range(8)}
        cells|={(x,y) for x in range(8-width,8) for y in range(9)}
        cells|={(x,y) for y in range(9-width,9) for x in range(8)}
        cases.append(cells)
    cases.append({(x,y) for x in range(10) for y in range(3)}|{(x,y) for x in range(4,7) for y in range(10)})
    modes=range(5) if varied_contours else range(1)
    for cells,mode in [(c,m) for c in cases for m in modes]:
        opaque=set()
        for cy in range(-1,12):
            for cx in range(-1,12):
                mask=sum(1<<bit for bit,(dx,dy) in enumerate(offsets) if (cx+dx,cy+dy) in cells)
                for py in range(16):
                    for px in range(16):
                        variant=mode if mode<4 else (cx*31+cy*17)%4
                        if pixel(mask,px,py,variant)[3]: opaque.add((cx*16+px,cy*16+py))
        centers={(x*16+8,y*16+8) for x,y in cells}
        assert centers<=opaque
        visited={next(iter(centers))}; queue=deque(visited)
        while queue:
            x,y=queue.popleft()
            for p in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if p in opaque and p not in visited: visited.add(p);queue.append(p)
        assert visited==opaque, ('Disconnected road pixel island',mode,len(cells),sorted(opaque-visited)[:16])
        # Flood outside; enclosed transparent holes are never intentional here.
        outside={(-16,-16)}; queue=deque(outside)
        while queue:
            x,y=queue.popleft()
            for p in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if -16<=p[0]<192 and -16<=p[1]<192 and p not in opaque and p not in outside:
                    outside.add(p);queue.append(p)
        assert len(outside)+len(opaque)==208*208, ('Transparent pinhole inside road',mode,len(cells),sorted({(x,y) for y in range(-16,192) for x in range(-16,192)}-outside-opaque)[:12])
    result={'rgba_roundtrip':True,'frames':2048,'neighbor_masks':512,'color_variants':4,'variant_alpha_identical':not varied_contours,'variant_join_guard_identical':True,'connected_layouts':len(cases)*len(modes),'convex_and_concave_corners':True,'pinholes':0}
    (DOC/'road-edge-qa.json').write_text(json.dumps(result,indent=2))
    return result

def main():
    manifest=json.loads((DOC/'oathwake-tilesets-manifest.json').read_text())
    records=[]
    for rec in manifest['assets']:
        target=DEST/rec['file']; source=Path(rec['source'])
        assert target.exists() and target.with_suffix('.pxo').stat().st_size>0
        a=Image.open(source).convert('RGBA'); b=Image.open(target).convert('RGBA')
        assert b.size==a.size==tuple(rec['size']),rec['file']
        assert hashlib.sha256(source.read_bytes()).hexdigest()==rec['source_sha256'],rec['file']
        assert hashlib.sha256(b.tobytes()).hexdigest()==rec['expected_rgba_sha256'],rec['file']
        is_terrain=rec['file'] in ['plainsgrass1.png','plainsgrass2.png','plainsgrass3.png','short_grass.png','tall_grass.png']
        boundary=0
        if is_terrain:
            for y in range(a.height):
                for x in range(a.width):
                    if x%16 in (0,1,14,15) or y%16 in (0,1,14,15):
                        assert a.getpixel((x,y))[3]==b.getpixel((x,y))[3],(rec['file'],x,y)
                        boundary+=1
            # The full terrain tile actually used throughout the world remains entirely opaque.
            assert b.getchannel('A').crop((32,16,48,32)).getextrema()==(255,255)
        records.append({'file':rec['file'],'rgba_roundtrip':True,'original_unchanged':True,'boundary_alpha_pixels_checked':boundary,'alpha_pixels_changed':rec['alpha_changes'],'colors':len(set(b.get_flattened_data()))})
    road=verify_road()
    report={'sheet_count':len(records)+1,'passed':True,'assets':records,'road':road}
    (DOC/'terrain-asset-qa.json').write_text(json.dumps(report,indent=2))
    # Contact sheets are QA output only; no artwork is generated by Pillow.
    board=Image.new('RGB',(1200,1050),'#303437'); draw=ImageDraw.Draw(board)
    for i,rec in enumerate(manifest['assets']):
        im=Image.open(DEST/rec['file'])
        ox,oy=(i%6)*200,(i//6)*350
        draw.text((ox+4,oy+3),rec['file'],fill='white')
        board.paste(im,(ox+4,oy+24),im)
    road_preview=Image.open(DEST/'oathwake_road.png').crop((0,0,256,512)).resize((128,256),Image.Resampling.NEAREST)
    draw.text((1004,703),'oathwake_road.png / 4 variants',fill='white')
    board.paste(road_preview,(1004,724),road_preview)
    board.save(DOC/'oathwake-atlas-review.png')
    for stem in ['terrain-before','terrain-after','road-edge-review','world-0-before','world-0-after','world-1-before','world-1-after','world-2-before','world-2-after']:
        path=DOC/(stem+'-native.png')
        if path.exists():
            image=Image.open(path)
            image.resize((image.width*2,image.height*2),Image.Resampling.NEAREST).save(DOC/(stem+'.png'))
    print(json.dumps({'passed':True,'sheets':len(records)+1,'boundary_alpha_checks':sum(r['boundary_alpha_pixels_checked'] for r in records),'road':road}))

if __name__=='__main__': main()
