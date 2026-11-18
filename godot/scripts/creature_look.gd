class_name CreatureLook
extends RefCounted
## Finishes the materials of the painted, skinned models (blender/creature_kit.py). Their colour
## is baked into vertex colours (paint and ambient occlusion), stored sRGB-encoded so the darks
## don't band in 8 bits; the importer doesn't know that, so the first time a model is spawned its
## materials are told to read them that way, and given the rim light and membrane settings that
## glTF can't carry. Materials are shared by every instance of a model, so this runs once each.

const DONE := "creature_look"


static func apply(root: Node) -> void:
	for mi in Rig.meshes(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
				continue
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or m.has_meta(DONE):
				continue
			m.set_meta(DONE, true)
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				# Membranes: see-through from both sides, lit from behind, no shadow of their own.
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.rim_enabled = true
				m.rim = 0.7
				m.rim_tint = 0.4
			elif not m.emission_enabled:
				# Hide and shell: a faint rim so dark creatures keep an edge against dark rock.
				m.rim_enabled = true
				m.rim = 0.25
				m.rim_tint = 0.6
