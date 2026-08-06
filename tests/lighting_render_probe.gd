## Phase 4 render probe. Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/lighting_render_probe.tscn
##
## Renders the assembled room, saves tests/artifacts/lighting_screenshot.png
## for visual review, then checks the two-temperature read in the pixels:
## a meaningful population of warm amber/pink pixels AND a meaningful
## population of cold cyan pixels (the #00d4ff window rectangle) in the same
## frame. Exits 0 when both temperatures are present, 1 otherwise.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

var _frames := 0
var _bar_camera: Camera3D
var _oven_camera: Camera3D


func _ready() -> void:
	var room := RoomScene.instantiate()
	# Phase 5 spawns a player whose camera would steal these fixed angles.
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	# Second angle for close-up QA: bar top SSR (pendants on screen above the
	# wet counter) and pendant shadows from the stools on the floor.
	_bar_camera = Camera3D.new()
	_bar_camera.fov = 60.0
	add_child(_bar_camera)
	_bar_camera.global_position = Vector3(3.6, 1.7, -0.9)
	_bar_camera.look_at(Vector3(-0.8, 1.0, -3.4))
	# Third angle: straight at the oven mouth for the ember glow/bloom check.
	_oven_camera = Camera3D.new()
	_oven_camera.fov = 55.0
	add_child(_oven_camera)
	_oven_camera.global_position = Vector3(-4.6, 1.5, -0.8)
	_oven_camera.look_at(Vector3(-5.5, 1.25, -3.6))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		_bar_camera.make_current()
	if _frames == 120:
		var closeup := get_viewport().get_texture().get_image()
		closeup.save_png("res://tests/artifacts/lighting_bar_closeup.png")
		print("bar closeup saved")
		_oven_camera.make_current()
	if _frames == 150:
		var oven_shot := get_viewport().get_texture().get_image()
		oven_shot.save_png("res://tests/artifacts/lighting_oven_closeup.png")
		print("oven closeup saved")
		get_tree().quit(0)
	if _frames != 60:
		return
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("res://tests/artifacts/lighting_screenshot.png")
	if err != OK:
		printerr("LIGHTING RENDER PROBE FAIL (save_png error %d)" % err)
		get_tree().quit(1)
		return

	var warm := 0
	var cold := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c := image.get_pixel(x, y)
			total += 1
			if c.r > 0.22 and c.r > c.b * 1.5:
				warm += 1
			if c.b > 0.25 and c.b > c.r * 1.6 and c.g > c.r:
				cold += 1
	var warm_pct := 100.0 * warm / total
	var cold_pct := 100.0 * cold / total
	print("warm pixels: %.2f%%, cold pixels: %.2f%%" % [warm_pct, cold_pct])
	var ok := warm_pct > 4.0 and cold_pct > 0.8
	if ok:
		print("LIGHTING RENDER PROBE PASS (both temperatures read)")
	else:
		printerr("LIGHTING RENDER PROBE FAIL (warm %.2f%% needs > 4, cold %.2f%% needs > 0.8)" % [warm_pct, cold_pct])
		get_tree().quit(1)
