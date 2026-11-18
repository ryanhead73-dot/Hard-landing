"""Builds Juno as a skinned character with keyframed animations and exports it as GLB.

    python blender/build_juno.py            # with `pip install bpy==4.2.0`
    blender --background --python blender/build_juno.py

The pressure garment is a single tailored surface with stitched gussets and articulated
bellows. The composite shells, EVA hardware and articulated gloves share its skinned mesh.
Colour, chipped edges and short-range occlusion are baked into the mesh by creature_kit.

Every animation is an action keyed here and exported as its own clip. Poses are written the way
the game's old procedural animator wrote them: per joint, degrees about Godot's x, y and z in
the joint's rest frame (+x swings a limb forward or tips the torso back; -x on a shin or forearm
bends the knee back or the elbow up). pose_key() turns that into Blender bone rotations.

Output: godot/assets/models/juno_rigged.glb, and blender/juno_rigged.blend so the clips can be
opened and edited by hand in Blender.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as bm
from creature_kit import C, Creature, Geo, V, fbm, lathe, mix, smooth, tube

ROOT = bm.ROOT
OUT = bm.OUT
FPS = 30

# Godot model space: +x is the wearer's right and -z is forward.
IVORY = C("dbcfaf")
OXIDE = C("b85b32")
PRIMER = C("716d61")
THREAD = C("202a2a")
TEAL = C("344342")
WEB = "46432e"
IRON = "414542"
STEEL = "858779"
RUBBER = "343936"
TAU = math.tau


def skeleton(c):
    # Keep the original rig's joint origins and rest axes. The mesh extends below the
    # head pivot so its crown fits the player height without shortening the arm IK chain.
    c.bones["Hips"] = (V((0, .95, 0)), V((0, 1.07, 0)), None, True)
    c.bone("Spine", (0, 1.07, 0), (0, 1.32, 0), "Hips")
    c.bone("Chest", (0, 1.32, 0), (0, 1.68, 0), "Spine")
    c.bone("Neck", (0, 1.68, 0), (0, 1.74, 0), "Chest")
    c.bone("Head", (0, 1.74, 0), (0, 2, 0), "Neck")
    c.bone("PackMount", (0, 1.44, .2), (0, 1.56, .2), "Chest")
    c.bone("WeaponMount", HOLD_W[0], (.13, 1.27, -.6), "Chest", deform=False)
    for side, s in (("L", -1), ("R", 1)):
        x = s * .26
        c.bone("Arm"+side, (x, 1.62, 0), (x, 1.27, 0), "Chest")
        c.bone("Forearm"+side, (x, 1.27, 0), (x, .92, 0), "Arm"+side)
        c.bone("Hand"+side, (x, .977, 0), (x, .904, 0), "Forearm"+side)
        c.bone("Fingers"+side, (x, .906, 0), (x-.018*s, .857, 0), "Hand"+side)
        c.bone("Thumb"+side, (x-.012*s, .941, -.026), (x-.037*s, .9, -.044), "Hand"+side)
        x = s * .1
        c.bone("Leg"+side, (x, .89, 0), (x, .46, 0), "Hips")
        c.bone("Shin"+side, (x, .46, 0), (x, .03, 0), "Leg"+side)
        c.bone("Foot"+side, (x, .105, 0), (x, .052, -.15), "Shin"+side)


def sample(rows, y):
    """Linearly sample a measured section of a pattern at height y."""
    for a, b in zip(rows, rows[1:]):
        if y <= b[0]:
            t = max(0, (y-a[0]) / (b[0]-a[0]))
            return tuple(v + (w-v)*t for v, w in zip(a[1:], b[1:]))
    return rows[-1][1:]


class Suit(Creature):
    def _weights(self, part, verts):
        if part["geo"] in self.shoulder_caps:
            arm = self.shoulder_caps[part["geo"]]
            return [blend_bones("Chest",arm,.28+.58*smooth(1.56,1.45,v.y)) for v in verts]
        if part["geo"] is self.garment:
            return self.stitch_weights
        return super()._weights(part, verts)


def blend_bones(first, second, t):
    return [(b, w) for b, w in ((first, 1-t), (second, t)) if w > .00001]


def undersuit(c):
    # Each trouser leg meets its neighbour along the crotch seam. The outer halves
    # of those rings become the waist. Sleeve rings are sewn into holes in the yoke.
    geo = c.garment = Geo()
    weights = c.stitch_weights = []
    shades = {}
    count = 24

    def vertex(p, ws, seam, i, row):
        idx = len(geo.verts)
        v = V(p)
        geo.verts.append(v)
        weights.append(ws)
        shades[tuple(v)] = seam
        c.cloth_uv[tuple(v)] = (i/count, (row%24)/24)
        return idx

    def sew(lo, hi, row=0, omit=()):
        for i in range(count):
            if i in omit:
                continue
            j = (i+1) % count
            # Follow the two diagonal stitch directions across the lattice.
            a, b, d, e = lo[i], lo[j], hi[i], hi[j]
            if (i-row) % 4 < 2:
                geo.faces.extend([(a,b,e), (a,e,d)])
            else:
                geo.faces.extend([(a,b,d), (b,e,d)])

    def stitch(i, row):
        return float((i+row) % 6 == 0 or (i-row) % 6 == 0)

    def cloth(p, n):
        grime = .12 + .12*fbm(p, 28)
        return mix(TEAL, THREAD, grime + .08*shades[tuple(p)])

    leg_form = [(.09,.052,.052),(.19,.056,.062),(.31,.075,.083),(.405,.062,.071),
                (.46,.07,.079),(.53,.074,.078),(.67,.085,.098),(.8,.097,.109),(.91,.1,.119)]
    crotch = {}
    waist = {}
    for side, s in (("R",1),("L",-1)):
        for row in range(43):
            y = .09 + .82*row/42
            rx, rz = sample(leg_form, y)
            joint = math.exp(-((y-.46)/.061)**4)
            ring = []
            for i in range(count):
                a = TAU*i/count
                sin, cos = math.sin(a), math.cos(a)
                seam = stitch(i,row)
                delta = .003*(1-seam) + joint*.005*math.cos((y-.46)*226 + .5*cos)
                x = .103 + (rx+delta)*sin
                z = -(rz+delta)*cos + .007*math.sin(y*12)
                gusset = smooth(.805,.91,y)
                x += (max(0,.192*sin)-x)*gusset
                z += (-.119*cos-z)*gusset
                h = y - .056*max(0,-sin)*gusset
                ws = blend_bones("Shin"+side, "Leg"+side, smooth(.406,.514,y))
                if y > .805:
                    ws = blend_bones("Leg"+side, "Hips", gusset)
                if row == 42 and (i == 0 or i >= count//2) and i in crotch:
                    idx = crotch[i]
                else:
                    idx = vertex((s*x,h,z),ws,seam,i,row)
                if row == 42:
                    if i == 0 or i >= count//2:
                        crotch[i] = idx
                    if i <= count//2:
                        waist[(i*s) % count] = idx
                ring.append(idx)
            if row:
                sew(last, ring, row)
            else:
                geo.faces.append(tuple(reversed(ring)))
            last = ring

    form = [(.91,.192,.119),(.98,.195,.13),(1.06,.158,.11),(1.15,.143,.106),
            (1.27,.159,.123),(1.38,.188,.137),(1.44,.201,.131),
            (1.5,.199,.108),(1.525,.155,.086),(1.548,.082,.077)]
    heights = [.91 + .47*j/32 for j in range(33)] + [1.38+.02*j for j in range(1,7)] + [1.525,1.548]
    torso = [[waist[i] for i in range(count)]]
    for row, y in enumerate(heights[1:],1):
        rx, rz = sample(form,y)
        ring = []
        for i in range(count):
            a = TAU*i/count
            seam = stitch(i,row)
            d = .003*(1-seam)
            ws = blend_bones("Hips","Spine",smooth(1.005,1.135,y))
            if y > 1.22:
                ws = blend_bones("Spine","Chest", smooth(1.22,1.36,y))
            ring.append(vertex(((rx+d)*math.sin(a),y,-(rz+d)*math.cos(a)),ws,seam,i,row))
        omit = list(range(3,9)) + list(range(15,21)) if 32 < row <= 38 else []
        sew(torso[-1],ring,row,omit)
        torso.append(ring)
    geo.faces.append(tuple(torso[-1]))

    arm_form = [(.966,.037,.041),(1.01,.041,.047),(1.13,.057,.065),
                (1.22,.055,.056),(1.27,.052,.054),(1.33,.061,.061),
                (1.43,.07,.081),(1.493,.072,.077)]
    for side,s,start in (("R",1,3),("L",-1,15)):
        for row in range(29):
            y = .966 + .527*row/28
            rx, rz = sample(arm_form,y)
            ring = []
            for i in range(count):
                a = TAU*i/count
                seam = stitch(i,row)
                rib = math.exp(-((y-1.27)/.063)**4)*.004*math.cos(218*y)
                d = .002*(1-seam) + rib
                tilt = smooth(1.44,1.493,y)
                x = .26 - .023*tilt + (rx+d)*math.sin(a)*(1-.26*tilt)
                h = y + .043*math.sin(a)*tilt
                ws = blend_bones("Forearm"+side,"Arm"+side,smooth(1.22,1.32,y))
                ring.append(vertex((s*x,h,-(rz+d)*math.cos(a)),ws,seam,i,row))
            if row:
                sew(last,ring,row)
            else:
                geo.faces.append(tuple(ring))
            last = ring
        # Walk the armhole and match its cyclic start to the sleeve head.
        hole = ([torso[32][j] for j in range(start,start+6)] +
                [torso[r][start+6] for r in range(32,38)] +
                [torso[38][j] for j in range(start+6,start,-1)] +
                [torso[r][start] for r in range(38,32,-1)])
        orders = [[hole[(k+d*i)%count] for i in range(count)] for k in range(count) for d in (-1,1)]
        cuff = min(orders,key=lambda seq: sum((geo.verts[i]-geo.verts[j]).length_squared for i,j in zip(seq,last)))
        sew(last,cuff)
    c.part(geo,"Hips","Textile",cloth)


# One packed atlas shared by the ceramic faces and woven pressure garment.
# Tile zero stays white for parts whose whole finish is baked in vertex colour.
TILE_SIZE = 256
TILE_PAD = 4


def make_atlas(styles):
    n = TILE_SIZE-2*TILE_PAD
    v,u = np.mgrid[0:n,0:n]/(n-1)
    rng = np.random.default_rng(731)
    def noise(cells):
        grid = rng.random((cells+1,cells+1))
        x = np.minimum(u*cells,cells-.00001)
        y = np.minimum(v*cells,cells-.00001)
        a,b = x.astype(int),y.astype(int)
        fx,fy = x-a,y-b
        return ((1-fx)*(1-fy)*grid[b,a] + fx*(1-fy)*grid[b,a+1] +
                (1-fx)*fy*grid[b+1,a] + fx*fy*grid[b+1,a+1])
    atlas = np.ones((4*TILE_SIZE,4*TILE_SIZE,4),dtype=np.float32)

    def store_tile(index, rgb):
        y,x = divmod(index,4)
        padded = np.pad(rgb,((TILE_PAD,TILE_PAD),(TILE_PAD,TILE_PAD),(0,0)),mode="edge")
        atlas[y*TILE_SIZE:(y+1)*TILE_SIZE,x*TILE_SIZE:(x+1)*TILE_SIZE,:3] = np.clip(padded/255,0,1)

    # Double-needle quilting. The two stitches, the channel and its raised lip
    # are sampled per texel. In geometry, the quilt has a shallow padded crown.
    def seam(x):
        return abs((x+.5)%1-.5)
    d = np.minimum(seam(6*u+3*v),seam(6*u-3*v))
    quilting = 209-54*np.exp(-(d/.034)**2)-21*np.exp(-(d/.1)**2)
    quilting += 14*(abs(d-.045)<.012)*(np.sin(v*TAU*81)>.05)
    quilting += 3*np.sin(u*TAU*95)*np.sin(v*TAU*79)
    store_tile(1,np.repeat(quilting[:,:,None],3,axis=2))

    glyphs = {"K":["101","110","100","110","101"],"0":["111","101","101","101","111"],
              "7":["111","001","010","010","010"],"E":["111","100","110","100","111"]}
    for style,index in styles.items():
        rgb = np.zeros((n,n,3)) + [216,199,165]
        stripe = np.zeros((n,n),dtype=bool)
        if style in ("long stripe","shoulder"):
            stripe = abs(u-(.26+.26*v)) < (.085 if style=="shoulder" else .072)
        elif style=="breast":
            stripe = abs(v-(.78-.11*abs(2*u-1))) < .049
        elif style=="oxide crown":
            stripe = v<.92
        elif style=="brow":
            stripe = abs(u-.5)<.155
        rgb[stripe] = [181,85,43]
        # Recessed bead just inside the cut edge, individual quarter-turn
        # fasteners, and their steel slots survive at different camera distances.
        edge = np.minimum.reduce((u,1-u,v,1-v))
        small = style in ("plain","upper arm","boot","knee","brow","helmet","crown","oxide crown")
        rim = .041 if small else .034
        rgb[abs(edge-rim)<.005] = [115,110,96]
        rgb[abs(edge-rim-.009)<.003] = [238,229,206]
        for x in (.09,.91):
            for y in (.11,.87):
                dist = ((u-x)/.014)**2+((v-y)/.018)**2
                rgb[dist<1.42]=[95,92,82]
                rgb[dist<.78]=[158,155,142]
                rgb[(dist<.55)&(abs(v-y-.44*(u-x))<.0029)]=[57,57,51]
        if style=="breast":
            # Angular routed channel around the central press-form.
            side = abs(u-.5)
            bottom = .23+.09*np.minimum(1,side/.18)
            top = .63-.08*np.maximum(0,side-.12)/.13
            width = .21-.04*np.maximum(0,.5-v)
            groove = ((abs(side-width)<.006)&(v>bottom)&(v<top))
            groove |= ((abs(v-bottom)<.007)|(abs(v-top)<.007))&(side<width)
            rgb[groove] = [114,109,95]
            for k in range(3):
                rgb[(side<.05)&(abs(v-(.37+k*.027))<.005)] = [93,89,77]
        if style in ("breast","shoulder","long stripe"):
            word = {"breast":"K07","shoulder":"07","long stripe":"E7"}[style]
            ux,vy = (.61,.54) if style=="breast" else (.55,.69)
            w,h = (.011,.019) if style=="breast" else (.019,.019)
            for letter in word:
                for row,bits in enumerate(glyphs[letter]):
                    for col,ch in enumerate(bits):
                        if ch=="1":
                            x,y=ux+col*w,vy+(4-row)*h
                            rgb[(u>=x)&(u<x+w)&(v>=y)&(v<y+h)] = [66,66,57]
                ux+=4*w
            # Manufacturer's rule and grouped serial ticks.
            rgb[(u>.56)&(u<.81)&(abs(v-(vy-.028))<.004)] = [107,98,79]
            rgb[(u>.56)&(u<.74)&(abs(v-(vy-.045))<.006)&((u*126)%1>.43)] = [111,105,92]
        grain = rng.random(u.shape)
        grime = .55*noise(12)+.3*noise(42)+.15*grain
        # Broad patches of primer follow the exposed lip, especially at corners.
        corners = np.minimum(u,1-u) + np.minimum(v,1-v)
        wear = .64*noise(12) + .28*noise(32) + .08*grain
        threshold = .88-.47*np.exp(-edge/.066)-.20*np.exp(-corners/.13)
        if style in ("boot","knee"):
            # Kneeling and toe strikes abrade the forward face in short, raked streaks.
            rub = np.exp(-((u-.5)/.35)**2-((v-.40)/.31)**2)
            threshold -= rub*(.23+.10*np.cos(TAU*(8*v+2*u)))
        chip = wear>threshold
        rgb[chip] = [101,101,94]
        rgb[wear>threshold+.105] = [72,75,73]
        for _ in range(14):
            x,y = rng.uniform(.02,.96,2)
            slope = rng.uniform(-1.4,1.4)
            cut = (abs(v-y-(u-x)*slope)<.0018)&(u>x)&(u<x+rng.uniform(.018,.12))
            rgb[cut & (grain>.32)] = [142,138,125]
        rgb *= (.88+.16*grime-.24*np.exp(-abs(edge-rim)/.025))[:,:,None]
        store_tile(index,rgb)

    img = bpy.data.images.new("juno_atlas",width=atlas.shape[1],height=atlas.shape[0],alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(atlas.ravel())
    img.pack()
    return img


def apply_atlas(c):
    img = make_atlas(c.tiles)
    me = c.mesh.data
    uv = me.uv_layers.new(name="Patterns")
    for poly in me.polygons:
        material = me.materials[poly.material_index].name
        coords = []
        for loop in poly.loop_indices:
            p = me.vertices[me.loops[loop].vertex_index].co
            key = (p.x,p.z,-p.y)
            coord = (0,.5,.5)
            if material=="Enamel":
                coord = c.shell_uv.get(key,coord)
            elif material=="Textile" and key in c.cloth_uv:
                coord = (1,*c.cloth_uv[key])
            coords.append(coord)
        # Trim edges and the underside take their finish entirely from the bake.
        if len({t[0] for t in coords})>1:
            coords = [(0,.5,.5)]*len(coords)
        tile = coords[0][0]
        wrap = [tile==1 and max(q[i] for q in coords)-min(q[i] for q in coords)>.5 for i in (1,2)]
        for loop,(_,u,v) in zip(poly.loop_indices,coords):
            # Centre a crossing face on an interior repeat of the quilt.
            if wrap[0]: u += .5 if u < .5 else -.5
            if wrap[1]: v += 2/3 if v < .5 else -1/3
            def axis(x,cell):
                return (cell*TILE_SIZE+TILE_PAD+.5+x*(TILE_SIZE-2*TILE_PAD-1))/(4*TILE_SIZE)
            uv.data[loop].uv = (axis(u,tile%4),axis(v,tile//4))

    for name in ("Enamel","Textile"):
        m = c.mats[name]
        nodes,links = m.node_tree.nodes,m.node_tree.links
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        tint = nodes.new("ShaderNodeMixRGB")
        tint.blend_type = "MULTIPLY"
        tint.inputs[0].default_value = 1
        links.new(tex.outputs["Color"],tint.inputs[1])
        links.new(nodes.get("Gamma").outputs[0],tint.inputs[2])
        links.new(tint.outputs[0],nodes["Principled BSDF"].inputs["Base Color"])


def panel(c, bone, at, rows, arc=(-80,80), *, tilt=None, shape=None, livery=None,
          material="Enamel", color=IVORY, cols=14, pattern="plain", metal_edge=True):
    """A curved stamped panel. The trimmed face folds through a bevel into a dark return.
    rows are height, half-width and depth. tilt(u,v) cuts the silhouette, shape(u,v)
    presses a recess into the face. u spans -1..1 across the pattern and v runs bottom to top."""
    origin = V(at)
    geo = Geo()
    colors = {}
    cols = min(cols, 16)
    enamel = material == "Enamel"
    if enamel:
        if pattern not in c.tiles:
            c.tiles[pattern] = len(c.tiles)+2
        tile = c.tiles[pattern]
    last = len(rows)-1
    for j,(h,rx,rz) in enumerate(rows):
        v = (h-rows[0][0])/(rows[-1][0]-rows[0][0])
        for i in range(cols+1):
            u = i/cols*2-1
            angle = math.radians(arc[0]+(arc[1]-arc[0])*i/cols)
            relief = shape(u,v) if shape else 0
            p = origin + V(((rx+relief)*math.sin(angle), h+(tilt(u,v) if tilt else 0),
                            -(rz+relief)*math.cos(angle)))
            if enamel:
                c.shell_uv[tuple(p)] = tile, 1-i/cols, v
                colors[tuple(p)] = (.96,.96,.96)
            else:
                colors[tuple(p)] = livery(u,v) if livery else color
            geo.verts.append(p)
            if i<cols and j<last:
                k = j*(cols+1)+i
                geo.faces.append((k,k+1,k+cols+2,k+cols+1))
    outline = (list(range(cols+1)) + [j*(cols+1)+cols for j in range(1,last+1)] +
               list(range(last*(cols+1)+cols-1,last*(cols+1)-1,-1)) +
               [j*(cols+1) for j in range(last-1,0,-1)])
    # Fold the bevel back under the face. These open-backed shells seat on fabric or
    # the helmet gasket. A hidden cap across a curved opening can cut through it.
    under = []
    for k in outline:
        p = geo.verts[k]
        radial = V((p.x-origin.x,0,p.z-origin.z)).normalized()
        q = p-radial*.005
        q.y += .003 if p.y < origin.y+(rows[-1][0]+rows[0][0])/2 else -.003
        under.append(len(geo.verts))
        geo.verts.append(q)
        colors[tuple(q)] = C("837d6c") if metal_edge else colors[tuple(p)]
    for i in range(len(outline)):
        j = (i+1)%len(outline)
        geo.faces.append((outline[i],outline[j],under[j],under[i]))
    c.part(geo,bone,material,lambda p,n: colors[tuple(p)],hard=42)
    return geo


def block(c,bone,at,size,color,material="Hardware",rot=None,bevel=.004):
    # Three bevel planes around a clipped rectangular outline. Even a tread or a
    # vent louver catches a highlight without paying for a rounded box.
    x,y,z = (d/2 for d in size)
    b = min(bevel,min(size)*.28)
    geo = Geo()
    for h,inset in ((-y,b),(-y+b,0),(y-b,0),(y,b)):
        w,d = x-inset,z-inset
        cut = min(b,w*.35,d*.35)
        corners = [(-w+cut,-d),(w-cut,-d),(w,-d+cut),(w,d-cut),
                   (w-cut,d),(-w+cut,d),(-w,d-cut),(-w,-d+cut)]
        start = len(geo.verts)
        geo.verts.extend(V((u,h,v)) for u,v in corners)
        if start:
            for i in range(8):
                j = (i+1)%8
                geo.faces.append((start+i-8,start+j-8,start+j,start+i))
    geo.faces.extend((tuple(range(8)),tuple(range(24,32))))
    if rot:
        geo.rotate(rot)
    geo.move(at)
    c.part(geo,bone,material,color,hard=44)


def turning(c,bone,at,profile,color,material="Hardware",segs=14,rot=None,squash=1):
    c.part(lathe(profile,at,segs,rot,squash),bone,material,color,hard=48)


def band(c,bone,at,rx,rz,height,color,material="Textile"):
    profile = [(rx*.98,-height/2),(rx,-height*.34),(rx,height/2)]
    turning(c,bone,at,profile,color,material,14,squash=rz/rx)


def clipped(u,v):
    return .015*(1-v)*max(0,abs(u)-.55)*2 - .012*v*abs(u)**3


def torso_plates(c):
    # Breastplate has a pressed central channel ending in a stepped lower lip.
    panel(c,"Chest",(0,0,-.003),[(1.29,.172,.138),(1.313,.182,.153),(1.402,.211,.17),
          (1.465,.208,.152),(1.514,.18,.11)],(-87,87),cols=32,
          shape=lambda u,v: -.017*(1-smooth(.24,.40,abs(u)))*smooth(.05,.17,v)*(1-smooth(.7,.85,v)),
          tilt=lambda u,v: .028*min(abs(u)*2,1)*(1-v)-.019*v*(1-abs(u)),
          pattern="breast")
    panel(c,"Chest",(0,0,0),[(1.27,.174,.139),(1.35,.193,.157),(1.45,.21,.148),
          (1.51,.187,.115)],(102,258),tilt=clipped)
    for j,(y,rx,rz) in enumerate([(1.057,.109,.125),(1.135,.12,.13),(1.214,.139,.14)]):
        panel(c,"Spine",(0,y,0),[(0,rx*.89,rz),(.018,rx,rz+.008),(.076,rx+.007,rz+.004),
              (.091,rx,rz)],(-65,65),cols=14,tilt=lambda u,v:.026*abs(u)**1.3,
              shape=lambda u,v: -.004*(1-abs(u)))
    for s in (-1,1):
        # Woven load straps follow the slope of the chest and articulate at the waist.
        path = [(.115*s,1.008,-.112),(.127*s,1.156,-.068),(.144*s,1.285,-.083),
                (.153*s,1.35,-.118),(.166*s,1.425,-.116),(.148*s,1.49,-.099),
                (.134*s,1.531,-.044),(.134*s,1.536,.04),(.154*s,1.491,.111)]
        strap = tube(path,[(.026,.009)]*len(path),sides=8,samples=3,up=(0,0,1),caps=("flat","flat"))
        c.part(strap,["Hips","Spine","Chest"],"Textile",WEB)
        for x,y,z,angle in [(.146,1.33,-.108,-12),(.152,1.482,-.103,14)]:
            block(c,"Chest",(s*x,y,z),(.058,.032,.019),STEEL,rot=(angle,0,-8*s))
            block(c,"Chest",(s*x,y,z-.009),(.041,.014,.009),WEB,"Textile",rot=(angle,0,-8*s))
    # A small three-bar salvage tally stamped into the breast.
    for i in range(3):
        block(c,"Chest",(-.064+i*.012,1.417,-.159-i*.0018),(.006,.021,.004),
              "554f41","Enamel",rot=(0,0,-24),bevel=.001)


def helmet(c):
    # Separate crown petals leave actual kerfs either side of the orange centre panel.
    h = "Head"
    center = (0,0,-.003)
    band(c,"Neck",(0,1.536,0),.096,.094,.049,RUBBER)
    for y in (1.517,1.532,1.548):
        band(c,"Neck",(0,y,0),.1,.099,.008,IRON,"Hardware")
    crown = [(1.682,.118,.142),(1.711,.121,.135),(1.747,.108,.111),
             (1.774,.076,.079),(1.783,.044,.047),(1.785,.002,.003)]
    for a,b in [(-17,17),(17.8,88),(88.8,163),(163.8,196.2),(197,271.2),(272,342.2)]:
        panel(c,h,center,crown,(a,b),cols=8,
              pattern="oxide crown" if a in (-17,163.8) else "crown")
    for a,b in [(61,135),(136,224),(225,299)]:
        panel(c,h,center,[(1.556,.091,.10),(1.571,.113,.124),(1.615,.127,.139),
              (1.678,.123,.142),(1.691,.118,.141)],(a,b),cols=10,
              tilt=lambda u,v:.009*abs(u)*(1-v))
    # The seal, inner lip and glass share the same aperture contour. The raised
    # chin bar and brow project forward beyond the face of the lens.
    def aperture(u,v):
        return .049*abs(u)**2.5*(1-v)-.010*abs(u)**2*v
    lens = [(1.57,.103,.13),(1.602,.117,.147),(1.644,.12,.15),(1.687,.115,.143)]
    panel(c,h,center,lens,(-72,72),tilt=aperture,material="Hardware",color=C("302f2a"),cols=26)
    rim = [(1.575,.106,.135),(1.607,.119,.15),(1.644,.122,.153),(1.683,.117,.146)]
    panel(c,h,center,rim,(-68,68),tilt=aperture,material="Amber seal",color=C("975525"),
          metal_edge=False,cols=24)
    glass = [(1.579,.108,.139),(1.608,.12,.153),(1.645,.123,.156),(1.681,.118,.149)]
    def mirror(u,v):
        # Warm metallized glass: a cool upper reflection and a darker horizon
        # break up the amber even in shots with a plain environment.
        col = mix(C("8d4920"),C("c98435"),smooth(.1,.49,v))
        horizon = .48+.13*u-.12*u*u
        col = mix(col,C("563a2a"),smooth(horizon-.06,horizon+.06,v))
        col = mix(col,C("ba803d"),smooth(.54,.94,v))
        return mix(col,C("e1bb79"),.35*smooth(.81,.98,v)*(1-u*u))
    panel(c,h,center,glass,(-64,64),tilt=aperture,material="Gold glass",livery=mirror,
          metal_edge=False,cols=24)
    panel(c,h,center,[(1.538,.088,.119),(1.549,.104,.145),(1.572,.108,.151),
          (1.58,.108,.143)],(-92,92),tilt=lambda u,v:.048*abs(u)**1.65,
          cols=24)
    panel(c,h,center,[(1.682,.119,.151),(1.69,.123,.155),(1.703,.122,.147)],
          (-70,70),tilt=lambda u,v:-.012*abs(u)**2,cols=20,
          pattern="brow")
    block(c,h,(0,1.56,-.149),(.056,.026,.014),IRON,rot=(10,0,0))
    for i in range(3):
        block(c,h,(0,1.552+i*.006,-.158),(.041,.0025,.004),STEEL,rot=(10,0,0))
    for s in (-1,1):
        turning(c,h,(s*.113,1.641,.012),[(.051,0),(.051,.011),(.047,.016),
                (.046,.023),(.041,.025)],IRON,rot=(0,0,-90*s),segs=20)
        turning(c,h,(s*.138,1.641,.012),[(.035,0),(.036,.003),(.031,.006)],
                "8c806a","Enamel",rot=(0,0,-90*s),segs=16)
        for j in range(3):
            a = TAU*j/3
            turning(c,h,(s*.141,1.641+.039*math.sin(a),.012+.039*math.cos(a)),
                    [(.0037,0),(.0037,.002)],"b9b39d",rot=(0,0,-90*s),segs=6)
    turning(c,h,(-.116,1.666,.056),[(.009,0),(.01,.019),(.005,.022),
            (.003,.101),(.004,.105),(.002,.11)],IRON,segs=10)
    block(c,h,(0,1.606,.135),(.099,.032,.012),IRON)
    for i in range(4):
        block(c,h,(-.032+i*.021,1.606,.142),(.008,.017,.006),STEEL)


def limb_plates(c,side,s):
    leg, shin, arm, fore = (n+side for n in ("Leg","Shin","Arm","Forearm"))
    def arc(l,r):
        return (l,r) if s==1 else (-r,-l)
    # Scalloped outside thigh lets the quilt and the strap show at the inner thigh.
    x = s*.103
    for y,rx,rz in ((.621,.101,.115),(.79,.111,.128)):
        band(c,leg,(x,y,0),rx,rz,.041,WEB)
        block(c,leg,(x,y,rz),(.046,.043,.010),STEEL,bevel=.003)
        block(c,leg,(x,y,rz+.006),(.031,.027,.008),WEB,"Textile",bevel=.002)
    panel(c,leg,(x,0,0),[(.55,.078,.085),(.567,.086,.096),(.69,.1,.111),
          (.79,.105,.118),(.835,.10,.113)],arc(-22,115),tilt=clipped,pattern="long stripe",
          shape=lambda u,v:.004*(1-abs(u)))
    panel(c,shin,(x,0,-.012),[(.405,.054,.081),(.423,.074,.092),(.46,.085,.10),
          (.495,.082,.095),(.517,.064,.084)],(-75,75),tilt=clipped,cols=14,pattern="knee",
          shape=lambda u,v:.007*max(0,1-2*abs(u)))
    for y,rx,rz in ((.203,.067,.077),(.361,.081,.086)):
        band(c,shin,(x,y,0),rx,rz,.027,WEB)
    panel(c,shin,(x,0,0),[(.144,.051,.074),(.159,.063,.08),(.295,.078,.093),
          (.374,.081,.09),(.397,.071,.083)],arc(-60,89),tilt=clipped,pattern="long stripe",
          shape=lambda u,v:.007*max(0,1-2.8*abs(u)))
    x = s*.26
    panel(c,arm,(x,0,0),[(1.35,.062,.067),(1.372,.071,.077),(1.448,.08,.086),
          (1.474,.075,.08)],arc(17,156),tilt=clipped,cols=12)
    # Domed shoulder cap and a stepped lower return above the biceps defence.
    cap = panel(c,arm,(x-s*.018,0,0),[(1.449,.083,.085),(1.466,.096,.101),(1.507,.092,.102),
          (1.544,.073,.083),(1.565,.039,.045),(1.57,.015,.019)],arc(-48,220),
          tilt=lambda u,v:.028*abs(u)**2*(1-v),pattern="shoulder",cols=20)
    c.shoulder_caps[cap] = arm
    panel(c,fore,(x,0,0),[(1.223,.048,.057),(1.241,.062,.067),(1.277,.066,.073),
          (1.304,.056,.065)],arc(62,221),cols=12,tilt=clipped)
    band(c,fore,(x,1.181,0),.06,.067,.031,WEB)
    panel(c,fore,(x,0,0),[(.995,.044,.05),(1.009,.051,.058),(1.093,.059,.068),
          (1.163,.067,.075),(1.198,.06,.065)],arc(-62,156),tilt=clipped,pattern="long stripe",
          shape=lambda u,v:.004*max(0,1-3*abs(u)),cols=16)
    band(c,fore,(x,.985,0),.044,.049,.024,IRON,"Hardware")


def gloves(c,side,s):
    x = .26*s
    hand, fingers, thumb = ("Hand"+side,"Fingers"+side,"Thumb"+side)
    band(c,hand,(x,.936,0),.028,.044,.086,RUBBER)
    panel(c,hand,(x,0,0),[(.912,.027,.036),(.923,.033,.047),(.95,.032,.045),
          (.967,.029,.041)],(40,142) if s==1 else (-142,-40),cols=8,tilt=clipped)
    for i,length in enumerate((.056,.066,.061,.048)):
        z = -.031+i*.021
        path = [(x,.912,z),(x+.003*s,.892,z),(x-.003*s,.911-length*.74,z),
                (x-.016*s,.912-length,z-.002)]
        c.part(tube(path,[.012,.012,.010,.008],sides=7,samples=1),fingers,"Textile",RUBBER)
        block(c,fingers,(x+.012*s,.899,z),(.013,.019,.016),"a89c81","Enamel",bevel=.003)
    path = [(x-.004*s,.947,-.027),(x-.018*s,.928,-.044),(x-.031*s,.908,-.049),
            (x-.039*s,.903,-.037)]
    c.part(tube(path,[.018,.017,.014,.010],sides=7,samples=1),thumb,"Textile",RUBBER)


def boot_form(c,bone,x,rows,color,material):
    # Heel and toe have different depths and widths; the last blends into the boot shaft.
    geo = Geo()
    corners = [(-.56,-1),(.52,-1),(.91,-.84),(1,-.46),(.87,.5),(.81,.85),
               (.54,1),(-.58,1),(-.84,.81),(-.88,.44),(-.98,-.50),(-.90,-.84)]
    for j,(y,w,front,back) in enumerate(rows):
        for i,(u,v) in enumerate(corners):
            geo.verts.append(V((x+u*w,y,v*(front if v<0 else back))))
            n = len(corners)
            k = j*n+i
            k1 = j*n+(i+1)%n
            if j:
                geo.faces.append((k-n,k1-n,k1,k))
    geo.faces.extend([tuple(range(n)),tuple(range(len(geo.verts)-n,len(geo.verts)))])
    c.part(geo,bone,material,color,hard=47)


def boots(c,side,s):
    x = .102*s
    foot = "Foot"+side
    boot_form(c,foot,x,[(.009,.074,.177,.078),(.015,.078,.182,.082),
              (.039,.079,.182,.082),(.048,.076,.178,.078)],RUBBER,"Textile")
    for i in range(7):
        z = -.144+i*.032
        for sign in (-1,1):
            block(c,foot,(x+.037*sign,.009,z),(.066,.018,.022),"4b4840","Textile",
                  rot=(0,sign*20,0),bevel=.003)
    boot_form(c,foot,x,[(.045,.074,.175,.078),(.064,.076,.175,.078),(.085,.072,.156,.074),
              (.105,.064,.113,.064),(.141,.054,.058,.058),(.178,.052,.054,.056)],
              "544f42","Textile")
    # Toe shield wraps above the welt. The ankle hinge is independent of the shin guard.
    # The toe shield and the vamp use the same last. Trim its rear edge at the
    # instep and lift the pressed lip clear of the leather.
    toe = [(0.050,.077,.181),(.058,.079,.185),(.076,.078,.17),(.091,.071,.15),(.099,.068,.133)]
    geo = Geo()
    for j,(y,width,reach) in enumerate(toe):
        for i,(u,v) in enumerate([(-.98,.40),(-1,.55),(-.93,.85),(-.57,1),
                                  (.52,1),(.93,.85),(1,.55),(.98,.40)]):
            geo.verts.append(V((x+width*u,y,-reach*v)))
            if j and i:
                k = j*8+i
                geo.faces.append((k-9,k-8,k,k-1))
    # The cap curves back to a shallow flange below the lacing.
    geo.faces.append(tuple(range(32,40)))
    tile = c.tiles.setdefault("boot",len(c.tiles)+2)
    for k,p in enumerate(geo.verts):
        # Sidewall rises into the scuffed toe box; project its top across the instep.
        row,col = divmod(k,8)
        u = col/7
        v = row/4 * (.6 + .4*(1 + p.z/toe[row][2])/.6)
        c.shell_uv[tuple(p)] = tile,u,min(1,v)
    c.part(geo,foot,"Enamel","d0c5ac",hard=38)
    panel(c,foot,(x,0,0),[(.106,.056,.09),(.123,.061,.084),(.155,.066,.073),
          (.169,.064,.075)],(-130,130),cols=12,tilt=clipped)
    band(c,foot,(x,.147,.003),.059,.067,.021,WEB)
    turning(c,foot,(x+s*.055,.13,-.004),[(.021,0),(.02,.009),(.012,.012)],IRON,
            rot=(0,0,-90*s),segs=12)


def pockets(c):
    band(c,"Hips",(0,1.028,0),.184,.133,.062,WEB)
    block(c,"Hips",(0,1.029,-.136),(.081,.052,.023),STEEL,bevel=.008)
    block(c,"Hips",(0,1.03,-.15),(.054,.027,.009),IRON)
    for s in (-1,1):
        for rear in (-1,1):
            x,z = .145*s,rear*.093
            ang = (-34 if rear<0 else -146)*s
            block(c,"Hips",(x,.986,z),(.086,.117,.061),WEB,"Textile",rot=(0,ang,5*s),bevel=.011)
            block(c,"Hips",(x+s*.012,1.007,z+rear*.025),(.088,.052,.026),
                  "686041","Textile",rot=(0,ang,5*s),bevel=.007)
            block(c,"Hips",(x+s*.017,.995,z+rear*.034),(.015,.025,.009),IRON,rot=(0,ang,5*s))
    # Sheathed cable spanner, clipped aft of the left hip.
    block(c,"Hips",(-.19,.919,.045),(.045,.12,.055),WEB,"Textile",rot=(12,0,-7))
    path = [(-.192,.944,.042),(-.198,1.027,.06),(-.192,1.08,.072)]
    c.part(tube(path,[.013,.014,.012],sides=8,samples=1),"Hips","Hardware","a59978")
    for s in (-1,1):
        block(c,"Hips",(-.192+s*.012,1.082,.072),(.012,.033,.023),STEEL,rot=(14,0,-s*22))
    block(c,"LegR",(.195,.737,.012),(.045,.128,.09),"48432e","Textile",rot=(8,0,-4),bevel=.01)
    block(c,"LegR",(.218,.771,.015),(.015,.053,.096),"706548","Textile",rot=(8,0,-4))
    block(c,"LegR",(.226,.744,.012),(.009,.031,.022),IRON)
    # Two field repairs on the pressure garment: umber tape with a stitched-over end.
    for y in (1.381,1.395):
        panel(c,"ArmL",(-.26,0,0),[(y,.07,.082),(y+.009,.071,.082)],
              (-46,12),material="Textile",color=C("a18b64"),tilt=lambda u,v:.01*u,cols=6)


def pack(c):
    b = "PackMount"
    block(c,b,(0,1.324,.151),(.291,.335,.081),IRON,bevel=.014)
    for s in (-1,1):
        block(c,b,(s*.137,1.329,.194),(.027,.346,.056),"9f9b87",bevel=.007)
        block(c,b,(s*.108,1.484,.193),(.064,.043,.08),"ccc2ae","Enamel",rot=(0,0,10*s))
    block(c,b,(0,1.184,.203),(.289,.039,.093),"c2b397","Enamel",bevel=.007)
    block(c,b,(0,1.459,.207),(.276,.056,.098),"b9ab8f","Enamel",bevel=.009)
    for s in (-1,1):
        x,z = s*.084,.237
        profile = [(.017,0),(.032,.009),(.042,.023),(.047,.044),
                   (.047,.203),(.045,.219),(.038,.232),(.024,.24),(.014,.243)]
        turning(c,b,(x,1.197,z),profile,"888b80",segs=20)
        for y in (1.253,1.389):
            band(c,b,(x,y,z),.049,.049,.022,IRON,"Hardware")
            block(c,b,(x,y,z+.047),(.023,.027,.013),STEEL)
        band(c,b,(x,1.327,z),.0477,.0477,.031,"b4643a","Enamel")
        turning(c,b,(x,1.435,z),[(.016,0),(.017,.022),(.021,.025),(.021,.033)],STEEL,segs=8)
        turning(c,b,(x,1.467,z),[(.023,0),(.023,.008)],"a15a35","Enamel",segs=8)
    # Central exhaust louvers sit proud of the bottle carrier.
    block(c,b,(0,1.337,.249),(.071,.177,.051),IRON,bevel=.009)
    for j in range(7):
        block(c,b,(0,1.278+j*.019,.277),(.055,.007,.016),STEEL,rot=(17,0,0),bevel=.001)
    block(c,b,(0,1.449,.264),(.094,.054,.048),"948a76","Enamel")
    block(c,b,(0,1.451,.29),(.072,.034,.009),IRON)
    block(c,b,(0,1.452,.296),(.051,.014,.006),"77dec4","Status")
    # Ribbed breathing umbilical spans the moving helmet connection. Radius
    # undulates along one swept wall so the corrugations remain part of the hose.
    path = [(-.087,1.453,.239),(-.093,1.513,.23),(-.1,1.551,.195),
            (-.105,1.554,.139),(-.109,1.586,.085),(-.102,1.605,.052)]
    hose = tube(path,[.016]*len(path),sides=7,samples=14,up=(1,0,0),
                profile=lambda a,t:1+.16*math.cos(t*TAU*23))
    c.part(hose,[b,"Head"],"Textile",RUBBER)
    # Tool roll with radial folds at the ends and two compression straps.
    roll = [(.035,-.145),(.045,-.138),(.047,-.105),(.042,-.081),(.047,-.053),
            (.049,0),(.047,.053),(.042,.081),(.046,.112),(.043,.139),(.033,.145)]
    turning(c,b,(0,1.123,.194),roll,"857353","Textile",20,rot=(0,0,-90))
    for s in (-1,1):
        turning(c,b,(s*.083,1.123,.194),[(.042,-.011),(.045,-.01),(.045,.01),(.042,.011)],
                "494739","Textile",rot=(0,0,-90))
        block(c,b,(s*.083,1.125,.238),(.03,.021,.011),STEEL)
        spiral = []
        for j in range(21):
            a = j/20*TAU*1.65
            r = .006+j/20*.026
            spiral.append((s*.145,1.123+r*math.sin(a),.194+r*math.cos(a)))
        c.part(tube(spiral,[.0026]*len(spiral),sides=4,samples=1),b,"Textile","504b3c")
    # Right clavicle inspection torch. Only the backpack indicator is teal.
    block(c,"Chest",(.181,1.51,-.045),(.039,.041,.06),IRON,rot=(0,0,-12))
    block(c,"Chest",(.184,1.548,-.065),(.056,.049,.092),"827c69","Hardware",bevel=.009)
    block(c,"Chest",(.184,1.548,-.112),(.048,.04,.014),IRON)
    block(c,"Chest",(.184,1.548,-.121),(.035,.026,.008),"f4d398","Amber seal")


def build_model():
    c = Suit("Juno",root="Hips")
    c.shoulder_caps = {}
    c.shell_uv = {}
    c.cloth_uv = {}
    c.tiles = {}
    skeleton(c)
    c.material("Textile",rough=.9,metal=.01)
    c.material("Enamel",rough=.49,metal=.17)
    c.material("Hardware",rough=.36,metal=.71)
    c.material("Gold glass",rough=.115,metal=.48)
    c.material("Amber seal",rough=.28,metal=.10,emit="ffac59",energy=.55)
    c.material("Status",rough=.23,metal=.06,emit="50d9bd",energy=1.7)
    undersuit(c)
    torso_plates(c)
    helmet(c)
    for side,s in (("L",-1),("R",1)):
        limb_plates(c,side,s)
        gloves(c,side,s)
        boots(c,side,s)
    pockets(c)
    pack(c)
    c.build(ao_reach=.105,ao_floor=.34,ao_samples=16)
    apply_atlas(c)
    return c


# --- Animation ---------------------------------------------------------------------------

# The rifle: where it sits in the hold and when aiming, as (position, Godot degrees) in the
# spine's frame (so it rides the hips, lean and crouch, but not the chest's twist).
HOLD_W = ((0.13, 1.27, -0.40), (-10, 0, 0))
AIM_W = ((0.095, 1.51, -0.40), (0, 0, 0))
# Where the hands go on the rifle, in the weapon's own frame (-z is the muzzle).
GRIP_R = (0.0, -0.12, 0.17)
GRIP_L = (0.0, -0.06, -0.12)
HAND = 0.35  # elbow to the middle of the glove
# Elbows point down and out, the right one a little back (Godot axes, chest frame).
POLE = {"L": (-0.45, -1.0, 0.05), "R": (0.55, -1.0, 0.35)}


def _godot_rot(deg):
    """Godot Euler degrees (applied y, then x, then z, as Node3D does) -> Blender-space matrix."""
    x, y, z = (math.radians(a) for a in deg)
    # Godot axes in Blender: x -> x, y -> z, z -> -y.
    rx = Matrix.Rotation(x, 3, Vector((1, 0, 0)))
    ry = Matrix.Rotation(y, 3, Vector((0, 0, 1)))
    rz = Matrix.Rotation(z, 3, Vector((0, -1, 0)))
    return ry @ rx @ rz


def _fk(arm, rots, locs):
    """Posed armature-space matrices for world-aligned rotations `rots` and offsets `locs`."""
    out = {}
    for b in arm.data.bones:  # parents come first (creation order)
        rest3 = b.matrix_local.to_3x3()
        lq = (rest3.inverted() @ rots[b.name] @ rest3).to_4x4()
        basis = Matrix.Translation(rest3.inverted() @ locs[b.name]) @ lq
        if b.parent:
            out[b.name] = out[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local @ basis
        else:
            out[b.name] = b.matrix_local @ basis
    return out


def _carried(arm, posed, name):
    """How the bone's rest-aligned frame has been moved by its parent: posed_parent @ rest_parent^-1."""
    p = arm.data.bones[name].parent
    return posed[p.name] @ p.matrix_local.inverted()


