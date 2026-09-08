"""Reconstruct a reference's apparent pixel grid as Pixelorama coordinate edits.
No image resize, interpolation or PNG-import authorship. Each cell is decided
from supported material regions, snapped to the native palette and cleaned.
Review the reconstructed clusters before accepting or replicating this method.
"""
from collections import Counter,deque
import json,math
from pathlib import Path
from PIL import Image
from author_oathwake_native import Canvas,LEAF,WOOD,OUT,requests_for,split_tree

ROOT=Path(__file__).resolve().parents[1]

def connected(points):
    remaining=set(points);groups=[]
    while remaining:
        q=[remaining.pop()];group=set(q)
        for x,y in q:
            for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)]:
                p=x+dx,y+dy
                if p in remaining:remaining.remove(p);group.add(p);q.append(p)
        groups.append(group)
    return sorted(groups,key=len,reverse=True)

def reconstruct_oak():
    ref=Image.open(ROOT/'docs/resources/generated/trees.png').convert('RGB')
    # Exact bounds of first complete tree, excluding other sprites. Apparent
    # source pixel pitch is approximately four source pixels. Native art is
    # 76x96 plus margins, not squeezed into the previous 43px-wide footprint.
    x0,y0,x1,y1=28,88,336,472
    pitch=4;w=(x1-x0)//pitch;h=(y1-y0)//pitch
    foreground={}
    for y in range(y0,y1):
        for x in range(x0,x1):
            rgb=ref.getpixel((x,y))
            if min(rgb)<184:foreground[x,y]=rgb
    silhouette=connected(foreground)[0]
    c=Canvas(w,h)
    for y in range(h):
        for x in range(w):
            samples=[foreground[xx,yy] for yy in range(y0+y*pitch,y0+(y+1)*pitch) for xx in range(x0+x*pitch,x0+(x+1)*pitch) if (xx,yy) in silhouette]
            if len(samples)<9:continue
            # Material ownership prevents brown bark and green leaf groups
            # averaging into an unrelated colour. Use the dominant material.
            buckets={'wood':[],'leaf':[]}
            for rgb in samples:
                r,g,b=rgb;buckets['wood' if r-g>9 and r-b>17 else 'leaf'].append(rgb)
            kind=max(buckets,key=lambda k:len(buckets[k]));group=buckets[kind]
            pal=WOOD if kind=='wood' else LEAF
            # Vote among palette roles before drawing an actual native pixel.
            votes=Counter(min(range(len(pal)),key=lambda i:sum((rgb[k]-pal[i][k])**2*wt for k,wt in enumerate([.30,.59,.11]))) for rgb in group)
            idx=votes.most_common(1)[0][0]
            c.dot(x,y,pal[idx],kind)
    # Clean outline ownership and palette orphans: no crop islands are allowed.
    groups=c.components()
    for group in groups[1:]:
        for p in group:c.p.pop(p);c.kind.pop(p)
    # The exposed trunk begins below all visible leaves in the reference.
    # This cut is selected for this oak, not derived from a fixed base height.
    cut=74
    for p in c.p:
        if p[1]>=cut:c.kind[p]='wood'
    return c,cut

def main():
    c,cut=reconstruct_oak();upper,base,stump=split_tree(c,cut)
    # Open the whole tree / base / crown / stump alongside each other in PXO.
    board=Canvas(352,112)
    for i,part in enumerate([c,base,upper,stump]):board.paste(part,4+i*88,12)
    req,rec=requests_for('oak-grid-reconstruction-review',board)
    rec.update(status='visual review pending',reference_pitch=4,cut_y=cut,
               actual_native_size=[c.w,c.h],source_crop=[28,88,336,472])
    (OUT/'reconstruction-requests.json').write_text(json.dumps([{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}]+req))
    (OUT/'reconstruction-manifest.json').write_text(json.dumps(rec,indent=2))
    print(rec)

if __name__=='__main__':main()
