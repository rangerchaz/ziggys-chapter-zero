## Phase 5 render probe. Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/meckie_render_probe.tscn
##
## Spawns the room with the playable Droid Meckie, then:
##   1. saves a third-person shot and pixel-checks the cyan signature
##      (emissive faceplate/accents plus the OmniLight3D pool on the floor),
##   2. swaps meckie_id to Eva at runtime and pixel-checks that the same
##      shot turns pink with no code edits,
##   3. backs the Meckie against the front wall and verifies the SpringArm3D
##      pulled the camera in instead of clipping through geometry.
## Saves three artifacts to tests/artifacts/. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

var _frames := 0
var _failures := 0
var _player: CharacterBody3D
var _rig: SpringArm3D


func _ready() -> void:
	add_child(RoomScene.instantiate())
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	_failures += 1


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		5:
			var room := get_child(0)
			for child in room.get_children():
				if child is MeckiePlayerController:
					_player = child
			if _player == null:
				printerr("MECKIE RENDER PROBE FAIL (no player spawned)")
				get_tree().quit(1)
				return
			_rig = _player.get_node(^"CameraRig")
			# Pose on the open floor, facing the camera, bar as backdrop.
			_player.global_position = Vector3(0.8, 0.05, 1.2)
			_player.velocity = Vector3.ZERO
			_player.rotation.y = PI
			_rig.global_position = _player.global_position + Vector3(0, 1.35, 0)
			_rig.rotation = Vector3(-0.3, 0, 0)
		60:
			var image := _shot("meckie_third_person.png")
			var pct := _signature_pct(image, true)
			print("droid shot cyan pixels: %.2f%%" % pct)
			if pct < 0.4:
				_fail("Droid signature cyan barely present in shot (%.2f%%)" % pct)
		70:
			_player.meckie_id = &"eva"
			var light: OmniLight3D = _player.get_node(^"SignatureLight")
			if not light.light_color.is_equal_approx(MeckieDefs.color_of(&"eva")):
				_fail("meckie_id swap did not recolor the cast light")
		110:
			var image := _shot("meckie_signature_swap.png")
			var pct := _signature_pct(image, false)
			print("eva shot pink pixels: %.2f%%" % pct)
			if pct < 0.4:
				_fail("Eva signature pink barely present after swap (%.2f%%)" % pct)
		120:
			# Back against the front window: the arm extends into the wall.
			_player.global_position = Vector3(0, 0.05, 4.1)
			_player.velocity = Vector3.ZERO
			_player.rotation.y = PI
			_rig.global_position = _player.global_position + Vector3(0, 1.35, 0)
			_rig.rotation = Vector3(-0.15, 0, 0)
		170:
			if _rig.get_hit_length() > 2.2:
				_fail("Spring arm did not pull in at the wall (hit %f)" % _rig.get_hit_length())
			_shot("meckie_camera_pullin.png")
			if _failures == 0:
				print("MECKIE RENDER PROBE PASS")
				get_tree().quit(0)
			else:
				printerr("MECKIE RENDER PROBE FAIL (%d failures)" % _failures)
				get_tree().quit(1)


func _shot(file_name: String) -> Image:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("res://tests/artifacts/" + file_name)
	if err != OK:
		_fail("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
	return image


## Counts signature-colored pixels in the central region of the frame
## (the Meckie and its light pool), as a percentage of sampled pixels.
func _signature_pct(image: Image, cyan: bool) -> float:
	var hits := 0
	var total := 0
	for y in range(int(image.get_height() * 0.3), int(image.get_height() * 0.95), 4):
		for x in range(int(image.get_width() * 0.25), int(image.get_width() * 0.75), 4):
			var c := image.get_pixel(x, y)
			total += 1
			if cyan:
				if c.b > 0.25 and c.b > c.r * 1.6 and c.g > c.r:
					hits += 1
			else:
				if c.r > 0.25 and c.r > c.g * 1.7 and c.b > c.g:
					hits += 1
	return 100.0 * hits / total
