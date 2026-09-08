"""Native-grid Pixelorama authoring. No source-image sampling or image resizing.
Every visible pixel is an integer coordinate edit with semantic ownership.
Generated images are composition references only. PNG/PXO are written by MCP.
"""
import hashlib
import json
import math
import sys
from collections import deque
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/resources/native'
CLEAR=(0,0,0,0)
def color(h):return tuple(bytes.fromhex(h))+(255,)
LEAF=list(map(color,['293730','38483b','465742','64704e','81855b','9b9e74']))
WOOD=list(map(color,['30312b','464236','5b503d','746248','8a7853','b0a078']))
STONE=list(map(color,['34363a','494b49','606159','79796a','919080','a5a18c']))
STRAW=list(map(color,['464236','625640','8a7853','a39065','c4ae7d']))
VIOLET=list(map(color,['4a414e','6d5d74','8b7b92','aa929a']))
IVORY=list(map(color,['817959','a69d76','d0c6a0']))

class Canvas:
    def __init__(self,w,h):self.w=w;self.h=h;self.p={};self.kind={}
    def dot(self,x,y,c,kind='leaf',mask=None):
        x=int(x);y=int(y)
        if 0<=x<self.w and 0<=y<self.h and (mask is None or (x,y) in mask):
            if c[3]:self.p[x,y]=c;self.kind[x,y]=kind
            else:self.p.pop((x,y),None);self.kind.pop((x,y),None)
    def polygon(self,points,c,kind='leaf',mask=None):
        pts=[(round(x),round(y)) for x,y in points]
        for y in range(min(p[1] for p in pts),max(p[1] for p in pts)+1):
            cross=[]
            for (x1,y1),(x2,y2) in zip(pts,pts[1:]+pts[:1]):
                if y1==y2:continue
                if min(y1,y2)<=y+.5<max(y1,y2):cross.append(x1+(y+.5-y1)*(x2-x1)/(y2-y1))
            cross.sort()
            for a,b in zip(cross[::2],cross[1::2]):
                for x in range(math.ceil(a-.5),math.floor(b-.5)+1):self.dot(x,y,c,kind,mask)
        for a,b in zip(pts,pts[1:]+pts[:1]):self.line(a,b,c,kind,mask)
    def line(self,a,b,c,kind='wood',mask=None):
        x,y=map(round,a);xx,yy=map(round,b);dx=abs(xx-x);sx=1 if x<xx else -1;dy=-abs(yy-y);sy=1 if y<yy else -1;err=dx+dy
        while True:
            self.dot(x,y,c,kind,mask)
            if (x,y)==(xx,yy):break
            e=2*err
            if e>=dy:err+=dy;x+=sx
            if e<=dx:err+=dx;y+=sy
    def path(self,pts,c,kind='wood',mask=None):
        for a,b in zip(pts,pts[1:]):self.line(a,b,c,kind,mask)
    def paste(self,other,x,y):
        for (px,py),c in other.p.items():self.dot(x+px,y+py,c,other.kind[px,py])
    def bytes(self):return bytes(v for y in range(self.h) for x in range(self.w) for v in self.p.get((x,y),CLEAR))
    def components(self):
        left=set(self.p);result=[]
        while left:
            seed=next(iter(left));comp={seed};left.remove(seed);q=[seed]
            for x,y in q:
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)]:
                    p=x+dx,y+dy
                    if p in left:left.remove(p);comp.add(p);q.append(p)
            result.append(comp)
        return sorted(result,key=len,reverse=True)

# Leaf tufts are explicit native pixel clusters, not noise or sampled imagery.
TUFTS=[['...44.....','..445443..','.34444333.','3444333332','.333323322','..3322222.','...2221...'],
       ['..44....','.344433.','34443333','34433332','.333222.','..2221..'],
       ['....44....','..344443..','.344443332','344333332.','.33322222.','..22221...'],
       ['...44...','..34443.','.3444333','34433332','.332222.','..2221..']]
SPRAYS=[(-.40,-.32,0),(.21,-.51,1),(.57,-.13,2),(-.65,.25,3),
        (-.11,.20,2),(.39,.46,0)]

