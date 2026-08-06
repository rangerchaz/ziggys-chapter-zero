# Performance (Phase 16)

## Measured frame rate

Windowed, 1920x1080, on an Apple M4 (Metal 4.0 / Forward+), measured with
`res://tests/perf_phase16_probe.tscn` (`godot --path . res://tests/perf_phase16_probe.tscn`,
**not** `--headless` — `--headless` uses the dummy renderer and cannot
produce a real frame-time number). The probe tours the real player camera
through eight waypoints covering the whole room (door, bar, booths, oven,
jukebox, center table, window, a wide establishing angle) and samples
`Engine.get_frames_per_second()` at each stop after the view settles.

| Waypoint      | min fps | avg fps | max fps |
|---------------|--------:|--------:|--------:|
| door          |    75.0 |    75.0 |    75.0 |
| bar           |    79.0 |    79.0 |    79.0 |
| booths        |    79.0 |    79.0 |    79.0 |
| oven          |    79.0 |    80.4 |    81.0 |
| jukebox       |    80.0 |    80.5 |    81.0 |
| table_center  |    79.0 |    79.7 |    80.0 |
| window        |    79.0 |    79.0 |    79.0 |
| room_wide     |    79.0 |    79.0 |    79.0 |
| **overall**   |**75.0** |**79.0** |**81.0** |

Overall: **min 75 fps / avg 79 fps** across 320 samples — comfortably clear
of the 60fps@1080p acceptance target everywhere in the room, including the
worst-observed waypoint (the door, which frames the most geometry at once:
the full bar line, both booths, and the street through the front window).
The in-game overlay (`res://scenes/ui/fps_overlay.tscn` — toggle with **F3**)
reads the same live number during manual play for spot-checks.

## What got this here: the CSG bake

Godot's own docs call CSG a prototyping tool with a runtime cost. Before
this phase, the shipped room instantiated ~180 live `CSGShape3D` nodes
(room shell, 8 prop types, and 10 NPCs at ~13 CSG primitives each) that
each rebuild their mesh and collision shape at scene load and carry extra
per-node overhead the renderer can't batch as well as a plain
`MeshInstance3D`. Every one of those is now baked to static
`MeshInstance3D` geometry (`CSGShape3D.bake_static_mesh()` /
`bake_collision_shape()`, the same operation the editor's *CSG → Bake Mesh
Instance* menu action performs) via `tools/bake_csg.gd`. See the README's
"CSG authoring / bake for ship" section for the full workflow and how to
re-bake after an edit.

## Shadow-caster audit

Per the spec's perf guidance ("keep pendant lights as the primary shadow
casters," argue against excessive real-time shadow casters), only two
light sources in the shipped room have `shadow_enabled = true`:

- **`DataCenterWash`** (`DirectionalLight3D`) — the cold exterior wash
  through the front window; needed for the window light shafts that carry
  the whole two-temperature look.
- **The 5 `PendantLamp` `LampLight`s** (`OmniLight3D`) — the primary warm
  shadow casters, per spec.

Every other light in the room — the oven's `FireLight`, the jukebox's
`JukeLight`, the neon sign's `SignLight`, the street `OmniLight3D`, and
all 10 NPCs' `FaceLight` (`SpotLight3D`) — is unshadowed
(`shadow_enabled` left at its `false` default). This was already true as
of Phase 4 (confirmed by grepping every `scenes/**/*.tscn` for
`shadow_enabled`); no change was needed for this phase, it's recorded here
as the audit the acceptance criteria call for.

## No other settings needed tuning

The bake alone cleared the 60fps target with enough headroom (75-81fps at
1080p windowed) that no additional quality knobs (SSAO/SSR/volumetric fog
radius, shadow atlas size, MSAA) needed to be turned down. Those all stay
at their Phase 4-authored values.
