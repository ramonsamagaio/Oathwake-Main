"""Author a connected nine-cell road atlas through Pixelorama coordinate requests.

Box-filtered occupancy rounds both convex and concave bends. Missing-center tiles
carry only the corner fringe, so turns have no square cutouts or inflated width.
Pillow is used only to read/verify exports; the MCP bridge creates the PNG/PXO.
"""
import hashlib
import json
from pathlib import Path
from author_oathwake_terrain import noise

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/terrain'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'
OFFSETS=[(0,-1),(1,0),(0,1),(-1,0),(1,-1),(1,1),(-1,1),(-1,-1),(0,0)]
SIZE=16
CLEAR=(0,0,0,0)

def weights(pixel):
    center=pixel+.5
    return [max(0,min(center+8,(offset+1)*16)-max(center-8,offset*16))/16
            for offset in (-1,0,1)]

def tile_pixels(mask,variant=0):
    cells=[(x,y) for bit,(x,y) in enumerate(OFFSETS) if mask & (1<<bit)]
    def density(x,y):
        wx,wy=weights(x),weights(y)
        return sum(wx[dx+1]*wy[dy+1] for dx,dy in cells)
    def inside(x,y):
        # Periodic wear stays consistent at neighbouring atlas-cell boundaries.
        wear=(noise((x%16)//2,(y%16)//2,417)-.5)*.07
        return density(x,y)>.52+wear
    coverage={(x,y):inside(x,y) for y in range(-3,19) for x in range(-3,19)}
    result=[]
    for y in range(16):
        for x in range(16):
            if not coverage[x,y]:
                # Thin soil dust underneath the chipped lip blends into whichever
                # substrate is present, without painting a green rim onto sand.
                result.append((112,103,77,72) if density(x,y)>.42 else CLEAR)
                continue
            edge=min((abs(dx)+abs(dy) for dy in range(-3,4) for dx in range(-3,4)
                      if abs(dx)+abs(dy)<=3 and not coverage[x+dx,y+dy]),default=4)
            grain=noise(x,y,61+variant*113)
            cluster=noise(x//2,y//2,114+variant*317)
            base=(138,118,84)
            if edge==1:
                if cluster<.30: base=(119,104,77)
                elif cluster>.75: base=(151,131,94)
            elif edge==2 and cluster>.65: base=(149,129,92)
            elif edge==3 and cluster>.80: base=(144,124,88)
            delta=-3 if grain<.16 else (3 if grain>.84 else 0)
            if edge>=3: delta += -2 if cluster<.25 else (2 if cluster>.75 else 0)
            result.append((*(c+delta for c in base),255))
    return result

def main():
    width,height=256,2048
    data=[CLEAR]*(width*height)
    for frame in range(2048):
        mask,variant=frame%512,frame//512
        tile=tile_pixels(mask,variant)
        tx,ty=(frame%16)*16,(frame//16)*16
        for i,c in enumerate(tile): data[(ty+i//16)*width+tx+i%16]=c
    payload=[[i%width,i//width,*c] for i,c in enumerate(data) if c[3]]
    out=DEST/'oathwake_road.png'
    requests=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'},
              {'tool':'pixelorama_create_project','args':{'name':'Oathwake road edges','width':width,'height':height,'frame_count':1}}]
    requests += [{'tool':'pixelorama_set_pixels','args':{'frame':0,'pixels':payload[i:i+4000]}} for i in range(0,len(payload),4000)]
    requests += [{'tool':'pixelorama_save_project','args':{'path':str(out.with_suffix('.pxo'))}},
                 {'tool':'pixelorama_open_project','args':{'path':str(out.with_suffix('.pxo'))}},
                 {'tool':'pixelorama_export_spritesheet','args':{'path':str(out),'frame_count':1,'columns':1}}]
    (DOC/'road-author-requests.json').write_text(json.dumps(requests))
    (DOC/'oathwake-road-manifest.json').write_text(json.dumps({'file':str(out),'size':[width,height],
        'frames':2048,'neighbor_masks':512,'color_variants':4,'neighbor_order':OFFSETS,'center_bit':256,'authorship':'Pixelorama MCP; procedural pixel coordinates',
        'expected_rgba_sha256':hashlib.sha256(bytes(v for c in data for v in c)).hexdigest()},indent=2))
    print(json.dumps({'frames':2048,'pixels':len(payload),'requests':len(requests)}))

if __name__=='__main__':main()