def lobe(c,cx,cy,rx,ry,variant=0,palette=LEAF):
    # An authored sequence of shoulders, notches and pointed leaf tips.
    outline=[(-.92,-.12),(-.65,-.40),(-.69,-.58),(-.40,-.60),(-.24,-.90),
        (.0,-.79),(.18,-1.0),(.36,-.72),(.62,-.70),(.60,-.40),(.90,-.37),
        (.78,-.10),(1,.03),(.90,.25),(.69,.37),(.79,.60),(.47,.65),(.37,.90),
        (.10,.73),(-.06,.93),(-.27,.68),(-.51,.74),(-.59,.51),(-.87,.43),(-.79,.20),(-1,.12)]
    shape=Canvas(c.w,c.h);shape.polygon([(cx+x*rx,cy+y*ry) for x,y in outline],palette[0])
    mask=set(shape.p);c.paste(shape,0,0)
    c.polygon([(cx-rx,cy-ry),(cx+rx,cy-ry),(cx+rx*.62,cy+ry*.5),(cx,cy+ry*.65),(cx-rx,cy+ry*.3)],palette[2],mask=mask)
    c.polygon([(cx-rx*.6,cy-ry*.62),(cx+rx*.2,cy-ry*.85),(cx+rx*.70,cy-ry*.2),(cx+rx*.15,cy+ry*.3),(cx-rx*.65,cy+ry*.18)],palette[3],mask=mask)
    for i,(dx,dy,stamp) in enumerate(SPRAYS):
        px=round(cx+dx*rx)-4;py=round(cy+dy*ry)-3
        pattern=TUFTS[(stamp+variant)%len(TUFTS)]
        shade_shift=-1 if dy>.3 else 0
        for yy,row in enumerate(pattern):
            for xx,ch in enumerate(row):
                if ch!='.':c.dot(px+xx,py+yy,palette[max(1,min(5,int(ch)+shade_shift))],mask=mask)

