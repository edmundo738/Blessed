"""Author the first editable Blessed asset kit in Blender and export Godot GLBs.

Run from the project root with Blender 5.2 in background mode.  The .blend is
the source of truth; each GLB is a small runtime asset with its pivot at ground
level (world props) or at the grip (hand tools).
"""

from __future__ import annotations

import math
import os
import random

import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_ROOT = os.path.join(ROOT, "content", "models")
OUT = os.path.join(MODEL_ROOT, "runtime")
SOURCE_OUT = os.path.join(MODEL_ROOT, "source")
os.makedirs(OUT, exist_ok=True)
os.makedirs(SOURCE_OUT, exist_ok=True)
RNG = random.Random(738291)
MATS = {}
ASSETS = {}


def mat(name, color, rough=0.8, metal=0.0):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    MATS[name] = value
    return value


def materials():
    for args in [
        ("Blessed | bark umber", (0.27, 0.15, 0.10), .86, 0),
        ("Blessed | bark warm edge", (0.48, 0.29, 0.16), .82, 0),
        ("Blessed | bark shadow", (0.16, 0.10, 0.08), .9, 0),
        ("Blessed | birch chalk", (0.79, 0.79, 0.69), .88, 0),
        ("Blessed | leaf deep", (0.13, 0.34, 0.22), .8, 0),
        ("Blessed | leaf mid", (0.25, 0.56, 0.28), .78, 0),
        ("Blessed | leaf sun", (0.52, 0.70, 0.30), .74, 0),
        ("Blessed | pine", (0.10, 0.31, 0.24), .8, 0),
        ("Blessed | pine light", (0.24, 0.48, 0.31), .78, 0),
        ("Blessed | pine shadow", (0.07, 0.22, 0.20), .84, 0),
        ("Blessed | petal shadow", (0.72, 0.24, 0.43), .76, 0),
        ("Blessed | petal", (0.92, 0.49, 0.64), .72, 0),
        ("Blessed | petal light", (1.0, 0.78, 0.78), .68, 0),
        ("Blessed | flower gold", (1.0, 0.68, 0.16), .54, 0),
        ("Blessed | flower cream", (1.0, 0.90, 0.61), .7, 0),
        ("Blessed | fern", (0.19, 0.46, 0.27), .8, 0),
        ("Blessed | fern light", (0.39, 0.64, 0.31), .76, 0),
        ("Blessed | reed", (0.36, 0.48, 0.26), .84, 0),
        ("Blessed | cattail", (0.36, 0.19, 0.11), .88, 0),
        ("Blessed | stone shadow", (0.23, 0.30, 0.34), .91, 0),
        ("Blessed | stone face", (0.39, 0.46, 0.48), .88, 0),
        ("Blessed | stone light", (0.58, 0.59, 0.53), .84, 0),
        ("Blessed | moss", (0.25, 0.43, 0.25), .9, 0),
        ("Blessed | sea glass", (0.10, 0.46, 0.44), .38, .08),
        ("Blessed | kelp", (0.19, 0.44, 0.27), .52, 0),
        ("Blessed | kelp tip", (0.44, 0.66, 0.33), .5, 0),
        ("Blessed | log heart", (0.75, 0.52, 0.29), .82, 0),
        ("Blessed | berry", (0.66, 0.08, 0.18), .34, 0),
        ("Blessed | leather", (0.17, 0.09, 0.06), .88, 0),
        ("Blessed | leather stitch", (0.72, 0.50, 0.26), .78, 0),
        ("Blessed | forged iron", (0.20, 0.29, 0.34), .39, .62),
        ("Blessed | honed steel", (0.70, 0.82, 0.82), .28, .72),
        ("Blessed | brass", (0.72, 0.43, 0.16), .38, .68),
        ("Blessed | plank", (0.46, 0.28, 0.14), .78, 0),
    ]:
        mat(*args)


def new_asset(name):
    collection = bpy.data.collections.new("Blessed / " + name)
    bpy.context.scene.collection.children.link(collection)
    ASSETS[name] = collection
    return collection