def _plant(arm, posed, rots, side, ankle, pitch):
    """Solve hip and knee to the ankle hinge, then level the boot independently."""
    leg, shin, foot = (arm.data.bones[name + side] for name in ("Leg", "Shin", "Foot"))
    thigh = shin.head_local - leg.head_local
    calf = foot.head_local - shin.head_local
    delta = ankle - posed[leg.name].translation
    a, b = thigh.length, calf.length
    d = min(delta.length, a + b - .0001)
    direction = delta.normalized()
    forward = bm.g(0, 0, -1)
    pole = (forward - direction * direction.dot(forward)).normalized()
    along = (a*a + d*d - b*b) / (2*d)
    knee = direction * along + pole * math.sqrt(max(0, a*a - along*along))
    hip_rot = thigh.rotation_difference(knee).to_matrix()
    shin_rot = calf.rotation_difference(direction*d - knee).to_matrix()
    rots[leg.name] = _carried(arm, posed, leg.name).to_3x3().inverted() @ hip_rot
    rots[shin.name] = hip_rot.inverted() @ shin_rot
    rots[foot.name] = shin_rot.inverted() @ _godot_rot((pitch, 0, 0))


def _solve_arm(arm, posed, rots, side, target, pole_direction):
    """Two-bone IK: turns Arm<side> and Forearm<side> so the hand lands on `target` (Blender)."""
    up = arm.data.bones["Arm" + side]
    lo = arm.data.bones["Forearm" + side]
    a = (lo.head_local - up.head_local).length
    b = HAND
    c3 = _carried(arm, posed, "Arm" + side).to_3x3()
    s = posed["Arm" + side].translation
    d_vec = target - s
    d = min(max(d_vec.length, abs(a - b) + 1e-3), (a + b) * 0.995)
    dirv = d_vec.normalized()
    pole = c3 @ bm.g(*pole_direction)
    n = (pole - dirv * pole.dot(dirv)).normalized()
    cos_a = (a * a + d * d - b * b) / (2 * a * d)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    elbow = s + a * (dirv * cos_a + n * sin_a)
    hand = s + dirv * d
    u0 = lo.head_local - up.head_local
    w_up = u0.rotation_difference(c3.inverted() @ (elbow - s)).to_matrix()
    v0 = bm.g(0, -HAND, 0)
    cf = c3 @ w_up
    w_lo = v0.rotation_difference(cf.inverted() @ (hand - elbow)).to_matrix()
    rots["Arm" + side] = w_up
    rots["Forearm" + side] = w_lo


