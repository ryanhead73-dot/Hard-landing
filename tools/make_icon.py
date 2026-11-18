## Draws the game icon: Kestrel coming in nose-down onto oxide-orange ground.
## Usage: python tools/make_icon.py godot   (writes godot/icon.png and godot/icon.ico; needs Pillow)
import sys, math
from PIL import Image, ImageDraw
N=1024
im=Image.new('RGBA',(N,N),(0,0,0,0))
d=ImageDraw.Draw(im)
d.rounded_rectangle([0,0,N-1,N-1],radius=190,fill=(21,24,27,255))
# ground: oxide orange slab with a cream edge
d.polygon([(0,760),(N,700),(N,N),(0,N)],fill=(196,98,45,255))
d.line([(0,760),(N,700)],fill=(233,225,204,255),width=26)
# ship: delta silhouette, nose down to the right, tilted
cx,cy=470,470; a=math.radians(27)
pts=[(360,0),(-330,-250),(-210,0),(-330,250)]  # nose, wingtip, tail notch, wingtip
def rot(p):
    x,y=p; return (cx+x*math.cos(a)-y*math.sin(a), cy+x*math.sin(a)+y*math.cos(a))
d.polygon([rot(p) for p in pts],fill=(233,225,204,255))
# skid: a dark gouge in the ground ahead of the nose
d.polygon([(700,742),(1024,712),(1024,760),(760,790)],fill=(120,52,24,255))
# cockpit stripe
d.polygon([rot(p) for p in [(250,0),(120,-40),(120,40)]],fill=(255,178,77,255))
# rounded mask
mask=Image.new('L',(N,N),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,N-1,N-1],radius=190,fill=255)
im.putalpha(Image.composite(im.split()[3],Image.new('L',(N,N),0),mask))
out=sys.argv[1]
im.resize((256,256),Image.LANCZOS).save(out+'/icon.png')
im.save(out+"/icon.ico",sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
prev=Image.new('RGBA',(256+64+48+32+16+5*10,256),(240,240,240,255))
x=0
for s in [256,64,48,32,16]:
    prev.paste(im.resize((s,s),Image.LANCZOS),(x,0),im.resize((s,s),Image.LANCZOS)); x+=s+10
prev.save(out+'/icon_preview.png')