def relink(obj, collection):
    for old in tuple(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def finish(obj, collection, material, smooth=False):
    obj.data.materials.append(material)
    for face in getattr(obj.data, "polygons", ()):
        face.use_smooth = smooth
    return relink(obj, collection)


def ico(name, collection, pos, scale, material, subdivisions=2, jitter=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    if jitter:
        for vert in obj.data.vertices:
            factor = RNG.uniform(1.0 - jitter, 1.0 + jitter)
            vert.co *= factor
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, collection, material, smooth=False)


def cone(name, collection, pos, radius_bottom, radius_top, depth, material, vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius_bottom,
                                    radius2=radius_top, depth=depth, location=pos)
    obj = bpy.context.object
    obj.name = name
    bevel = obj.modifiers.new("Soft caught light", "BEVEL")
    bevel.width = min(radius_bottom, depth) * .055
    bevel.segments = 2
    obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return finish(obj, collection, material)


def cylinder_between(name, collection, a, b, radius_a, radius_b, material, vertices=10):
    delta = Vector(b) - Vector(a)
    center = (Vector(a) + Vector(b)) * .5
    obj = cone(name, collection, center, radius_a, radius_b, delta.length,
               material, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return obj


def curved_blade(name, collection, base, angle, height, width, lean, material):
    # Tapered, gently cupped ribbon; the center ridge catches a separate light.
    direction = Vector((math.cos(angle), math.sin(angle), 0))
    side = Vector((-direction.y, direction.x, 0))
    base = Vector(base)
    levels = 5
    verts = []
    for i in range(levels):
        t = i / (levels - 1)
        center = base + direction * (lean * t * t) + Vector((0, 0, height * t))
        half = width * .5 * (1 - .72 * t)
        ridge = direction * (width * .12 * math.sin(t * math.pi))
        verts.extend((center - side * half, center + ridge, center + side * half))
    faces = []
    for i in range(levels - 1):
        start = i * 3
        nxt = start + 3
        faces.extend(((start, start + 1, nxt + 1, nxt),
                      (start + 1, start + 2, nxt + 2, nxt + 1)))
    mesh = bpy.data.meshes.new(name + " | hand-shaped ribbon")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.materials.append(MATS["Blessed | leaf sun"])
    for i, face in enumerate(mesh.polygons):
        face.material_index = 1 if i % 2 else 0
        face.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    solid = obj.modifiers.new("Soft leaf edge", "SOLIDIFY")
    solid.thickness = .012
    return obj


def canopy(collection, center, sizes, palette, seed, blossom=False):
    r = random.Random(seed)
    leaves = []
    for index, (pos, scale) in enumerate(sizes):
        m = MATS[palette[index % len(palette)]]
        leaf = ico("Canopy mass %02d" % index, collection, pos, scale, m, 2, .13)
        leaves.append(leaf)
    # Small sculpted leaf sprays break the round silhouette without turning the
    # canopy into a cloud of disconnected low-poly spheres.
    detail_materials = (["Blessed | petal", "Blessed | petal light",
                         "Blessed | petal shadow"] if blossom else
                        ["Blessed | leaf mid", "Blessed | leaf sun",
                         "Blessed | leaf deep"])
    for index in range(24):
        angle = math.tau * index / 24 + r.uniform(-.15, .15)
        lobe_pos, lobe_scale = sizes[index % len(sizes)]
        face_angle = angle + r.uniform(-.45, .45)
        base = Vector(lobe_pos) + Vector((
            math.cos(face_angle) * lobe_scale[0] * r.uniform(.62, .88),
            math.sin(face_angle) * lobe_scale[1] * r.uniform(.62, .88),
            r.uniform(-.10, .22) * lobe_scale[2],
        ))
        curved_blade("Canopy leaf spray %02d" % index, collection, base,
                     face_angle, r.uniform(.26, .46), r.uniform(.16, .24),
                     r.uniform(.10, .24), MATS[detail_materials[index % len(detail_materials)]])
    if blossom:
        # Readable sakura blossoms: small warm centers and five separate petals.
        for index in range(12):
            lobe_pos, lobe_scale = sizes[(index * 3) % len(sizes)]
            angle = math.tau * index / 12 + r.uniform(-.18, .18)
            center_pos = Vector(lobe_pos) + Vector((
                math.cos(angle) * lobe_scale[0] * .72,
                math.sin(angle) * lobe_scale[1] * .72,
                r.uniform(-.1, .22) * lobe_scale[2],
            ))
            for petal in range(5):
                pa = math.tau * petal / 5
                pos = center_pos + Vector((math.cos(pa) * .085, math.sin(pa) * .085, .025))
                item = ico("Sakura petal", collection, pos, (.085, .055, .035),
                           MATS["Blessed | petal light"] if petal % 2 else MATS["Blessed | petal"], 1)
                item.rotation_euler[2] = pa
            ico("Sakura golden heart", collection, center_pos + Vector((0, 0, .06)),
                (.045, .045, .035), MATS["Blessed | flower gold"], 1)
    return leaves


def broad_tree(name, height, palette, crown_radius, blossom=False):
    c = new_asset(name)
    bark = MATS["Blessed | bark umber"]
    trunk_top = height * .77
    cone("Flared sculpted trunk", c, (0, 0, trunk_top * .51), .36, .12,
         trunk_top, bark, 13)
    # Surface roots make contact with the ground read clearly at player scale.
    for i in range(6):
        a = math.tau * i / 6 + .2
        cylinder_between("Root buttress %02d" % i, c,
            (math.cos(a) * .76, math.sin(a) * .76, .07),
            (math.cos(a) * .13, math.sin(a) * .13, height * .31),
            .045, .145, MATS["Blessed | bark warm edge"], 8)
    for i in range(8):
        a = math.tau * i / 8 + .24
        start_z = height * RNG.uniform(.52, .70)
        start = (0, 0, start_z)
        end = (math.cos(a) * crown_radius * RNG.uniform(.67, .91),
               math.sin(a) * crown_radius * RNG.uniform(.67, .91),
               height * RNG.uniform(.72, .83))
        cylinder_between("Crown limb %02d" % i, c, start, end, .13, .055,
                         MATS["Blessed | bark warm edge"], 9)
    center = (0, 0, height * .82)
    lobes = []
    for i in range(9):
        a = math.tau * i / 8
        ring = crown_radius * (.48 if i else 0)
        pos = (math.cos(a) * ring, math.sin(a) * ring,
               height * RNG.uniform(.75, .87))
        scale = (crown_radius * RNG.uniform(.45, .58),
                 crown_radius * RNG.uniform(.42, .55), crown_radius * RNG.uniform(.34, .46))
        lobes.append((pos, scale))
    center_scale = (crown_radius * .63, crown_radius * .58, crown_radius * .49)
    lobes.insert(0, (center, center_scale))
    canopy(c, center, lobes, palette, len(name) * 13, blossom)
    return c


def pine_tree():
    name, height = "tree_pine", 8.4
    c = new_asset(name)
    cone("Tall tapered pine trunk", c, (0, 0, height * .45), .29, .035, height * .90,
         MATS["Blessed | bark umber"], 12)
    # Layered, irregular skirt tiers keep the spruce silhouette clear at play
    # distance. Short exposed boughs and alternating greens break the stacked
    # shapes so the tree reads as designed foliage rather than plain cones.
    tier_count = 7
    for tier in range(tier_count):
        t = tier / float(tier_count)
        base_z = .62 + tier * 1.02
        radius = (2.02 * (1.0 - t) ** .78 + .20) * RNG.uniform(.96, 1.04)
        depth = 1.62 * (1.0 - .36 * t)
        cone("Sculpted pine foliage tier %02d" % tier, c,
             (0, 0, base_z + depth * .5), radius, radius * .10, depth,
             MATS[["Blessed | pine shadow", "Blessed | pine", "Blessed | pine light"][tier % 3]],
             10 if tier < 5 else 8)
        for arm in range(5):
            angle = math.tau * arm / 5 + tier * .46 + RNG.uniform(-.09, .09)
            start = (math.cos(angle) * radius * .16,
                     math.sin(angle) * radius * .16, base_z + depth * .20)
            end = (math.cos(angle) * radius * 1.02,
                   math.sin(angle) * radius * 1.02, base_z + depth * .45)
            cylinder_between("Pine skirt branch", c, start, end,
                             .075 * (1.0 - .35 * t), .025,
                             MATS["Blessed | pine shadow"], 7)
    cone("Pine crown", c, (0, 0, 7.84), .28, 0, .88,
         MATS["Blessed | pine light"], 9)
    return c


def birch_tree():
    name, height = "tree_birch", 7.3
    c = new_asset(name)
    cone("Pale birch trunk", c, (0, 0, height * .47), .20, .055, height * .94,
         MATS["Blessed | birch chalk"], 11)
    for i in range(12):
        z = RNG.uniform(.55, 6.3)
        a = RNG.uniform(0, math.tau)
        patch = ico("Natural birch bark mark", c,
                    (math.cos(a) * .186, math.sin(a) * .186, z),
                    (.025, .035, RNG.uniform(.06, .14)), MATS["Blessed | stone shadow"], 1)
    for i in range(5):
        a = i * math.tau / 5
        z = 4.55 + i * .28
        cylinder_between("Birch branch", c, (0, 0, z - .38),
                         (math.cos(a) * 1.15, math.sin(a) * 1.15, z + .48),
                         .065, .025, MATS["Blessed | bark warm edge"], 8)
    sizes = []
    for i in range(8):
        a = i * math.tau / 8
        sizes.append(((math.cos(a) * .78, math.sin(a) * .78, 6.25 + RNG.uniform(-.35, .38)),
                      (.82, .71, .72)))
    sizes.insert(0, ((0, 0, 6.45), (.94, .78, .78)))
    canopy(c, (0, 0, 6.25), sizes,
           ["Blessed | leaf sun", "Blessed | leaf mid", "Blessed | leaf deep"], 42)
    return c


def willow_tree():
    c = new_asset("tree_willow")
    height = 7.4
    cone("Graceful willow trunk", c, (0, 0, height * .45), .30, .095, height * .90,
         MATS["Blessed | bark umber"], 12)
    for i in range(7):
        angle = math.tau * i / 7 + .16
        start = (0, 0, 4.55 + RNG.uniform(-.25, .45))
        end = (math.cos(angle) * 1.62, math.sin(angle) * 1.62, 6.65 + RNG.uniform(-.22, .24))
        cylinder_between("Willow arching limb", c, start, end, .12, .045,
                         MATS["Blessed | bark warm edge"], 8)
    canopy(c, (0, 0, 6.5), [
        ((0, 0, 6.58), (1.55, 1.42, .72)),
        ((.75, 0, 6.45), (1.0, .88, .66)),
        ((-.74, .15, 6.43), (.98, .88, .64)),
        ((0, .72, 6.48), (.96, .92, .62)),
        ((0, -.70, 6.44), (.96, .90, .62)),
    ], ["Blessed | leaf deep", "Blessed | leaf mid", "Blessed | leaf sun"], 790)
    # Long leaf curtains make this species distinct and create a calm wind read.
    for i in range(24):
        a = math.tau * i / 24
        radius = RNG.uniform(1.25, 2.1)
        base = (math.cos(a) * radius, math.sin(a) * radius, RNG.uniform(6.0, 6.72))
        curved_blade("Willow hanging leaf ribbon", c, base, a,
                     -RNG.uniform(.72, 1.65), RNG.uniform(.11, .18),
                     RNG.uniform(.06, .22),
                     MATS["Blessed | leaf sun"] if i % 4 == 0 else MATS["Blessed | leaf mid"])
    return c


def rock_cluster():
    c = new_asset("rock_cluster")
    ico("Main weathered stone", c, (0, 0, .43), (.79, .54, .56),
        MATS["Blessed | stone face"], 2, .19)
    ico("Broken shoulder", c, (-.48, -.06, .30), (.47, .38, .39),
        MATS["Blessed | stone shadow"], 2, .16)
    ico("Pale fracture plane", c, (.36, .18, .56), (.47, .40, .39),
        MATS["Blessed | stone light"], 1, .10)
    ico("Moss seam", c, (-.05, .02, .86), (.45, .27, .12),
        MATS["Blessed | moss"], 1, .2)
    return c


def grass_clump():
    c = new_asset("grass_clump")
    for i in range(20):
        a = math.tau * i / 20 + RNG.uniform(-.22, .22)
        h = RNG.uniform(.42, .86)
        base = (RNG.uniform(-.18, .18), RNG.uniform(-.18, .18), .02)
        curved_blade("Layered grass blade %02d" % i, c, base, a, h,
                     RNG.uniform(.09, .17), RNG.uniform(.10, .34),
                     MATS[["Blessed | leaf deep", "Blessed | leaf mid",
                           "Blessed | fern light"][i % 3]])
    # A few seed heads give meadow grass a readable fine silhouette.
    for i in range(3):
        a = math.tau * i / 3 + .4
        end = (math.cos(a) * .18, math.sin(a) * .18, RNG.uniform(.64, .82))
        cylinder_between("Grass seed stem", c, (0, 0, .05), end, .014, .008,
                         MATS["Blessed | leaf deep"], 5)
        for grain in range(3):
            p = Vector(end) + Vector((0, 0, -.07 * grain))
            ico("Grass seed", c, p, (.045, .035, .045),
                MATS["Blessed | flower cream"], 1)
    return c


def fern_clump():
    c = new_asset("fern_clump")
    for frond in range(7):
        angle = math.tau * frond / 7 + RNG.uniform(-.18, .18)
        base = Vector((RNG.uniform(-.08, .08), RNG.uniform(-.08, .08), .03))
        height = RNG.uniform(.70, 1.05)
        length = RNG.uniform(.58, .88)
        curved_blade("Fern central rib", c, base, angle, height, .07, length,
                     MATS["Blessed | fern"])
        for side in (-1, 1):
            for leaflet in range(1, 7):
                t = leaflet / 8.0
                origin = base + Vector((math.cos(angle) * length * t,
                    math.sin(angle) * length * t, height * t))
                leaf_angle = angle + side * RNG.uniform(.68, 1.0)
                curved_blade("Fern paired leaflet", c, origin, leaf_angle,
                    RNG.uniform(.12, .22), RNG.uniform(.07, .11),
                    RNG.uniform(.10, .18),
                    MATS["Blessed | fern light"] if leaflet % 3 == 0 else MATS["Blessed | fern"])
    return c


def flower_clump():
    c = new_asset("flower_clump")
    flower_mats = ["Blessed | petal", "Blessed | flower gold",
                   "Blessed | flower cream", "Blessed | petal light"]
    for i in range(5):
        angle = math.tau * i / 5 + RNG.uniform(-.2, .2)
        spread = RNG.uniform(.08, .28)
        stem_h = RNG.uniform(.42, .72)
        base = Vector((math.cos(angle) * spread, math.sin(angle) * spread, .02))
        top = base + Vector((math.cos(angle) * .08, math.sin(angle) * .08, stem_h))
        cylinder_between("Wildflower stem", c, base, top, .022, .014,
                         MATS["Blessed | fern"], 6)
        for leaf_side in (-1, 1):
            curved_blade("Wildflower stem leaf", c, base + Vector((0, 0, stem_h * .28)),
                angle + leaf_side * .9, .20, .09, .12, MATS["Blessed | leaf mid"])
        for petal in range(5):
            pa = math.tau * petal / 5
            petal_pos = top + Vector((math.cos(pa) * .085, math.sin(pa) * .085, 0))
            flower = ico("Five-petal wildflower", c, petal_pos, (.078, .048, .032),
                         MATS[flower_mats[(i + petal) % len(flower_mats)]], 1)
            flower.rotation_euler[2] = pa
        ico("Wildflower pollen heart", c, top + Vector((0, 0, .035)),
            (.045, .045, .032), MATS["Blessed | flower gold"], 1)
    return c


def reed_clump():
    c = new_asset("reed_clump")
    for i in range(9):
        angle = math.tau * i / 9 + RNG.uniform(-.24, .24)
        radius = RNG.uniform(.10, .42)
        height = RNG.uniform(.72, 1.35)
        base = (math.cos(angle) * radius, math.sin(angle) * radius, .02)
        top = (math.cos(angle) * (radius + .10), math.sin(angle) * (radius + .10), height)
        cylinder_between("Marsh reed", c, base, top, .035, .022,
                         MATS["Blessed | reed"], 6)
        if i % 2 == 0:
            cone("Cattail seed head", c,
                 (top[0], top[1], height + .12), .065, .055, .28,
                 MATS["Blessed | cattail"], 8)
        for side in (-1, 1):
            curved_blade("Reed blade", c, (base[0], base[1], .16),
                angle + side * .72, height * .56, .085, .25,
                MATS["Blessed | leaf mid"])
    return c


def seaweed():
    c = new_asset("seaweed_cluster")
    ico("Anchoring reef stone", c, (0, 0, .13), (.42, .3, .18),
        MATS["Blessed | stone shadow"], 1, .12)
    for stalk in range(5):
        a = math.tau * stalk / 5
        base = Vector((math.cos(a) * .16, math.sin(a) * .16, .22))
        height = RNG.uniform(.72, 1.24)
        curved_blade("Kelp ribbon %02d" % stalk, c, base, a, height,
                     RNG.uniform(.14, .22), RNG.uniform(.35, .60),
                     MATS["Blessed | kelp tip"] if stalk % 2 else MATS["Blessed | kelp"])
        cylinder_between("Kelp midrib %02d" % stalk, c, base,
                         base + Vector((math.cos(a) * .25, math.sin(a) * .25, height * .82)),
                         .035, .012, MATS["Blessed | sea glass"], 6)
    return c


def bush_plant(with_berries=False):
    c = new_asset("plant_berry_bush" if with_berries else "plant_bush")
    center = (0, 0, .66)
    lobes = []
    for i in range(9):
        angle = math.tau * i / 8
        radius = RNG.uniform(.27, .58)
        pos = (math.cos(angle) * radius, math.sin(angle) * radius,
               RNG.uniform(.34, .78))
        scale = (RNG.uniform(.35, .55), RNG.uniform(.32, .49),
                 RNG.uniform(.28, .42))
        lobes.append((pos, scale))
    lobes.insert(0, (center, (.56, .52, .43)))
    for i, (pos, scale) in enumerate(lobes):
        ico("Bush leaf mass", c, pos, scale,
            MATS[["Blessed | leaf deep", "Blessed | leaf mid",
                  "Blessed | leaf sun"][i % 3]], 2, .15)
    for i in range(18):
        angle = math.tau * i / 18
        curved_blade("Bush outer leaf", c,
            (math.cos(angle) * RNG.uniform(.42, .70),
             math.sin(angle) * RNG.uniform(.42, .70),
             RNG.uniform(.30, .88)), angle, RNG.uniform(.20, .36),
            RNG.uniform(.10, .16), RNG.uniform(.08, .18),
            MATS["Blessed | leaf sun"] if i % 4 == 0 else MATS["Blessed | leaf mid"])
    if with_berries:
        for i in range(11):
            angle = math.tau * i / 11 + .23
            pos = (math.cos(angle) * RNG.uniform(.48, .68),
                   math.sin(angle) * RNG.uniform(.42, .63),
                   RNG.uniform(.43, .96))
            berry_color = MATS["Blessed | berry"] if i % 4 else MATS["Blessed | flower gold"]
            ico("Visible ripe berry", c, pos, (.105, .105, .105), berry_color, 2)
            curved_blade("Berry calyx", c, pos, angle, .12, .08, .03,
                         MATS["Blessed | leaf deep"])
    return c


def mushroom_cluster():
    c = new_asset("plant_mushroom")
    for i in range(5):
        angle = math.tau * i / 5 + RNG.uniform(-.2, .2)
        radius = RNG.uniform(.02, .34)
        h = RNG.uniform(.18, .38)
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        cylinder_between("Mushroom ivory stem", c, (x, y, .02), (x, y, h),
                         .045, .035, MATS["Blessed | flower cream"], 8)
        ico("Mushroom cap", c, (x, y, h + .055),
            (RNG.uniform(.13, .20), RNG.uniform(.13, .19), .09),
            MATS["Blessed | petal shadow"] if i % 2 else MATS["Blessed | berry"], 2, .08)
        for spot in range(3):
            a = math.tau * spot / 3
            ico("Mushroom cap fleck", c,
                (x + math.cos(a) * .07, y + math.sin(a) * .07, h + .115),
                (.025, .025, .014), MATS["Blessed | flower cream"], 1)
    return c


def log_pickup():
    c = new_asset("pickup_log")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=.15, depth=.88, location=(0, 0, .16))
    log = bpy.context.object
    log.name = "Split log | bark"
    log.rotation_euler[1] = math.pi * .5
    finish(log, c, MATS["Blessed | bark warm edge"])
    for x in (-.285, .165):
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=.145, depth=.018,
                                            location=(x, 0, .16), rotation=(0, math.pi * .5, 0))
        finish(bpy.context.object, c, MATS["Blessed | log heart"])
    for angle in (0.0, 2.1, 4.2):
        cylinder_between("Bark groove", c, (-.32, math.cos(angle) * .12, .16 + math.sin(angle) * .12),
                         (.32, math.cos(angle) * .12, .16 + math.sin(angle) * .12),
                         .012, .009, MATS["Blessed | bark umber"], 5)
    return c


