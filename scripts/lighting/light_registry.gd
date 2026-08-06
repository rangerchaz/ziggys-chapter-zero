## Phase 4 light registry. Every warm instrument (amber pendant bulbs and
## lights, the red-pink neon tubes, the oven ember and fire light) is tagged
## into the "warm_lights" group inside its prop scene, so the group instances
## with the fixture. Later phases (the Phase 11 brownout) address the whole
## warm rig through this class without knowing the room layout.
class_name LightRegistry

const WARM_GROUP := "warm_lights"

const _META_BASE_LIGHT := "warm_base_light_energy"
const _META_BASE_EMISSION := "warm_base_emission_energy"


static func get_warm_lights(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(WARM_GROUP)


## Scales every warm instrument to `factor` of its authored strength
## (1.0 = full glow, 0.0 = brownout). Covers both real light nodes and
## emissive geometry. Authored baselines are cached in node metadata on
## first use, so repeated calls set absolute levels and never compound.
static func scale_warm_lights(tree: SceneTree, factor: float) -> void:
	for node in tree.get_nodes_in_group(WARM_GROUP):
		if node is Light3D:
			if not node.has_meta(_META_BASE_LIGHT):
				node.set_meta(_META_BASE_LIGHT, node.light_energy)
			node.light_energy = node.get_meta(_META_BASE_LIGHT) * factor
		elif node is GeometryInstance3D and "material" in node:
			var mat: Material = node.material
			if mat is StandardMaterial3D and mat.emission_enabled:
				if not node.has_meta(_META_BASE_EMISSION):
					node.set_meta(_META_BASE_EMISSION, mat.emission_energy_multiplier)
				mat.emission_energy_multiplier = node.get_meta(_META_BASE_EMISSION) * factor
