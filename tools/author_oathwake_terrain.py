"""Prepare deterministic Pixelorama MCP pixel edits for Oathwake terrain.
Images are read for analysis only; PNG/PXO authorship and export occur in Pixelorama.
Existing 16px cell positions and a 2px boundary alpha signature are preserved.
"""
import hashlib
import json
import math
import random
import shutil
import sys
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/sprites/world/procedural/terrain'
DEST=SRC/'oathwake_tilesets'
DOC=ROOT/'docs/terrain'
PLANTS=SRC.parent/'plants'
CLEAR=(0,0,0,0)
def rgb(h): return tuple(bytes.fromhex(h))
PALETTES={
 'sand': list(map(rgb,['8a754e','9d875a','ad9766','b9a372','c4ae7d','d0bb88'])),
 'earth':list(map(rgb,['625640','706047','7f6d4e','8a7654','97815c','a18c65'])),
 'olive':list(map(rgb,['414c38','526047','64704e','76805a','899065','9b9e74'])),
 'forest':list(map(rgb,['343f35','45513e','555e45','667050','7a805a','8a8e66'])),
 'deep':list(map(rgb,['293730','38483b','465742','576448','6d7651','81855b'])),
 'stone':list(map(rgb,['34363a','494b49','606159','79796a','919080','a5a18c'])),
 'wood':list(map(rgb,['30312b','464236','5b503d','746248','8a7853','a39065'])),
}
TERRAIN={'plainsgrass2.png':'sand','plainsgrass3.png':'earth','short_grass.png':'olive','plainsgrass1.png':'forest','tall_grass.png':'deep'}
OTHER={'forest_path_short_grass_autumn.png':'earth','plains_3D_cliffs.png':'stone','forest_unbreakable_bushes_bottom_.png':'deep','forest_unbreakable_bushes_top_.png':'forest','tree_wall.png':'wood','canopy_.png':'deep'}
DETAIL={'plainsgrass2_details.png':'sand','plainsgrass3_details.png':'earth','shortgrass_details.png':'olive','flora_tiny_flowers.png':'flowers','flora_tiny_ground_leaves.png':'leaves','flora_ground_plants.png':'plants'}

def noise(x,y,seed=0):
    v=((x*374761393+y*668265263+seed*982451653)^0x9e3779b9)&0xffffffff
    v=((v^(v>>13))*1274126177)&0xffffffff
    return ((v^(v>>16))&0xffff)/65535

