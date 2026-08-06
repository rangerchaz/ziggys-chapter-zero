## Phase 4 lighting rig probe. Headless-safe (checks node/resource state,
## not pixels):
##
##     godot --headless --path . res://tests/lighting_probe.tscn
##
## Verifies the warm_lights group, pendant shadows, the cold #00d4ff exterior
## light, the WorldEnvironment feature set, the bar top material, and the
## LightRegistry brownout hook. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

var _failures := 0


func _ready() -> void:
	var room := RoomScene.instantiate()
	# Phase 5 spawns a player into the room; this probe checks the rig alone.
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_warm_group()
	_check_pendant_shadows()
	_check_cold_light()
	_check_environment()
	_check_window_glass()
	_check_bar_top_material()
	_check_registry_scaling()
	if _failures == 0:
		print("LIGHTING PROBE PASS")
	else:
		printerr("LIGHTING PROBE FAIL (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_failures += 1
		printerr("  FAIL: %s" % label)


func _check_warm_group() -> void:
	var warm := LightRegistry.get_warm_lights(get_tree())
	# 5 pendants x (bulb + lamp light) + neon (Z + underbar + spill light)
	# + oven (ember + fire light) = 15 tagged instruments.
	_expect(warm.size() == 15, "warm_lights group has 15 members (got %d)" % warm.size())
	for node in warm:
		if not (node is Light3D or node is GeometryInstance3D):
			_expect(false, "warm_lights member %s is a light or geometry" % node.name)
			return
	_expect(true, "every warm_lights member is a light or emissive geometry")


func _check_pendant_shadows() -> void:
	var shadowed := 0
	for node in LightRegistry.get_warm_lights(get_tree()):
		if node is OmniLight3D and node.shadow_enabled:
			shadowed += 1
	_expect(shadowed == 5, "5 shadow-casting pendant lights (got %d)" % shadowed)


func _check_cold_light() -> void:
	var wash := get_node_or_null("ZiggysRoom/DataCenterWash")
	if wash == null:
		_expect(false, "DataCenterWash node exists")
		return
	_expect(wash is DirectionalLight3D, "DataCenterWash is a DirectionalLight3D")
	_expect(wash.shadow_enabled, "cold wash casts window-shaped shadows")
	var c: Color = wash.light_color
	var target := Color(0.0, 0.831, 1.0)
	var close := absf(c.r - target.r) < 0.02 and absf(c.g - target.g) < 0.02 and absf(c.b - target.b) < 0.02
	_expect(close, "cold wash color is #00d4ff (got %s)" % c)
	_expect(not wash.is_in_group(LightRegistry.WARM_GROUP), "cold wash is NOT in warm_lights")
	var dir: Vector3 = -wash.global_transform.basis.z
	_expect(dir.z < -0.5 and dir.y < -0.2, "cold wash aims into the room and down (dir %s)" % dir)


func _check_environment() -> void:
	var we := get_node_or_null("ZiggysRoom/WorldEnvironment")
	if we == null or we.environment == null:
		_expect(false, "WorldEnvironment with environment resource exists")
		return
	var env: Environment = we.environment
	_expect(env.glow_enabled, "glow/bloom enabled")
	_expect(env.volumetric_fog_enabled, "volumetric fog enabled")
	_expect(env.ssao_enabled and env.ssao_intensity <= 1.5, "subtle SSAO enabled")
	_expect(env.ssr_enabled and env.ssr_max_steps >= 32, "SSR enabled with tuned steps")
	_expect(env.tonemap_mode == Environment.TONE_MAPPER_ACES, "filmic ACES tonemapping")
	var warm_nudge := env.adjustment_enabled and env.adjustment_color_correction != null
	_expect(warm_nudge, "warm color-correction nudge active")


func _check_window_glass() -> void:
	var glass := get_node_or_null("ZiggysRoom/Shell/WindowGlass")
	if glass == null:
		_expect(false, "WindowGlass node exists")
		return
	var pass_through: bool = glass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_expect(pass_through, "window glass lets the cyan wash through (cast_shadow off)")


func _check_bar_top_material() -> void:
	var mat: StandardMaterial3D = load("res://materials/bar_top.tres")
	if mat == null:
		_expect(false, "materials/bar_top.tres loads")
		return
	_expect(mat.roughness_texture is NoiseTexture2D, "bar top roughness is noise-driven")
	_expect(mat.roughness <= 0.5, "bar top base roughness low enough for wet reflections")
	var counter_top := get_node_or_null("ZiggysRoom/Props/BarCounter/CounterTop")
	_expect(counter_top != null and counter_top.material == mat, "bar counter top uses bar_top.tres")


func _check_registry_scaling() -> void:
	var lamp: OmniLight3D = null
	for node in LightRegistry.get_warm_lights(get_tree()):
		if node is OmniLight3D and node.shadow_enabled:
			lamp = node
			break
	if lamp == null:
		_expect(false, "found a pendant light for the scaling check")
		return
	var base: float = lamp.light_energy
	LightRegistry.scale_warm_lights(get_tree(), 0.25)
	var dimmed := is_equal_approx(lamp.light_energy, base * 0.25)
	LightRegistry.scale_warm_lights(get_tree(), 1.0)
	var restored := is_equal_approx(lamp.light_energy, base)
	_expect(dimmed and restored, "LightRegistry brownout scaling dims and restores")
