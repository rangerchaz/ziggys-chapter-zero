## Phase 16 CSG bake tool, runnable headless:
##
##     godot --headless --path . --script res://tools/bake_csg.gd
##
## Mirrors the editor's "CSG -> Bake Mesh Instance" action for every prop and
## the room shell: instances each CSG-authored scene, lets the CSG tree
## settle, then replaces every independent CSG root (CSGShape3D.bake_static_mesh
## / bake_collision_shape) with a MeshInstance3D (+ StaticBody3D collision
## where the source had use_collision=true), while non-CSG siblings (lights,
## audio generators) are duplicated as-is. Output goes to scenes/props/baked/
## and scenes/room/ziggys_shell_baked.tscn; the CSG source scenes under
## scenes/props/ and scenes/room/ziggys_shell.tscn are never modified, so
## they remain the editable authoring layer. Re-run this script after any
## edit to a source CSG scene to refresh its baked counterpart.
extends SceneTree

const TARGETS := [
	{"src": "res://scenes/props/bar_counter.tscn", "out": "res://scenes/props/baked/bar_counter_baked.tscn"},
	{"src": "res://scenes/props/bar_stool.tscn", "out": "res://scenes/props/baked/bar_stool_baked.tscn"},
	{"src": "res://scenes/props/booth.tscn", "out": "res://scenes/props/baked/booth_baked.tscn"},
	{"src": "res://scenes/props/jukebox.tscn", "out": "res://scenes/props/baked/jukebox_baked.tscn"},
	{"src": "res://scenes/props/neon_sign.tscn", "out": "res://scenes/props/baked/neon_sign_baked.tscn"},
	{"src": "res://scenes/props/pendant_lamp.tscn", "out": "res://scenes/props/baked/pendant_lamp_baked.tscn"},
	{"src": "res://scenes/props/pizza_oven.tscn", "out": "res://scenes/props/baked/pizza_oven_baked.tscn"},
	{"src": "res://scenes/props/table.tscn", "out": "res://scenes/props/baked/table_baked.tscn"},
	{"src": "res://scenes/room/ziggys_shell.tscn", "out": "res://scenes/room/ziggys_shell_baked.tscn"},
	{"src": "res://scenes/characters/npc_human.tscn", "out": "res://scenes/characters/npc_human_baked.tscn"},
]

const SETTLE_FRAMES := 20

var _had_error := false


func _initialize() -> void:
	_run()


func _run() -> void:
	for target: Dictionary in TARGETS:
		await _bake_one(target["src"], target["out"])
	if _had_error:
		printerr("BAKE FAILED")
		quit(1)
	else:
		print("BAKE COMPLETE")
		quit(0)


func _bake_one(src_path: String, out_path: String) -> void:
	var packed: PackedScene = load(src_path)
	if packed == null:
		printerr("Could not load %s" % src_path)
		_had_error = true
		return

	var inst: Node = packed.instantiate()
	root.add_child(inst)
	for _i in SETTLE_FRAMES:
		await process_frame

	# Mutate the live instance in place rather than building a parallel tree,
	# so a scripted root (e.g. npc_human.gd's NpcHuman) keeps its script,
	# exported properties and non-CSG children (lights, audio, hand-authored
	# collision) untouched - only independent CSG roots get swapped for their
	# baked MeshInstance3D equivalent.
	var new_root: Node
	if inst is CSGShape3D:
		new_root = _bake_root(inst as CSGShape3D)
		new_root.name = inst.name
		root.remove_child(inst)
		inst.queue_free()
	else:
		for child in inst.get_children():
			if child is CSGShape3D and (child as CSGShape3D).is_root_shape():
				var baked := _bake_root(child as CSGShape3D)
				var idx := child.get_index()
				inst.remove_child(child)
				child.queue_free()
				inst.add_child(baked)
				inst.move_child(baked, idx)
			elif _contains_csg(child):
				push_warning("%s: child %s has nested CSG that isn't an independent root; leaving it unbaked" % [src_path, child.name])
		root.remove_child(inst)
		new_root = inst

	_assign_owner(new_root, new_root)

	var mesh_count := _count_mesh_instances(new_root)
	if mesh_count == 0:
		printerr("%s: baked tree has no MeshInstance3D nodes" % src_path)
		_had_error = true

	var dir_path := out_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var packed_out := PackedScene.new()
	var pack_err := packed_out.pack(new_root)
	if pack_err != OK:
		printerr("Failed to pack %s: %d" % [out_path, pack_err])
		_had_error = true
	else:
		var save_err := ResourceSaver.save(packed_out, out_path)
		if save_err != OK:
			printerr("Failed to save %s: %d" % [out_path, save_err])
			_had_error = true
		else:
			print("Baked %s -> %s (%d mesh instances)" % [src_path, out_path, mesh_count])

	new_root.queue_free()


func _bake_root(csg: CSGShape3D) -> MeshInstance3D:
	var mesh: ArrayMesh = csg.bake_static_mesh()
	var mi := MeshInstance3D.new()
	mi.name = csg.name
	mi.transform = csg.transform
	mi.visible = csg.visible
	mi.mesh = mesh
	mi.cast_shadow = csg.cast_shadow
	for g in csg.get_groups():
		mi.add_to_group(g, true)

	if csg.use_collision:
		var shape: ConcavePolygonShape3D = csg.bake_collision_shape()
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = csg.collision_layer
		body.collision_mask = csg.collision_mask
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)

	return mi


func _contains_csg(node: Node) -> bool:
	for child in node.get_children():
		if child is CSGShape3D:
			return true
		if _contains_csg(child):
			return true
	return false


func _assign_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_assign_owner(child, owner_node)


func _count_mesh_instances(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count