def terrain_pixels(im,role):
    w,h=im.size; before=list(im.get_flattened_data()); result=before[:]; pal=PALETTES[role]
    # The full frame is a neutral material sample. Preserve the source rim's
    # relief relative to it; the first pass collapsed lit lips and dark roots.
    fill_luma=sorted(sum(c[k]*weight for k,weight in enumerate((.30,.59,.11)))
                     for c in im.crop((32,16,48,32)).get_flattened_data() if c[3]==255)
    base_luma=fill_luma[len(fill_luma)//2]
    def alpha(x,y):
        return before[y*w+x][3] if 0<=x<w and 0<=y<h else 0
    for y in range(h):
        for x in range(w):
            i=y*w+x; r,g,b,a=before[i]
            if a==0: continue
            px,py=x%16,y%16
            # Preserve pre-existing translucent drop shadows as subdued umber.
            if a<255:
                result[i]=(38,38,31,a); continue
            edge=min((abs(dx)+abs(dy) for dy in range(-3,4) for dx in range(-3,4) if abs(dx)+abs(dy)<=3 and alpha(x+dx,y+dy)==0),default=4)
            grain=noise(px,py,17)
            # Low-contrast sand/earth mottling; tileable 16px grain without large stamps.
            shade=3
            # Fine grain changes values by a few RGB levels, not whole palette steps.
            delta=-2 if grain<.10 else (2 if grain>.90 else 0)
            patch=noise(px//3,py//3,63)
            delta += -2 if patch<.3 else (1 if patch>.7 else 0)
            source_relief=(r*.30+g*.59+b*.11-base_luma)/18.0
            shade=max(0,min(5,3+source_relief))
            if edge<=3:
                # A broken, clustered lip keeps the grass/soil transition readable.
                # Source lighting also carries across atlas seams; alpha-nearness
                # alone cannot identify an edge on every packed cell boundary.
                cluster=noise(x//2,y//2,91)
                shade=max(0,min(5,shade+(.35 if cluster>.65 else -.15)))
            if edge==1 and 2<=px<=13 and 2<=py<=13:
                # Only alter contour inside cells: connections at all tile boundaries stay fixed.
                solid=sum(alpha(x+dx,y+dy)==255 for dx,dy in [(-1,0),(1,0),(0,-1),(0,1)])
                if solid<=1 or (solid==2 and noise(x//2,y//2,9)<.26):
                    result[i]=CLEAR; continue
            lo=int(shade); hi=min(5,lo+1); blend=round((shade-lo)*4)/4
            mixed=[round(pal[lo][k]*(1-blend)+pal[hi][k]*blend) for k in range(3)]
            result[i]=(*(max(0,min(255,c+delta)) for c in mixed),255)
    return result

def structure_pixels(im,role):
    w,h=im.size; result=[]; pal=PALETTES[role]
    colors=sorted(set(c[:3] for c in im.get_flattened_data() if c[3]),key=lambda c:sum(c))
    rank={c:i/max(1,len(colors)-1) for i,c in enumerate(colors)}
    for y in range(h):
        for x in range(w):
            c=im.getpixel((x,y)); r,g,b,a=c
            if not a: result.append(CLEAR); continue
            shade=min(5,int((r*.25+g*.6+b*.15)/32))
            if role=='stone':
                # Interpolate the ramp so original cliff facets survive. Integer palette
                # bins collapsed differently lit cap planes to the same flat gray.
                value=min(5,max(0,(r*.3+g*.59+b*.11)/31-1))
                lo=int(value); hi=min(5,lo+1); blend=round((value-lo)*4)/4
                mixed=tuple(round(pal[lo][k]*(1-blend)+pal[hi][k]*blend) for k in range(3))
                result.append((*mixed,a)); continue
            if role=='wood' and a==255 and x%16 in (5,6,11) and y%9 in (3,4): shade=max(0,shade-1)
            result.append((*pal[shade],a))
    return result

def detail_pixels(im,role):
    w,h=im.size; result=[CLEAR]*(w*h)
    cell=32 if role=='plants' else 16
    # Each variant is redrawn within its original frame, with its original ground anchor.
    for cy in range(h//cell):
        for cx in range(w//cell):
            rng=random.Random(173+cx*173+cy*401)
            ox,oy=cx*cell,cy*cell
            def dot(x,y,c):
                if 1<=x<cell-1 and 1<=y<cell-1: result[(oy+y)*w+ox+x]=(*c,255)
            def stroke(x,y,dx,dy,length,c):
                for n in range(length): dot(x+round(dx*n),y+round(dy*n),c)
            pal=PALETTES['forest' if cy else 'olive']
            if role in ('sand','earth'):
                p=PALETTES[role]; base=10
                if cx%2==0:
                    # Small dry sedge clumps.
                    for x,dx,ln in [(6,-.35,4),(8,0,6),(10,.4,3)]:
                        stroke(x,base,dx,-1,ln,p[1]); stroke(x+1,base-1,dx,-1,ln-1,p[4])
                else:
                    # Subtle earth fissure and a few irregular flecks.
                    stroke(4,8,1,.25,5,p[1]); stroke(8,9,.3,1,3,p[2])
                    for x,y in [(4,7),(6,7),(11,6)]: dot(x,y,p[4])
            elif role=='flowers':
                # Sparse muted ivory / dusty mauve wildflowers; no bright yellow dots.
                petals=rgb('c5ba96') if cx==0 else rgb('aa929a')
                for x,y in [(6,8),(10,11)]:
                    stroke(x,y+3,0,-1,3,pal[1]);dot(x-1,y+2,pal[3]);dot(x+1,y+1,pal[2])
                    for dx,dy in [(-1,0),(1,0),(0,-1)]:dot(x+dx,y+dy,petals)
                    dot(x,y,rgb('756b49'))
            elif role in ('leaves','olive'):
                # Bent grass blades and small fallen leaves, larger variants first.
                count=4 if cx<4 else 2
                for n in range(count):
                    x=4+n*2; base=11-rng.randrange(3); ln=rng.randrange(3,6)
                    stroke(x,base,(-.3 if n%2 else .35),-1,ln,pal[1])
                    stroke(x+1,base-1,(-.3 if n%2 else .35),-1,max(1,ln-2),pal[4])
                if cx%3==1:
                    for x,y in [(4,12),(5,11),(6,11)]:dot(x,y,PALETTES['earth'][4])
            else:
                # Rarer 32px decorative fern / dry grass rosettes, no resource geometry.
                base=27
                for n in range(7):
                    x=8+n*2; ln=rng.randrange(8,17); slope=(n-3)*.10
                    stroke(x,base,slope,-1,ln,pal[0]);stroke(x+1,base-1,slope,-1,ln-1,pal[3])
                    for j in range(3,ln-2,3):
                        xx=x+round(slope*j); yy=base-j
                        stroke(xx,yy,-1,-.4,3,pal[2]);stroke(xx+1,yy,1,-.5,3,pal[4])
                if cx in (1,4):
                    for x,y in [(12,12),(17,9),(21,14)]:
                        dot(x,y,PALETTES['sand'][3]);dot(x,y-1,PALETTES['sand'][4])
    return result

def main():
    DEST.mkdir(exist_ok=True); DOC.mkdir(exist_ok=True)
    records=[]; requests=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}]
    for name,role in {**TERRAIN,**OTHER,**DETAIL}.items():
        source=(SRC if (SRC/name).exists() else PLANTS)/name
        original=Image.open(source).convert('RGBA'); w,h=original.size
        # Duplicate source files in an explicit originals subfolder before authoring.
        backup=DEST/'source_copies'/name; backup.parent.mkdir(exist_ok=True)
        if not backup.exists(): shutil.copy2(source,backup)
        data=(terrain_pixels(original,role) if name in TERRAIN else (structure_pixels(original,role) if name in OTHER else detail_pixels(original,role)))
        payload=[[i%w,i//w,*c] for i,c in enumerate(data) if c[3]]
        request_start=len(requests)
        out=DEST/name; pxo=out.with_suffix('.pxo')
        requests.append({'tool':'pixelorama_create_project','args':{'name':'Oathwake '+out.stem,'width':w,'height':h,'frame_count':1}})
        requests += [{'tool':'pixelorama_set_pixels','args':{'frame':0,'pixels':payload[i:i+4000]}} for i in range(0,len(payload),4000)]
        requests += [{'tool':'pixelorama_save_project','args':{'path':str(pxo)}},{'tool':'pixelorama_open_project','args':{'path':str(pxo)}},{'tool':'pixelorama_export_spritesheet','args':{'path':str(out),'frame_count':1,'columns':1}}]
        if len(sys.argv)>1 and name not in sys.argv[1:]: requests=requests[:request_start]
        old=list(original.get_flattened_data())
        records.append({'file':name,'source':str(source),'role':role,'size':[w,h],'cell_size':32 if role=='plants' else 16,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'expected_rgba_sha256':hashlib.sha256(bytes(v for c in data for v in c)).hexdigest(),'changed_pixels':sum(a!=b for a,b in zip(old,data)),'alpha_changes':sum(a[3]!=b[3] for a,b in zip(old,data)),'pixel_count':len(payload)})
    (DOC/'terrain-author-requests.json').write_text(json.dumps(requests))
    (DOC/'oathwake-tilesets-manifest.json').write_text(json.dumps({'palettes':PALETTES,'assets':records,'production_root':str(DEST)},indent=2))
    print(json.dumps({'sheets':len(records),'pixels':sum(r['pixel_count'] for r in records),'requests':len(requests)}))

if __name__=='__main__':main()