def solve(arm, pose, offsets):
    """World-aligned rotations and offsets for every bone, with the rifle placed and the hands
    put on it. pose: {joint: (x, y, z) Godot degrees} plus optional "_w" (rifle (pos, rot) in the
    spine's frame, or None to leave it at rest on the chest), "_ikL"/"_ikR" (a point in the
    rifle's frame for that hand, or None to pose the arm by its angles)."""
    rots = {}
    locs = {}
    for b in arm.data.bones:
        rots[b.name] = _godot_rot(pose.get(b.name, (0, 0, 0)))
        locs[b.name] = bm.g(*(offsets or {}).get(b.name, (0, 0, 0)))
    w = pose.get("_w", HOLD_W)
    posed = _fk(arm, rots, locs)
    for side, (ankle, pitch) in pose.get("_feet", {}).items():
        _plant(arm, posed, rots, side, ankle, pitch)
    if w is None:
        return rots, locs
    spine = posed["Spine"] @ arm.data.bones["Spine"].matrix_local.inverted()
    frame = spine @ Matrix.Translation(bm.g(*w[0])) @ _godot_rot(w[1]).to_4x4()
    # The WeaponMount bone (parented to the chest) is turned and moved to put the rifle there.
    wb = arm.data.bones["WeaponMount"]
    want = frame @ wb.matrix_local.to_3x3().to_4x4()
    carried = _carried(arm, posed, "WeaponMount")
    # want = carried @ rest @ T(rest3^-1 off) @ R(rest3^-1 W rest3)  =>  solve W and off.
    rest = wb.matrix_local
    base = (carried @ rest).inverted() @ want
    loc, rot, _ = base.decompose()
    rest3 = rest.to_3x3()
    rots["WeaponMount"] = rest3 @ rot.to_matrix() @ rest3.inverted()
    locs["WeaponMount"] = rest3 @ loc
    for side in ("L", "R"):
        p = pose.get("_ik" + side, GRIP_L if side == "L" else GRIP_R)
        if p is not None:
            _solve_arm(arm, posed, rots, side, frame @ bm.g(*p), pose.get("_pole"+side, POLE[side]))
            # Flex the new digits around the grip. Released hands return to their
            # relaxed glove shape with the rest of the free-arm pose.
            sign = 1 if side == "R" else -1
            rots["Fingers"+side] = _godot_rot((0, 0, -43*sign))
            rots["Thumb"+side] = _godot_rot((-16, 0, 16*sign))
    return rots, locs