def leaf_pickup():
    c = new_asset("pickup_leaf")
    for i in range(5):
        curved_blade("Loose gathered leaf %02d" % i, c,
                     (RNG.uniform(-.1, .1), RNG.uniform(-.1, .1), .05 + i * .01),
                     i * math.tau / 5, RNG.uniform(.28, .42), .20,
                     RNG.uniform(.08, .15), MATS["Blessed | leaf mid"] if i % 2 else MATS["Blessed | leaf sun"])
    return c


def berry_pickup():
    c = new_asset("pickup_berry")
    for i in range(5):
        angle = math.tau * i / 5
        ico("Blessed red berry", c, (math.cos(angle) * .14, math.sin(angle) * .14,
            .16 + RNG.uniform(-.03, .11)), (.13, .13, .12), MATS["Blessed | berry"], 2)
    curved_blade("Berry calyx", c, (0, 0, .22), .5, .24, .20, 0,
                 MATS["Blessed | leaf deep"])
    return c


def box(name, collection, location, dimensions, material, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel_mod = obj.modifiers.new("Hand softened timber", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 2
    obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return finish(obj, collection, material)


def extruded(name, collection, outline, depth, material, bevel=.012):
    count = len(outline)
    verts = [(x, y, z) for y in (-depth * .5, depth * .5) for x, z in outline]
    faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, j + count, i + count))
    mesh = bpy.data.meshes.new(name + " | forged silhouette")
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    finish(obj, collection, material)
    if bevel:
        mod = obj.modifiers.new("Forged edge bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("Weighted blade normals", "WEIGHTED_NORMAL")
    return obj


def tool_axe():
    c = new_asset("tool_axe")
    cylinder_between("Ash handle", c, (0, 0, .04), (-.08, 0, .86), .045, .035,
                     MATS["Blessed | bark warm edge"], 12)
    for i in range(5):
        z = .08 + i * .065
        cylinder_between("Leather grip wrap %02d" % i, c,
                         (-.01 - .015 * (z / .4), 0, z), (-.03 - .015 * (z / .4), 0, z + .028),
                         .052, .052, MATS["Blessed | leather"], 12)
    for z in (.13, .39, .70):
        cylinder_between("Grip brass pin", c, (-.09, -.044, z), (-.09, .044, z),
                         .014, .014, MATS["Blessed | brass"], 8)
    outline = [(-.12, .68), (.02, .70), (.20, .78), (.39, .73), (.45, .60),
               (.41, .45), (.28, .36), (.09, .43), (-.12, .48)]
    extruded("Broad leaf-shaped axe head", c, outline, .115, MATS["Blessed | forged iron"], .022)
    edge = [(.34, .43), (.41, .45), (.45, .60), (.41, .73), (.36, .70), (.38, .59)]
    extruded("Honed bright cutting bevel", c, edge, .12, MATS["Blessed | honed steel"], .008)
    ico("Forged poll cap", c, (-.105, 0, .57), (.10, .105, .09),
        MATS["Blessed | forged iron"], 1)
    return c


def tool_pickaxe():
    c = new_asset("tool_pickaxe")
    cylinder_between("Ash handle", c, (0, 0, .04), (-.05, 0, .91), .042, .033,
                     MATS["Blessed | bark warm edge"], 12)
    for i in range(5):
        z = .09 + i * .066
        cylinder_between("Leather grip wrap %02d" % i, c, (-.01, 0, z), (-.012, 0, z + .026),
                         .048, .048, MATS["Blessed | leather"], 12)
    outline = [(-.51, .73), (-.46, .86), (-.28, .85), (-.12, .77), (0, .72),
               (.14, .76), (.34, .88), (.52, .89), (.49, .75), (.35, .66),
               (.16, .62), (-.04, .62), (-.26, .65), (-.42, .66)]
    extruded("Curved cross pick head", c, outline, .105, MATS["Blessed | forged iron"], .025)
    for x, z in ((-.48, .80), (.49, .82)):
        ico("Polished pick tip", c, (x, 0, z), (.09, .09, .095),
            MATS["Blessed | honed steel"], 1)
    cylinder_between("Brass haft ferrule", c, (-.05, 0, .61), (-.05, 0, .71), .055, .05,
                     MATS["Blessed | brass"], 10)
    return c


def export_asset(name, collection):
    bpy.ops.object.select_all(action="DESELECT")
    objects = [o for o in collection.objects if o.type == "MESH"]
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
        # Join geometry/material slots for a single draw surface in Godot, then
        # place the node origin at ground level (or at the hand grip for tools).
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        # Bake each Blender palette material into a corner-color attribute.
        # Godot's shared foliage shader can then add toon bands and wind without
        # losing the hand-authored colors from the editable Blender source.
        if name.startswith(("tree_", "grass_", "fern_", "flower_", "reed_", "seaweed_",
                            "plant_")):
            colors = joined.data.color_attributes
            color_attr = colors.new(name="BlessedColor", type="BYTE_COLOR", domain="CORNER")
            colors.active_color = color_attr
            for polygon in joined.data.polygons:
                slot = polygon.material_index
                if slot < len(joined.data.materials) and joined.data.materials[slot]:
                    color = joined.data.materials[slot].diffuse_color
                else:
                    color = (1.0, 1.0, 1.0, 1.0)
                for loop_index in polygon.loop_indices:
                    color_attr.data[loop_index].color = color

        def save_selected(obj, filepath, ratio=1.0):
            work = obj.copy()
            work.data = obj.data.copy()
            collection.objects.link(work)
            if ratio < 0.999:
                decimate = work.modifiers.new("Blessed distance LOD", "DECIMATE")
                decimate.ratio = ratio
            bpy.ops.object.select_all(action="DESELECT")
            work.select_set(True)
            bpy.context.view_layer.objects.active = work
            bpy.ops.export_scene.gltf(filepath=filepath, export_format="GLB",
                use_selection=True, export_apply=True, export_materials="EXPORT",
                export_cameras=False, export_lights=False, export_yup=True,
                export_vertex_color="ACTIVE")
            bpy.data.objects.remove(work, do_unlink=True)

        save_selected(joined, os.path.join(OUT, name + ".glb"))
        if name.startswith(("tree_", "rock_cluster", "plant_")):
            save_selected(joined, os.path.join(OUT, name + "_lod1.glb"), .48)
            save_selected(joined, os.path.join(OUT, name + "_lod2.glb"), .20)


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in tuple(bpy.data.collections):
        if collection != bpy.context.scene.collection:
            bpy.data.collections.remove(collection)
    materials()
    broad_tree("tree_oak", 6.4,
        ["Blessed | leaf deep", "Blessed | leaf mid", "Blessed | leaf sun"], 1.72)
    broad_tree("tree_sakura", 5.65,
        ["Blessed | petal shadow", "Blessed | petal", "Blessed | petal light"], 1.58, True)
    pine_tree()
    birch_tree()
    willow_tree()
    rock_cluster()
    grass_clump()
    fern_clump()
    flower_clump()
    reed_clump()
    seaweed()
    bush_plant(False)
    bush_plant(True)
    mushroom_cluster()
    log_pickup()
    leaf_pickup()
    berry_pickup()
    tool_axe()
    tool_pickaxe()

    # Native source remains editable; runtime models are isolated per asset.
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE_OUT, "blessed_asset_kit.blend"))
    for name, collection in ASSETS.items():
        export_asset(name, collection)
    print("BLESSED_ASSET_KIT_EXPORT_OK", len(ASSETS), "assets", OUT)


if __name__ == "__main__":
    main()
