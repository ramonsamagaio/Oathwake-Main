"""Renderiza a pose projetada pelo runtime, para conferir a silhueta sem abrir o Godot."""
import json, math, sys
from PIL import Image, ImageDraw
import build_monster as B

TILE_W, TILE_H = 24.0, 16.0
FOV = math.radians(25.0); CAM_X = -math.pi*0.25; SKEW = 0.45
SW, SH = 640.0, 360.0
CAM_Z = SH/(2.0*math.tan(FOV*0.5)*TILE_H)

def globalize(v, face):
    a=math.radians(face-180.0); c,s=math.cos(a),math.sin(a)
    o=(v[0]*c-v[1]*s, v[0]*s+v[1]*c, v[2])
    return (round(o[0]*TILE_W*2)/(TILE_W*2), round(o[1]*TILE_H*2)/(TILE_H*2), round(o[2]*TILE_H*2)/(TILE_H*2))

def project(w):
    x=w[0]*(TILE_W/TILE_H); y=-w[1]+SKEW*w[2]; z=w[2]
    c,s=math.cos(CAM_X),math.sin(CAM_X)
    vy=y*c-z*s; vz=y*s+z*c-CAM_Z
    ww=max(-vz,0.001); f=1.0/math.tan(FOV*0.5); asp=SW/SH
    return (SW*0.5*((f/asp)*x/ww), -SH*0.5*(f*vy/ww))

CHAINS=[('root','spine'),('spine','top'),('top','chest'),('chest','neck'),('neck','head'),
        ('bottom','hipL'),('hipL','legL'),('legL','footL'),('footL','toeL'),
        ('bottom','hipR'),('hipR','legR'),('legR','footR'),('footR','toeR'),
        ('chest','shoulderL'),('shoulderL','armL'),('armL','handL'),('handL','fingerL'),('fingerL','fistL'),
        ('chest','shoulderR'),('shoulderR','armR'),('armR','handR'),('handR','fingerR'),('fingerR','fistR')]
COL={'L':(90,190,255),'R':(255,140,90)}

def draw(nodes, anim, faces, frames, path):
    cw,ch=190,230
    img=Image.new('RGB',(cw*len(faces),ch*len(frames)),(18,20,26)); d=ImageDraw.Draw(img)
    for r,fr in enumerate(frames):
        nx=anim['transforms'][fr]['nodeXfm']
        fk=B.fk_positions(nodes,nx)
        for c,face in enumerate(faces):
            ox,oy=c*cw+cw//2, r*ch+ch-40
            P={n:project(globalize(v,face)) for n,v in fk.items()}
            for a,b in CHAINS:
                col=COL.get(a[-1],COL.get(b[-1],(220,220,220)))
                if not (a[-1] in 'LR' or b[-1] in 'LR'): col=(210,210,215)
                d.line([ox+P[a][0]*2.2, oy+P[a][1]*2.2, ox+P[b][0]*2.2, oy+P[b][1]*2.2], fill=col, width=3)
            for n,p in P.items():
                d.ellipse([ox+p[0]*2.2-2, oy+p[1]*2.2-2, ox+p[0]*2.2+2, oy+p[1]*2.2+2], fill=(255,235,120))
            d.text((c*cw+8, r*ch+8), '%s  quadro %d' % (['S','SE','E','NE','N'][c], fr), fill=(150,200,230))
    img.save(path)

if __name__=='__main__':
    d=json.load(open(sys.argv[1])); f=d['figures']['Oathwake-Monster-01']
    name=sys.argv[3] if len(sys.argv)>3 else 'walk'
    draw(f['nodes'], f['anims'][name], [180.0,135.0,90.0,45.0,0.0], [0,6,12,18], sys.argv[2])
    print('ok', sys.argv[2])