def pose_key(arm, frame, pose, offsets=None, prev=None):
    """Keys a pose: {joint: (x, y, z) Godot degrees}; joints left out go back to rest.
    offsets: {joint: (x, y, z) Godot metres} moves a bone (the hips, for bob and crouch)."""
    rots, locs = solve(arm, pose, offsets)
    for pb in arm.pose.bones:
        rest = pb.bone.matrix_local.to_3x3()
        q = (rest.inverted() @ rots[pb.name] @ rest).to_quaternion()
        if prev is not None:
            if pb.name in prev:
                q.make_compatible(prev[pb.name])
            prev[pb.name] = q.copy()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.location = rest.inverted() @ locs[pb.name]
        pb.keyframe_insert("location", frame=frame)


def action(arm, name, keys, loop=True):
    """keys: [(frame, pose, offsets)]. Makes an action, pushes it to its own NLA track (so the
    glTF exporter writes it as a separate clip) and leaves the armature at rest."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    prev = {}
    for frame, pose, offsets in keys:
        pose_key(arm, frame * 2, pose, offsets, prev)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(keys[0][0] * 2), act)
    strip.name = name
    track.mute = True
    arm.animation_data.action = None
    act.use_fake_user = True
    return act


def _merge(*dicts):
    """Adds joint angles together; for the "_" settings (rifle, hand targets) the last one wins."""
    out = {}
    for d in dicts:
        for k, v in d.items():
            if k.startswith("_"):
                out[k] = v
                continue
            a = out.get(k, (0, 0, 0))
            out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out


# The two-handed rifle hold: the chest turns a little right so the left hand reaches the
# handguard, the head turns back to look ahead. The arms are solved onto the rifle.
HOLD = {"Chest": (0, -18, 0), "Neck": (0, 8, 0), "Head": (0, 10, 0)}
# Shouldered and raised for aiming, bladed further, cheek down to the sight.
AIM = {"Chest": (0, -24, 0), "Neck": (0, 10, 0), "Head": (-8, 13, -6), "_poleR": (1, -.55, .25), "_w": AIM_W}
# Hands off the rifle: it stays on the chest at rest and the arms take their angles.
FREE = {"_w": None, "_ikL": None, "_ikR": None}


def _foot_path(t, side, distance, stance, lift, heel=14, toe=29, long_stride=False):
    # z increases behind the moving body. Roll about the heel and toe tread,
    # keeping the active point stationary in the ground frame.
    if t <= stance:
        u = t / stance
        z = distance * (t - stance/2)
        height = 0
        pitch = heel * (1 - smooth(0, .35 if long_stride else .22, u)) - toe * smooth(.55 if long_stride else .68, 1, u)
    else:
        u = (t - stance) / (1 - stance)
        z = distance * (t - stance/2 - smooth(0, 1, u))
        if long_stride:
            # Match ground velocity at release and contact, braking quickly in swing.
            carry = u*(1-u)**18 - (1-u)*u**18
            z = distance * (stance*(.5 - smooth(0, 1, u)) + (1-stance)*carry)
        height = lift * math.sin(math.pi*u)**1.4
        pitch = -toe + (toe + heel) * smooth(.08, .86, u)
    if long_stride:
        z += .065  # Toe roll permits a longer reach behind the hip.
    pivot = bm.g(0, -.105, .073 if pitch >= 0 else -.17)
    ankle = bm.g(side*.108, .105 + height, z) + pivot - _godot_rot((pitch, 0, 0)) @ pivot
    return ankle, pitch


def free_arms(swing, elbow, spread, counter=0, flex=0):
    pose = dict(FREE)
    for side, sign in (("L", -1), ("R", 1)):
        pose["Arm" + side] = (swing + sign*counter, 0, sign*spread)
        pose["Forearm" + side] = (elbow + sign*flex, 0, 0)
        pose["Fingers" + side] = (0, 0, -6*sign)
    return pose


def build_actions(arm):
    bpy.context.scene.render.fps = FPS * 2
    keys = []
    feet = {side: (bm.g(sign*.115,.105,sign*.045),0) for side,sign in (("L",-1),("R",1))}
    for i in range(33):
        t = i % 32 / 32 * TAU
        breath, shift = math.sin(2*t), math.sin(t)
        adjust = max(0, -math.cos(t))**4
        pose = _merge(HOLD, {
            "_feet": feet, "_w": ((.13, 1.27+.022*adjust, -.40+.012*adjust), (-10+5*adjust,0,2*adjust)),
            "Hips": (0, 2*shift, -2*shift), "Spine": (-2+1.7*breath, 0, 2.5*shift),
            "Chest": (1.3*breath, 3*shift, 0), "Head": (-breath, 13*math.sin(t-.45), -shift),
            "PackMount": (-1.1*math.sin(2*t-.5), -shift, 0)})
        keys.append((1+i*120/32, pose, {"Hips": (.033*shift, -.035+.007*breath, 0)}))
    action(arm, "idle", keys)
    free_keys = []
    for frame, pose, offsets in keys:
        phase = TAU*(frame-1)/120
        fidget = max(0, -math.cos(phase))**4
        arms = free_arms(-6, 15, 5, 2*math.sin(phase), 4*fidget)
        free_keys.append((frame, pose | arms, offsets))
    action(arm, "idle_free", free_keys)

    leg, shin, foot = (arm.data.bones[name+"L"] for name in ("Leg", "Shin", "Foot"))
    thigh = (shin.head_local - leg.head_local).length
    calf = (foot.head_local - shin.head_local).length
    reach = math.sqrt(thigh**2 + calf**2 + 2*thigh*calf*math.cos(math.radians(10)))
    pelvis = arm.data.bones["Hips"].head_local
    sockets = {side: arm.data.bones["Leg"+side].head_local - pelvis for side in ("L","R")}
    for name, distance, stance, lift, heel, toe in (
            ("walk", 2.72, 13/24, .16, 29, 54),
            ("run", 4.32, .25, .39, 18, 57),
            ("crouch_walk", 1.4, .58, .075, 14, 29)):
        keys = []
        for i in range(49):
            t = i % 48 / 48
            shift = math.sin(TAU*t)
            twist = math.cos(TAU*t)
            gait_feet = {side: _foot_path((t+offset)%1, sign, distance, stance, lift, heel, toe, name != "crouch_walk")
                    for side, sign, offset in (("L",-1,0),("R",1,.5))}
            if name == "crouch_walk":
                hip = (-2, -7*twist, 3*shift)
                lean, counter, head_pitch = -19, 5*twist, 15.2
                height = -.405 - .022*math.cos(2*TAU*t)
            else:
                running = name == "run"
                hip = (0, -(15 if running else 18)*twist, 2*shift)
                lean, counter = (-8 if running else -2), -hip[1]*.65
                head_pitch = -lean
                # Walk vaults over the support leg. Allow the pelvis to descend
                # into the long split at exchange, using the actual ankle reach.
                # Running compresses at loading and rises through toe-off.
                if running:
                    height = -.066 - .060*math.cos(2*TAU*(t-.08))
                else:
                    height = -.101 - .103*math.cos(2*TAU*(t-.01))
                for side, offset in (("L",0), ("R",.5)):
                    if (t + offset) % 1 > stance:
                        continue
                    socket = _godot_rot(hip) @ sockets[side]
                    ankle = gait_feet[side][0]
                    dx = ankle.x - (socket.x - .024*shift)
                    dy = ankle.y - socket.y
                    ceiling = ankle.z + math.sqrt(max(0, reach**2 - dx**2 - dy**2))
                    height = min(height, ceiling - (pelvis.z + socket.z))
            pose = _merge(HOLD, {
                "_feet": gait_feet, "Hips": hip, "Spine": (lean, counter, -2*shift),
                "Chest": (0, 6*twist, -shift), "Head": (head_pitch, -4*twist, 0),
                "PackMount": (2*math.sin(2*TAU*t-.5), -3*math.cos(TAU*t-.55), shift)})
            keys.append((i/2, pose, {"Hips": (-.024*shift, height, 0)}))
        # Keep the GLB duration, with its extra frame after the gameplay loop.
        keys.append((25, *keys[-1][1:]))
        action(arm, name, keys)
        if name in ("walk", "run"):
            free_keys = []
            for frame, pose, offsets in keys[:-1]:
                # Left heel strikes at phase zero; the right arm leads then.
                lead = math.cos(TAU*(frame/24 - (.11 if running else .02)))
                arms = free_arms(-23 if running else -8, 85 if running else 23,
                                 7 if running else 5, (40 if running else 25)*lead,
                                 (5 if running else 8)*lead)
                free_keys.append((frame, pose | arms, offsets))
            action(arm, name + "_free", free_keys)

    # Keep the soles down as the crouched torso breathes.
    crouch = {"_feet": feet,
              "Spine": (-20, 0, 0), "Chest": (-4, 0, 0), "Head": (18, 0, 0), "_w": ((0.13, 1.27, -0.40), (14, 0, 0))}
    action(arm, "crouch", [(1, _merge(HOLD, crouch), {"Hips": (0, -0.42, 0)}),
                           (31, _merge(HOLD, crouch, {"Spine": (-2, 0, 0)}), {"Hips": (0, -0.43, 0)}),
                           (61, _merge(HOLD, crouch), {"Hips": (0, -0.42, 0)})])
    low = _merge(HOLD, crouch) | free_arms(22, 20, 5)
    action(arm, "crouch_free", [(1, low, {"Hips": (0, -.42, 0)}),
                                (31, _merge(low, {"Spine": (-2,0,0)}), {"Hips": (0, -.43, 0)}),
                                (61, low, {"Hips": (0, -.42, 0)})])
    # Preserve the original two-frame jump take. The air blend carries the tuck
    # into flight while the one-shot landing takes the weight on fixed soles.
    brace = _merge(HOLD, {"_feet": feet, "Spine": (-8,0,0), "PackMount": (5,0,0)})
    action(arm, "jump", [(1, brace, {"Hips": (0,-.135,0)}),
                         (2, _merge(HOLD, {"LegL": (47,0,-3), "ShinL": (-75,0,0),
                                          "LegR": (19,0,4), "ShinR": (-46,0,0)}), {})], loop=False)
    action(arm, "land", [(0, brace, {"Hips": (0,-.035,0)}),
                         (3, _merge(brace, {"Spine": (-9,0,0)}), {"Hips": (0,-.23,.045)}),
                         (5, _merge(brace, {"PackMount": (-11,0,0)}), {"Hips": (0,-.205,.035)}),
                         (10.5, _merge(HOLD, {"_feet": feet}), {"Hips": (0,-.035,0)})], loop=False)
    fall_a = {"LegL": (22, 0, -6), "ShinL": (-40, 0, 0), "LegR": (8, 0, 6), "ShinR": (-26, 0, 0),
              "Spine": (-4, 0, 0), "Head": (6, 0, 0)}
    fall_b = {"LegL": (18, 0, -8), "ShinL": (-34, 0, 0), "LegR": (12, 0, 8), "ShinR": (-30, 0, 0),
              "Spine": (-6, 0, 0), "Head": (8, 0, 0)}
    balance = _merge(HOLD, {"_ikL": None, "ArmL": (18,0,-53), "ForearmL": (35,0,-9),
                            "_poleR": (.9,-.5,.2)})
    action(arm, "fall", [(1, _merge(balance, fall_a), {}), (13, _merge(balance, fall_b), {}), (25, _merge(balance, fall_a), {})])

    balance_a = _merge(HOLD, fall_a, free_arms(10, 24, 53, 5))
    balance_b = _merge(HOLD, fall_b, free_arms(14, 30, 60, -4))
    action(arm, "fall_free", [(1, balance_a, {}), (13, balance_b, {}), (25, balance_a, {})])

    # Aim: an upper-body hold, layered over the legs in the game.
    sight = _merge(AIM, {"_feet": {side: (bm.g(sign*.15, .105, sign*.12), 0)
                                   for side, sign in (("L",-1),("R",1))}})
    settled = {"Hips": (.015,-.055,0)}
    action(arm, "aim", [(1, sight, settled), (31, _merge(sight, {"Chest": (.8,0,0)}), settled),
                        (61, sight, settled)])

    # Reload (1.6 s): tilt the rifle, the left hand drops to the belt, pulls a cell, slaps it into
    # the magazine well, racks the bolt, back to the hold.
    tilt = {"_w": ((0.1, 1.22, -0.36), (-16, 18, 30)), "Chest": (0, 4, 0), "Head": (14, 10, 0)}
    belt = {"_ikL": (-.44, -.24, .24)}
    insert = {"_ikL": (0.0, -0.24, 0.06)}
    slap = {"_ikL": (0.0, -0.17, 0.05)}
    rack = {"_ikL": (0.07, 0.03, 0.12)}
    action(arm, "reload", [
        (1, HOLD, {}), (7, _merge(HOLD, tilt, slap), {}),
        (11, _merge(HOLD, tilt, insert), {}), (18, _merge(HOLD, tilt, belt), {}),
        (24, _merge(HOLD, tilt, belt, {"Spine": (3, 0, 0), "_ikL": (-.42, -.25, .20)}), {}),
        (31, _merge(HOLD, tilt, insert), {}), (35, _merge(HOLD, tilt, slap, {"Chest": (2, 0, 0)}), {}),
        (41, _merge(HOLD, tilt, rack, {"Chest": (0, 6, 0)}), {}), (44, _merge(HOLD, tilt, {"_ikL": (.04,.015,.22)}), {}), (49, HOLD, {}),
    ], loop=False)

    # Hurt flinch (0.4 s).
    action(arm, "hurt", [(1, HOLD, {}), (3, _merge(HOLD, {"Spine": (14, 11, 7), "Chest": (6, 0, 0), "Head": (-10, -10, 0)}), {}),
                         (6, _merge(HOLD, {"Chest": (-4,-3,-2), "PackMount": (7,3,0)}), {}),
                         (12, HOLD, {})], loop=False)

    # Dodge roll (0.5 s): tuck the rifle in, roll forward over the shoulder, come up.
    tuck = {"LegL": (100, 0, 0), "LegR": (100, 0, 0), "ShinL": (-130, 0, 0), "ShinR": (-130, 0, 0),
            "Spine": (-25, 0, 0), "Chest": (-18, 9, 0), "Head": (-9, 0, 0),
            "_w": ((0.08, 1.3, -0.3), (20, 0, 0))}
    action(arm, "roll", [
        (1, HOLD, {}),
        (4, _merge(tuck, {"Hips": (-60, 12, 21)}), {"Hips": (0, -0.4, 0)}),
        (8, _merge(tuck, {"Hips": (-180, 8, 25)}), {"Hips": (.06, -.36, 0)}),
        (12, _merge(tuck, {"Hips": (-300, -8, 16)}), {"Hips": (.03, -0.4, 0)}),
        (16, _merge(HOLD, crouch), {"Hips": (0,-.34,.035)}),
    ], loop=False)

    # Interact (0.8 s): the rifle drops to the right hand, the left reaches out and works a panel.
    lowered = {"_w": ((0.18, 1.12, -0.3), (-40, 10, 10)), "_ikL": None}
    reach = _merge(lowered, {"ArmL": (80, 0, 6), "ForearmL": (10, 0, 0), "Spine": (-10, 0, 0), "Chest": (-4, 10, 0), "Head": (-8, 0, 0)})
    action(arm, "interact", [(1, HOLD, {}), (4, _merge(lowered, {"ArmL": (28,0,-14), "ForearmL": (48,0,0)}), {}), (10, reach, {}),
                             (14, _merge(reach, {"ForearmL": (-18, 0, 0)}), {}), (24, HOLD, {})], loop=False)

    # Install (1.4 s): rifle away, kneel, both hands push the part home.
    kneel = _merge(FREE, {"LegL": (85, 0, 0), "ShinL": (-90, 0, 0), "LegR": (-10, 0, 0), "ShinR": (-100, 0, 0),
                          "Spine": (-16, 0, 0), "Head": (-10, 0, 0), "ArmL": (75, 0, 10), "ArmR": (75, 0, -10), "ForearmL": (20, 0, 0), "ForearmR": (20, 0, 0)})
    action(arm, "install", [(1, HOLD, {}), (5, _merge(HOLD, {"Spine": (-6,0,0), "LegL": (24,0,0), "ShinL": (-42,0,0)}), {"Hips": (0,-.08,0)}),
                            (12, kneel, {"Hips": (0, -0.38, 0)}),
                            (20, _merge(kneel, {"Spine": (-8, 0, 0), "ForearmL": (-20, 0, 0), "ForearmR": (-20, 0, 0)}), {"Hips": (0, -0.38, 0)}),
                            (30, kneel, {"Hips": (0, -0.38, 0)}), (42, HOLD, {})], loop=False)

    # Stim (0.9 s): the left hand slaps the injector into the thigh.
    grasp = {"FingersL": (0,0,55), "ThumbL": (-18,0,-17)}
    stab = _merge(lowered, grasp, {"ArmL": (16, 0, -4), "ForearmL": (8, 0, 0), "Spine": (-10, 0, 0), "Head": (-16, 0, 0)})
    action(arm, "stim", [(1, HOLD, {}), (5, _merge(stab, {"ForearmL": (32,0,0), "ArmL": (-9,0,-9)}), {}), (10, stab, {}), (13, _merge(stab, {"Spine": (-4, 0, 0), "ArmL": (-6, 0, 0)}), {}),
                         (27, HOLD, {})], loop=False)

    # Throw (0.75 s): the left arm winds back over the shoulder and whips forward.
    action(arm, "throw", [(1, HOLD, {}), (7, _merge(lowered, grasp, {"ArmL": (-40, 0, -60), "ForearmL": (-90, 0, 0), "Chest": (-6, 24, 0)}), {}),
                          (12, _merge(lowered, {"ArmL": (110, 0, -10), "ForearmL": (0, 0, 0), "Chest": (6, -20, 0)}), {}),
                          (16, _merge(lowered, {"ArmL": (80,-22,-9), "ForearmL": (13,0,0), "Chest": (-5,-14,0)}), {}),
                          (23, HOLD, {})], loop=False)

    # Down (1.4 s): knees buckle, she folds and topples onto her side. The game hides the rifle.
    action(arm, "die", [
        (1, HOLD, {}),
        (9, _merge(FREE, {"LegL": (60, 0, 0), "LegR": (50, 0, 0), "ShinL": (-100, 0, 0), "ShinR": (-90, 0, 0),
                          "Spine": (20, 0, 0), "Head": (20, 0, 0), "ArmL": (20, 0, -20), "ArmR": (20, 0, 20)}), {"Hips": (0, -0.45, 0)}),
        (17, _merge(FREE, {"Hips": (0, 0, 66), "Spine": (-12,0,7), "ArmL": (28,0,-24),
                           "LegL": (53,0,0), "ShinL": (-91,0,0), "LegR": (72,0,0), "ShinR": (-95,0,0)}), {"Hips": (-.11,-.62,0)}),
        (23, _merge(FREE, {"Hips": (0, 0, 91), "LegL": (40, 0, 0), "LegR": (60, 0, 0), "ShinL": (-60, 0, 0), "ShinR": (-80, 0, 0),
                           "Spine": (14, 0, 0), "Head": (10, 0, -20), "ArmL": (62, 0, 9), "ArmR": (47, 0, -8), "ForearmR": (28,0,-12)}), {"Hips": (-.17, -.70, 0)}),
        (42, _merge(FREE, {"Hips": (0, 0, 88), "LegL": (36, 0, 0), "LegR": (62, 0, 0), "ShinL": (-56, 0, 0), "ShinR": (-84, 0, 0),
                           "Spine": (12, 0, 0), "Head": (6, 0, -26), "ArmL": (64, 0, 5), "ForearmL": (34,0,0),
                           "ArmR": (68, 0, -38), "ForearmR": (18,0,-8)}), {"Hips": (-.19, -.68, 0)}),
    ], loop=False)


def export(arm):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "juno_rigged.glb")
    bpy.ops.object.select_all(action="SELECT")
    # glTF carries paint in COLOR_0 and the atlas as baseColorTexture. The
    # Blender preview also decodes the baked colours to linear for shading.
    preview = []
    for name in ("Enamel","Textile"):
        tree = bpy.data.materials[name].node_tree
        base = tree.nodes["Principled BSDF"].inputs["Base Color"]
        preview.append((tree,base,base.links[0].from_socket))
        tree.links.new(tree.nodes.get("Image Texture").outputs[0],base)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_range=False,
                              export_def_bones=False, export_optimize_animation_size=False,
                              export_vertex_color="ACTIVE")
    for tree,base,source in preview:
        tree.links.new(source,base)
    print("exported", os.path.relpath(path, ROOT))
    blend = os.path.join(ROOT, "blender", "juno_rigged.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    print("saved", os.path.relpath(blend, ROOT))


def main():
    suit = build_model()
    build_actions(suit.arm)
    for pb in suit.arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.preferences.filepaths.save_version = 0
    export(suit.arm)


if __name__ == "__main__":
    main()
