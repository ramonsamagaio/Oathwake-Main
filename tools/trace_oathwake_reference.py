"""One-to-one reference tracing and native-pixel cleanup for Pixelorama.

This is source-guided tracing, not a claim of freehand redrawing. Source and
destination coordinates have identical pitch; there is no image resampling.
Only Pixelorama writes the authored PNG/PXO. Palette and alpha are explicit.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path
from PIL import Image
from author_oathwake_native import Canvas, color, requests_for, OUT

SOURCE = Path(__file__).resolve().parents[1]/'docs/resources/source_copies/reference3-user.png'
LEAF = list(map(color, ['293730','344638','42543f','536548','667850','7a895b','8e9a65','a2a976','b6b888','c8c799']))
WOOD = list(map(color, ['30312b','423b32','594a3c','706046','88734e','9f8964','b5a27c']))
LEAF_LEVELS = [36,51,68,85,105,124,144,164,186,207]
WOOD_LEVELS = [34,48,64,83,104,128,159]

# Native contours inspected against the reference and Romestead flora_stump.
# Below clear_y only wood is allowed. The bases are broad connected wood masses,
# with short blunt buttresses like Romestead, not long separated root fingers;
# this is not a rectangular crop or grass recoloured into a brown diamond.
ROOT_PROFILES={
 'oak':{'clear_y':141,'foot':167,'outline':[(51,125),(59,127),(70,125),(77,127),(74,135),(75,144),(79,152),(81,160),(78,164),(73,163),(70,167),(63,167),(60,165),(54,165),(51,163),(48,164),(47,160),(50,151),(53,138)]},
 'beech':{'clear_y':141,'foot':171,'outline':[(55,135),(69,135),(75,137),(73,145),(75,153),(78,160),(79,166),(75,169),(71,167),(69,171),(62,171),(58,168),(53,169),(49,168),(47,165),(50,158),(55,150),(57,143)]},
 'autumn':{'clear_y':143,'foot':174,'outline':[(57,139),(70,138),(73,140),(71,150),(75,158),(78,165),(78,169),(75,172),(69,170),(66,174),(59,173),(56,170),(51,172),(47,170),(47,166),(52,158),(57,148)]},
 'crooked_pine':{'clear_y':146,'foot':179,'outline':[(43,134),(48,137),(56,138),(62,141),(65,143),(71,139),(75,137),(75,141),(69,148),(71,155),(74,164),(78,170),(79,174),(75,177),(70,175),(66,179),(59,179),(55,177),(51,178),(49,174),(52,168),(56,159),(57,152),(54,147),(46,144),(42,141)]},
 'spruce':{'clear_y':151,'foot':177,'outline':[(56,150),(67,150),(68,155),(71,162),(74,168),(75,173),(71,175),(67,174),(64,177),(57,177),(54,174),(49,175),(47,172),(49,167),(54,161),(56,158)]},
 'willow':{'clear_y':149,'foot':178,'outline':[(52,132),(58,136),(70,137),(78,135),(79,142),(78,150),(81,157),(85,164),(87,171),(83,175),(78,173),(75,177),(68,178),(62,178),(58,175),(52,176),(49,172),(51,166),(55,157),(58,149),(59,141)],'erase':[(40,137,53,149),(81,139,100,149)]},
 'palm':{'clear_y':132,'foot':147,'outline':[(46,124),(53,127),(74,126),(80,123),(81,132),(83,139),(80,143),(75,144),(72,147),(63,147),(59,145),(52,145),(47,142),(46,137),(47,131)]},
 'branch_pine':{'clear_y':123,'foot':155,'outline':[(49,115),(60,119),(70,117),(75,117),(77,124),(77,132),(81,139),(82,146),(78,150),(73,148),(69,153),(64,155),(58,153),(54,150),(47,151),(44,149),(44,144),(48,138),(52,134),(55,128),(54,121)]},
 'blossom':{'clear_y':125,'foot':155,'outline':[(50,110),(55,113),(66,113),(68,112),(67,122),(67,133),(70,139),(73,146),(73,151),(68,153),(65,152),(62,155),(56,154),(53,152),(48,152),(46,149),(47,143),(49,137),(50,129)]},
 'fruit':{'clear_y':127,'foot':155,'outline':[(51,122),(57,125),(68,124),(71,120),(72,125),(68,131),(69,138),(73,145),(75,150),(72,153),(67,152),(64,155),(57,155),(53,152),(48,152),(46,149),(48,143),(52,136),(54,130)]},
 'flower':{'clear_y':129,'foot':156,'outline':[(50,122),(58,125),(66,125),(71,120),(72,123),(69,130),(66,134),(68,142),(72,148),(73,152),(70,155),(65,153),(62,156),(56,156),(53,154),(48,154),(46,151),(48,145),(52,138),(54,130)]},
 'blue':{'clear_y':125,'foot':153,'outline':[(51,120),(57,122),(68,122),(73,120),(72,129),(70,135),(73,142),(76,147),(75,151),(70,152),(66,150),(62,153),(57,153),(54,150),(48,151),(46,148),(49,141),(53,136),(54,128)]},
}

def bare_wood_roots(c,model,src):
    profile=ROOT_PROFILES[model['name']]
    clear_y=profile['clear_y'];ox,oy=model['origin']
    wood_mask=Canvas(c.w,c.h)
    wood_mask.polygon(profile['outline'],WOOD[0],'wood')
    row_spans={y:(min(x for x,yy in wood_mask.p if yy==y),max(x for x,yy in wood_mask.p if yy==y)) for y in range(profile['foot']-12,profile['foot']+1)}
    for x,y in list(c.p):
        in_erase=any(x0<=x<x1 and y0<=y<y1 for x0,y0,x1,y1 in profile.get('erase',[]))
        if (y>=clear_y or in_erase) and (x,y) not in wood_mask.p:
            c.p.pop((x,y));c.kind.pop((x,y))
    for x,y in wood_mask.p:
        if y<clear_y and (x,y) not in c.p:continue
        r,g,b=src.getpixel((x+ox,y+oy));lum=.299*r+.587*g+.114*b
        idx=min(range(len(WOOD_LEVELS)),key=lambda i:abs(WOOD_LEVELS[i]-lum))
        if y>=profile['foot']-12:
            # Broad bark volume continues into the base. Do not reproduce the
            # bright separated toe tips or deep fork shadows in the source.
            left,right=row_spans[y];across=(x-left)/max(1,right-left)
            volume=3 if across<.20 else 4 if across<.48 else 3 if across<.72 else 2
            idx=max(1,min(5,round((idx+volume*2)/3)))
        # Root silhouettes use a dark bark edge, like the Romestead reference.
        boundary=any((x+dx,y+dy) not in wood_mask.p for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])
        if boundary and y>=clear_y:idx=min(idx,1)
        c.dot(x,y,WOOD[idx],'wood')
    for group in c.components()[1:]:
        for p in group:c.p.pop(p);c.kind.pop(p)
    assert all(co in WOOD for (x,y),co in c.p.items() if y>=clear_y)
    return profile

def trace_oak(model=None):
    src = Image.open(SOURCE).convert('RGB')
    c = Canvas(128,192)
    model=model or {'name':'oak','origin':[8,0],'bounds':[14,20,132,184],'cut':137,'palette':'olive'}
    ox,oy=model['origin'];x0,y0,x1,y1=model['bounds'];cut=model['cut']-oy
    palette_name=model.get('palette','olive')
    palette=LEAF
    if palette_name=='blue':palette=list(map(color,['293730','344840','425b4e','526c5a','668169','7c9279','92a18a','a6b09b','bac1ad','c9cfbb']))
    if palette_name=='gold':palette=list(map(color,['34352b','4d4530','5f5338','706041','84714c','99825a','aa926b','b7a07c','c2ae8a','cdba9a']))
    if palette_name=='pink':palette=list(map(color,['3d343d','50404c','655060','795e70','8e7082','a28491','b298a0','c1acaf','cfbfbc','dbd0c9']))
    # Reference 3, first tree: exactly the same pixel coordinates in a padded
    # canvas. No guessed 2x/4x pixel lattice and no shrinking a large render.
    for sy in range(y0,y1):
        for sx in range(x0,x1):
            r,g,b = src.getpixel((sx,sy))
            if (max(r,g,b)-min(r,g,b) < 17 and max(r,g,b)>115) or min(r,g,b)>228:
                continue
            x,y=sx-ox,sy-oy
            # Initial source classification. Explicit bark/root masks below
            # correct shaded wood ownership and remove all attached ground.
            wood = (r>g+2 and r>b+8 and palette_name not in ['gold','pink']) or (cut-5<=y<=cut+5 and 44<=x<=84)
            if palette_name=='pink':wood = r>g+7 and g>b+4
            if palette_name=='gold' and y>=cut-12:wood = r>g+2 and r>b+8
            pal,levels = (WOOD,WOOD_LEVELS) if wood else (palette,LEAF_LEVELS)
            if y>cut+9 and g>r:
                pal=list(map(color,['293730','344638','42543f','536548','64704e','76805a','899065','9b9e74']))
                levels=[38,60,83,108,135,158,184,208]
            lum=.299*r+.587*g+.114*b
            if model['name']=='fruit' and y<cut-12 and r>g*1.22 and g>b*1.3:
                pal=list(map(color,['593b31','754735','91583c','ac7248','c28e60','d1a677']))
                levels=[57,84,108,134,163,193]
            if model['name']=='flower' and y<cut-14 and lum>168 and abs(r-g)<28 and r>b+10:
                pal=list(map(color,['817959','a69d76','c1b790','d0c6a0']))
                levels=[165,191,216,238]
            idx=min(range(len(levels)),key=lambda i:abs(levels[i]-lum))
            c.dot(x,y,pal[idx],'wood' if wood else 'leaf')
    for group in c.components()[1:]:
        for p in group:c.p.pop(p);c.kind.pop(p)
    # Root-pad white-matte fringe is neither grass detail nor cast shadow.
    # Inspect its source colour only at the external silhouette, at native 1:1.
    for _ in range(2):
        fringe=[]
        for x,y in c.p:
            if y<=cut+9:continue
            rgb=src.getpixel((x+ox,y+oy))
            if min(rgb)>135 and max(rgb)>180 and any((x+dx,y+dy) not in c.p for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]):fringe.append((x,y))
        for p in fringe:c.p.pop(p);c.kind.pop(p)
    # Eliminate singleton colour specks introduced by JPEG texture while
    # preserving connected leaf marks, bark strokes and the traced silhouette.
    fixes={}
    for (x,y),co in c.p.items():
        around=[(x+dx,y+dy) for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)]]
        neighbours=[c.p[p] for p in around if p in c.p and c.kind[p]==c.kind[x,y]]
        if len(neighbours)>=6 and co not in neighbours:
            most,n=Counter(neighbours).most_common(1)[0]
            if n>=4:fixes[x,y]=most
    c.p.update(fixes)
    # Remove crop-edge needles. At this native pitch a one-pixel appendage
    # with only one/two neighbours is a compression fringe, not a leaf group.
    edge_fixes=[]
    for x,y in c.p:
        n=sum((x+dx,y+dy) in c.p for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)])
        if n<=2:edge_fixes.append((x,y))
    for p in edge_fixes:c.p.pop(p);c.kind.pop(p)
    # Replace sub-three-pixel colour islands with a bordering material shade.
    # No averaging, blur or random texture is introduced.
    for _ in range(2):
        pending=set(c.p);changes={}
        while pending:
            seed=pending.pop();group=[seed];co=c.p[seed]
            for x,y in group:
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    p=x+dx,y+dy
                    if p in pending and c.p[p]==co:
                        pending.remove(p);group.append(p)
            if len(group)>2:continue
            border=[]
            for x,y in group:
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    p=x+dx,y+dy
                    if p in c.p and c.p[p]!=co and c.kind[p]==c.kind[x,y]:border.append(c.p[p])
            if border:
                ranked=Counter(border)
                replacement=min(ranked,key=lambda col:(sum((col[i]-co[i])**2 for i in range(3))/ranked[col]))
                for p in group:changes[p]=replacement
        c.p.update(changes)
    for group in c.components()[1:]:
        for p in group:c.p.pop(p);c.kind.pop(p)
    bare_wood_roots(c,model,src)
    # The cut was chosen below overhead foliage. Neutral/purple bark pixels
    # outside the root contour must not retain a leaf-palette classification.
    for (x,y),co in list(c.p.items()):
        if y>=cut and co not in WOOD:
            r,g,b=src.getpixel((x+ox,y+oy));lum=.299*r+.587*g+.114*b
            idx=min(range(len(WOOD_LEVELS)),key=lambda i:abs(WOOD_LEVELS[i]-lum))
            c.dot(x,y,WOOD[idx],'wood')
    crown=Canvas(c.w,c.h);trunk=Canvas(c.w,c.h)
    for (x,y),co in c.p.items():
        target=crown if y<cut else trunk
        target.dot(x,y,co,c.kind[x,y])
    # Small branch/root pieces can cross the chosen stem row. Their component
    # ownership follows the connected crown/base, keeping all original pixels.
    for source,target in [(crown,trunk),(trunk,crown)]:
        for group in source.components()[1:]:
            for p in group:target.dot(*p,source.p.pop(p),source.kind.pop(p))
    assert set(crown.p).isdisjoint(trunk.p)
    assert {**trunk.p,**crown.p}==c.p
    return c,crown,trunk,cut,len(fixes)

MODELS=[
    {'name':'oak','origin':[8,0],'bounds':[14,20,132,184],'cut':137,'palette':'olive','anchor':[64,175]},
    {'name':'beech','origin':[121,0],'bounds':[136,18,245,188],'cut':147,'palette':'olive','anchor':[64,176]},
    {'name':'autumn','origin':[242,0],'bounds':[255,18,355,188],'cut':148,'palette':'gold','anchor':[64,176]},
    {'name':'crooked_pine','origin':[357,0],'bounds':[357,22,485,189],'cut':151,'palette':'olive','anchor':[66,177]},
    {'name':'spruce','origin':[475,0],'bounds':[485,19,593,190],'cut':156,'palette':'olive','anchor':[64,177]},
    {'name':'willow','origin':[590,0],'bounds':[594,20,718,190],'cut':155,'palette':'olive','anchor':[66,178]},
    {'name':'palm','origin':[6,188],'bounds':[12,201,129,357],'cut':325,'palette':'olive','anchor':[64,155]},
    {'name':'branch_pine','origin':[122,188],'bounds':[132,203,250,354],'cut':308,'palette':'olive','anchor':[65,155]},
    {'name':'blossom','origin':[243,188],'bounds':[250,202,366,357],'cut':308,'palette':'pink','anchor':[64,159]},
    {'name':'fruit','origin':[360,188],'bounds':[367,202,484,361],'cut':317,'palette':'olive','anchor':[64,160]},
    {'name':'flower','origin':[479,188],'bounds':[486,202,607,361],'cut':316,'palette':'olive','anchor':[64,161]},
    {'name':'blue','origin':[598,188],'bounds':[608,202,725,356],'cut':314,'palette':'blue','anchor':[64,155]},
]

for model in MODELS:
    model['anchor'][1]=ROOT_PROFILES[model['name']]['foot']+1
    model['root_clear_y']=ROOT_PROFILES[model['name']]['clear_y']

def family():
    req=[{'tool':'pixelorama_status'}];records=[];assets=[]
    full_atlas=Canvas(768,384);crown_atlas=Canvas(768,384);trunk_atlas=Canvas(768,384)
    for i,model in enumerate(MODELS):
        full,crown,trunk,cut,fixes=trace_oak(model)
        for board,part in [(full_atlas,full),(crown_atlas,crown),(trunk_atlas,trunk)]:board.paste(part,(i%6)*128,(i//6)*192)
        records.append({**model,'cut_native':cut,'pixels':len(full.p),'components':len(full.components()),'trunk_components':len(trunk.components()),'crown_components':len(crown.components())})
    for name,canvas in [('reference3-trees',full_atlas),('reference3-crowns',crown_atlas),('reference3-trunks',trunk_atlas)]:
        calls,rec=requests_for(name,canvas);req+=calls;assets.append(rec)
    (OUT/'reference3-family-requests.json').write_text(json.dumps(req))
    (OUT/'reference3-family.json').write_text(json.dumps({'models':records,'assets':assets,'size':[768,384],'frame_size':[128,192],'status':'replicated reference shapes; isolated Godot review; production catalog unchanged'},indent=2))
    print(json.dumps(records))

def main():
    OUT.mkdir(exist_ok=True,parents=True)
    full,crown,trunk,cut,fixes=trace_oak()
    req=[{'tool':'pixelorama_status'}];records=[]
    for name,canvas in [('reference3-oak',full),('reference3-oak-crown',crown),('reference3-oak-trunk',trunk)]:
        calls,rec=requests_for(name,canvas);req+=calls;records.append(rec)
    board=Canvas(416,208)
    for i,part in enumerate([full,trunk,crown]):board.paste(part,8+i*140,8)
    calls,rec=requests_for('reference3-oak-parts',board);req+=calls;records.append(rec)
    (OUT/'reference3-requests.json').write_text(json.dumps(req))
    manifest={'source':str(SOURCE),'method':'1:1 source-guided native tracing, palette mapping and pixel cleanup; no resampling',
              'source_to_canvas_offset':[-8,0],'cut_y':cut,'ground_anchor':[64,175],
              'status':'visual review pending; not installed in game','colour_specks_corrected':fixes,
              'alpha_components':len(full.components()),'assets':records}
    (OUT/'reference3-manifest.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest))

if __name__=='__main__':
    import sys
    family() if '--family' in sys.argv else main()