def native_tree(species='oak',w=80,h=96,variant=0):
    c=Canvas(w,h);sx=w/80;sy=h/96
    def pt(x,y):return round(x*sx),round(y*sy)
    def poly(pts,index):c.polygon([pt(x,y) for x,y in pts],WOOD[index],'wood')
    def path(pts,index):c.path([pt(x,y) for x,y in pts],WOOD[index],'wood',set(p for p in c.p if c.kind[p]=='wood'))
    # Exposed branching architecture, bark ribbons, split roots and a clean basal anchor.
    poly([(25,94),(28,90),(33,87),(36,80),(37,71),(33,64),(29,59),(20,55),(16,48),(19,44),(24,49),(33,53),(37,59),(40,53),(39,42),(36,33),(39,29),(43,37),(45,48),(50,43),(55,34),(59,32),(58,41),(54,50),(48,57),(43,67),(43,77),(46,84),(52,90),(58,94),(46,94),(41,91),(38,95),(29,95)],0)
    poly([(28,92),(35,86),(39,75),(39,66),(35,60),(31,56),(21,52),(20,48),(26,53),(34,55),(40,62),(43,55),(43,40),(41,34),(45,40),(46,51),(52,45),(56,39),(55,46),(49,54),(42,65),(41,78),(44,86),(49,92),(42,88),(39,92),(36,93),(38,86),(34,90)],2)
    poly([(30,92),(36,84),(39,77),(40,67),(39,62),(42,58),(43,49),(44,39),(45,43),(45,53),(42,63),(42,71),(39,84),(39,90),(35,93)],3)
    path([(28,92),(34,87),(37,80),(39,68),(37,63),(32,59),(24,54),(20,49)],4)
    path([(32,94),(37,90),(39,82),(41,78),(42,69),(41,65),(46,55),(53,47),(55,42)],1)
    path([(42,82),(45,89),(51,93)],4)
    path([(42,58),(44,51),(44,41)],4)
    path([(38,87),(40,81),(39,75),(40,69)],5)
    if species in ['oak','blue','apple','ash','olive','pine','windswept']:
        poly([(25,94),(30,90),(33,84),(35,77),(34,69),(30,62),(23,57),(17,50),(18,44),(22,45),(25,51),(32,55),(37,61),(39,52),(39,41),(35,31),(40,27),(44,35),(46,44),(46,52),(52,46),(55,35),(60,31),(62,33),(59,46),(54,53),(49,59),(47,69),(47,78),(50,84),(55,88),(62,93),(58,95),(47,94),(42,89),(40,94),(33,95)],0)
        poly([(29,93),(35,84),(38,75),(38,67),(32,59),(24,55),(20,48),(24,52),(33,56),(40,63),(42,54),(42,42),(39,32),(42,34),(45,43),(44,57),(49,53),(55,47),(58,37),(58,44),(53,52),(46,61),(43,73),(43,80),(48,86),(53,91),(46,88),(41,83),(38,92)],2)
        poly([(31,91),(35,81),(38,73),(37,67),(33,61),(28,57),(32,58),(40,64),(41,70),(39,80),(37,87),(37,92)],3)
        poly([(44,62),(49,55),(54,50),(57,45),(56,50),(50,56),(46,66),(44,77),(45,83),(43,80),(42,73)],3)
        path([(30,92),(34,86),(36,80),(38,74),(39,68)],4)
        path([(33,92),(37,87),(39,80),(42,75),(42,66),(46,58),(53,51)],1)
        path([(45,75),(46,82),(50,87),(56,91)],4)
        path([(40,60),(43,54),(44,46),(42,37)],4)
        path([(40,79),(39,84),(40,89)],0)
        path([(36,69),(34,65),(30,61),(23,56)],1)
    if species in ['oak','blue','apple','ash']:
        if species=='ash':lobes=[(39,16,13,12),(29,29,12,11),(47,29,13,12),(26,44,12,11),(42,44,15,12),(34,57,15,10),(49,58,11,8)];cut=73
        else:lobes=[(39,16,15,11),(23,27,14,10),(53,29,15,11),(13,41,12,10),(34,39,16,12),(61,45,13,11),(25,55,16,10),(55,56,15,9)];cut=74
        pal=LEAF if species!='blue' else list(map(color,['293730','354741','465c50','607762','83917a','a0a58a']))
        for i,(x,y,rx,ry) in enumerate(lobes):lobe(c,*pt(x,y),max(4,round(rx*sx)),max(4,round(ry*sy)),(variant+i)%4,pal)
        if species=='apple':
            for x,y in [(26,27),(43,32),(19,47),(37,54),(57,46)]:
                px,py=pt(x,y);c.polygon([(px-1,py-2),(px+2,py-2),(px+2,py+1),(px,py+2),(px-2,py)],color('744b3d'))
                c.dot(px-1,py-1,color('b48255'));c.dot(px,py-1,color('9b6250'));c.dot(px,py-3,WOOD[0])
    elif species in ['olive','pine','windswept']:
        if species=='pine':lobes=[(38,21,23,10),(17,29,15,9),(59,27,16,10),(38,32,20,9)];cut=58
        elif species=='olive':lobes=[(27,22,14,7),(51,29,17,7),(16,43,13,7),(60,48,14,7),(36,51,12,7)];cut=69
        else:lobes=[(50,16,16,9),(29,28,19,9),(53,36,19,10),(21,44,14,9),(57,52,16,9)];cut=72
        for i,(x,y,rx,ry) in enumerate(lobes):lobe(c,*pt(x,y),max(4,round(rx*sx)),max(3,round(ry*sy)),(variant+i)%4)
    else:
        # Upright evergreens use explicit descending whorls; the lower edge of
        # the final bough is visible before the exposed stem and the cut.
        c=Canvas(w,h)
        center=w//2
        c.polygon([(center-2,h-29),(center+2,h-29),(center+2,h-9),(center+8,h-2),(center+1,h-3),(center-3,h-1),(center-8,h-2),(center-2,h-9)],WOOD[0],'wood')
        c.path([(center,h-27),(center-1,h-12),(center-5,h-3)],WOOD[3],'wood')
        c.path([(center+1,h-19),(center+1,h-8),(center+4,h-3)],WOOD[2],'wood')
        if species=='spruce':
            for j in range(7):
                yy=round((12+j*9)*sy);rx=round((4+j*3.4)*sx);ry=max(3,round(12*sy))
                mask=Canvas(w,h);mask.polygon([(center,yy-ry),(center+rx,yy+2),(center+rx//2,yy),(center+rx-2,yy+5),(center+2,yy+3),(center,yy+6),(center-3,yy+3),(center-rx,yy+5),(center-rx//2,yy),(center-rx,yy+1)],LEAF[0])
                pts=set(mask.p);c.paste(mask,0,0)
                c.polygon([(center-1,yy-ry+2),(center+rx-2,yy+1),(center,yy+2),(center-rx+2,yy+1)],LEAF[2],mask=pts)
                for dx in range(-max(1,rx-2),1,3):c.path([(center+dx,yy+1),(center+dx+2,yy-2),(center+dx+3,yy-3)],LEAF[4],'leaf',pts)
            cut=83
        else:
            lobes=[(40,10,4,7),(39,20,7,10),(42,32,9,11),(36,42,10,11),(43,54,10,12),(38,65,10,10)]
            pal=LEAF if species!='gold' else list(map(color,['343b30','4d5038','686744','8a8051','a39065','c0ac7c']))
            for i,(x,y,rx,ry) in enumerate(lobes):lobe(c,*pt(x,y),max(3,round(rx*sx)),max(3,round(ry*sy)),(variant+i)%4,pal)
            cut=82
    cut_y=round(cut*sy)
    leaf_bottom=max(y for (x,y),kind in c.kind.items() if kind=='leaf')
    assert leaf_bottom<cut_y-1,(species,'cut intersects foliage',leaf_bottom,cut_y)
    # These pixels are reconstructed architecture, never a leftover crop.
    comps=c.components()
    if len(comps)>1:
        raise AssertionError((species,'disconnected native geometry',[len(a) for a in comps]))
    return c,cut_y

def split_tree(full,cut):
    upper=Canvas(full.w,full.h);base=Canvas(full.w,full.h);stump=Canvas(full.w,full.h)
    for (x,y),co in full.p.items():
        if y<=cut+1:upper.dot(x,y,co,full.kind[x,y])
        if y>=cut:base.dot(x,y,co,full.kind[x,y])
        if y>=full.h-12:stump.dot(x,y,co,'wood')
    centre=full.w//2;yb=full.h-13;radius=max(3,round(full.w*.085))
    stump.polygon([(centre-radius,yb),(centre+radius,yb),(centre+radius-1,yb+8),(centre+radius+2,yb+11),(centre-2,yb+10),(centre-radius-2,yb+11)],WOOD[0],'wood')
    stump.polygon([(centre-radius+1,yb+2),(centre+radius-1,yb+2),(centre+radius-1,yb+8),(centre-1,yb+8),(centre-radius+1,yb+10)],WOOD[2],'wood')
    stump.line((centre-radius+2,yb+2),(centre-radius+2,yb+8),WOOD[4])
    stump.line((centre+1,yb+3),(centre,yb+9),WOOD[1])
    stump.polygon([(centre-radius,yb+1),(centre-radius+2,yb-1),(centre+radius-2,yb-1),(centre+radius,yb+1),(centre+radius-2,yb+3),(centre-radius+2,yb+3)],WOOD[4],'wood')
    stump.line((centre-radius+3,yb),(centre+radius-3,yb),WOOD[5])
    stump.line((centre-radius+2,yb+2),(centre+radius-2,yb+2),WOOD[2])
    stump.dot(centre,yb+1,WOOD[2],'wood')
    return upper,base,stump

def requests_for(name,c):
    payload=[[x,y,*col] for (x,y),col in sorted(c.p.items(),key=lambda kv:(kv[0][1],kv[0][0]))]
    path=OUT/name
    req=[{'tool':'pixelorama_create_project','args':{'name':name,'width':c.w,'height':c.h,'frame_count':1}}]
    req += [{'tool':'pixelorama_set_pixels','args':{'frame':0,'layer':0,'pixels':payload[i:i+4000]}} for i in range(0,len(payload),4000)]
    req += [{'tool':'pixelorama_save_project','args':{'path':str(path.with_suffix('.pxo'))}},
            {'tool':'pixelorama_open_project','args':{'path':str(path.with_suffix('.pxo'))}},
            {'tool':'pixelorama_export_spritesheet','args':{'path':str(path.with_suffix('.png')),'frame_count':1,'columns':1,'layer':0}}]
    record={'name':name,'size':[c.w,c.h],'rgba_sha256':hashlib.sha256(c.bytes()).hexdigest(),'native_pixel_edits':len(payload),'colors':len(set(c.p.values()))}
    return req,record

def proof():
    OUT.mkdir(exist_ok=True,parents=True)
    tree,cut=native_tree('oak');upper,base,stump=split_tree(tree,cut)
    board=Canvas(352,112)
    for i,c in enumerate([tree,base,upper,stump]):board.paste(c,4+i*88,12)
    req,record=requests_for('oak-native-proof-v2',board)
    record.update(cut_y=cut,leaf_bottom=max(y for (x,y),k in tree.kind.items() if k=='leaf'),connected=True)
    (OUT/'proof-requests.json').write_text(json.dumps([{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}]+req))
    (OUT/'proof-manifest.json').write_text(json.dumps(record,indent=2))
    print(record)

if __name__=='__main__':proof()
