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


func _ready() -> void:
	add_child(RoomScene.instantiate())


func _process(_delta: float) -> void:
	_frames += 1
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
	get_tree().quit(0 if ok else 1)
