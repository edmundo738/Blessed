"""Adapt selected Quaternius CC0 nature models for Blessed and export Godot GLBs.

Run with Blender 5.2 from the project root. Each source stays in its own named
collection; the runtime exports remain one species per file.
"""
import bmesh
import bpy
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "content", "models", "source", "quaternius", "glTF")
SOURCE_BLEND = os.path.join(ROOT, "content", "models", "source", "blessed_quaternius_nature.blend")
OUT = os.path.join(ROOT, "content", "models", "runtime", "quaternius")
os.makedirs(OUT, exist_ok=True)

# Source name, target height in metres, LOD ratios. Canopies, shrubs and
# groundcover are individually normalized around the dimensions used in chunks.
SPECS = {
    "tree_oak": ("CommonTree_1", 6.8, (0.58, 0.25)),
    "tree_birch": ("CommonTree_2", 7.1, (0.58, 0.25)),
    "tree_willow": ("CommonTree_3", 7.4, (0.58, 0.25)),
    "tree_sakura": ("TwistedTree_1", 5.8, (0.58, 0.25)),
    "tree_pine": ("Pine_5", 8.4, (0.58, 0.25)),
    "plant_bush": ("Bush_Common_Flowers", 0.95, (0.55, 0.24)),
    "plant_berry_bush": ("Bush_Common_Flowers", 1.05, (0.55, 0.24)),
    "plant_mushroom": ("Mushroom_Common", 0.50, (0.58, 0.25)),
    "rock_cluster": ("Rock_Medium_2", 1.23, (0.52, 0.24)),
    "grass_clump": ("Grass_Common_Short", 0.68, ()),
    "fern_clump": ("Fern_1", 0.52, ()),
    "flower_clump": ("Flower_3_Group", 0.72, ()),
    "clover_clump": ("Clover_1", 0.40, ()),
    "reed_clump": ("Grass_Wispy_Tall", 1.12, ()),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection != bpy.context.scene.collection:
            bpy.data.collections.remove(collection)


def import_model(source_name, asset_id, target_height):
    filepath = os.path.join(SOURCE, source_name + ".gltf")
    if not os.path.isfile(filepath):
        raise FileNotFoundError(filepath)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=filepath)
    imported = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in imported if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh in " + source_name)

    # Preserve world transforms while removing empty import roots.
    bpy.context.view_layer.update()
    for obj in meshes:
        matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = matrix
    for obj in imported:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    collection = bpy.data.collections.new(asset_id)
    bpy.context.scene.collection.children.link(collection)
    for obj in meshes:
        for old in list(obj.users_collection):
            old.objects.unlink(obj)
        collection.objects.link(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = asset_id
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    if asset_id == "plant_berry_bush":
        _remove_material_faces(obj, "Flowers")
        _add_berries(collection)
        # Join the deliberately attached fruit into this one berry-bush asset.
        bpy.ops.object.select_all(action="DESELECT")
        for item in collection.objects:
            if item.type == "MESH":
                item.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.join()

    if asset_id == "rock_cluster":
        _neutralize_green_lichen(obj)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    dimensions = obj.dimensions
    # Ferns spread sideways: cap width as well as height instead of making them tall.
    if asset_id == "fern_clump":
        factor = min(target_height / max(dimensions.z, 0.001), 1.35 / max(dimensions.x, dimensions.y))
    else:
        factor = target_height / max(dimensions.z, 0.001)
    obj.scale = (factor, factor, factor)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Put each plant/tree on the ground at the origin for predictable placement.
    vertices = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = (min(v.x for v in vertices), min(v.y for v in vertices), min(v.z for v in vertices))
    hi = (max(v.x for v in vertices), max(v.y for v in vertices), max(v.z for v in vertices))
    bpy.context.scene.cursor.location = ((lo[0] + hi[0]) * .5, (lo[1] + hi[1]) * .5, lo[2])
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location = (0, 0, 0)
    obj.name = asset_id
    return collection, obj


def _remove_material_faces(obj, material_name):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    slots = list(obj.data.materials)
    remove = [f for f in bm.faces if f.material_index < len(slots)
              and slots[f.material_index] is not None
              and slots[f.material_index].name == material_name]
    if remove:
        bmesh.ops.delete(bm, geom=remove, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _add_berries(collection):
    red = bpy.data.materials.new("Blessed | ripe berry")
    red.diffuse_color = (0.68, 0.025, 0.055, 1)
    red.use_nodes = True
    red.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.68, 0.025, 0.055, 1)
    red.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.32
    # Small visible fruits grow on the same shrub. No extra foliage or species.
    berries = [(-.43, -.36, .58), (.41, -.40, .72), (-.55, .12, .88),
               (.52, .11, .52), (.28, .48, .91), (-.20, .50, .68)]
    for i, pos in enumerate(berries):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=.062,
                                             location=pos)
        berry = bpy.context.object
        berry.name = "Ripe berry %02d" % i
        berry.data.materials.append(red)
        for old in list(berry.users_collection):
            old.objects.unlink(berry)
        collection.objects.link(berry)


def _neutralize_green_lichen(obj):
    images = set()
    for material in obj.data.materials:
        if not material or not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and "Rock" in node.image.name:
                images.add(node.image)
    for image in images:
        clean = image.copy()
        clean.name = "Blessed stone | clean slate"
        pixels = list(clean.pixels[:])
        for i in range(0, len(pixels), 4):
            r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]
            if g > r * 1.08 and g > b * 1.08:
                gray = (r + g + b) / 3.0
                pixels[i] = gray * 1.025
                pixels[i + 1] = gray * 1.01
                pixels[i + 2] = gray * 0.99
        clean.pixels[:] = pixels
        clean.update()
        for material in obj.data.materials:
            if material and material.use_nodes:
                for node in material.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image == image:
                        node.image = clean


def export_model(asset_id, collection, ratios):
    obj = next(o for o in collection.objects if o.type == "MESH")

    def export_copy(path, ratio=1.0):
        work = obj.copy()
        work.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(work)
        if ratio < 0.999:
            decimate = work.modifiers.new("Distance LOD", "DECIMATE")
            decimate.ratio = ratio
        bpy.ops.object.select_all(action="DESELECT")
        work.select_set(True)
        bpy.context.view_layer.objects.active = work
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLTF_SEPARATE", use_selection=True,
            export_apply=True, export_materials="EXPORT", export_cameras=False,
            export_lights=False, export_yup=True)
        bpy.data.objects.remove(work, do_unlink=True)

    export_copy(os.path.join(OUT, asset_id + ".gltf"))
    for index, ratio in enumerate(ratios, 1):
        export_copy(os.path.join(OUT, "%s_lod%d.gltf" % (asset_id, index)), ratio)


def main():
    os.makedirs(OUT, exist_ok=True)
    clear_scene()
    imported = {}
    for asset_id, (source_name, height, lods) in SPECS.items():
        collection, obj = import_model(source_name, asset_id, height)
        imported[asset_id] = (collection, lods)
        dimensions = tuple(round(v, 3) for v in obj.dimensions)
        verts = len(obj.data.vertices)
        print("QUATERNIUS_ASSET", asset_id, "from", source_name,
              "dims", dimensions, "verts", verts,
              "lods", lods)

    bpy.ops.file.pack_all()
    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND)
    for asset_id, (collection, lods) in imported.items():
        export_model(asset_id, collection, lods)
    print("QUATERNIUS_RUNTIME_EXPORT_OK", len(imported), "assets", OUT)


if __name__ == "__main__":
    main()
