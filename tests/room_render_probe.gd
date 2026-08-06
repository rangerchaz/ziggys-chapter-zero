## Phase 3 render probe. Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/room_render_probe.tscn
##
## Loads the assembled room, lets it render for a moment, then saves a
## screenshot to tests/artifacts/room_screenshot.png for visual review.
## Exits 0 when the screenshot is written, 1 otherwise.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

var _frames := 0


func _ready() -> void:
	add_child(RoomScene.instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 45:
		return
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("res://tests/artifacts/room_screenshot.png")
	if err == OK:
		print("RENDER PROBE PASS (screenshot saved)")
	else:
		printerr("RENDER PROBE FAIL (save_png error %d)" % err)
	get_tree().quit(0 if err == OK else 1)
