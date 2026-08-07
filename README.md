# Wichita Guild - Chapter Zero: A Night at Ziggy's

A single-chapter 3D vertical slice in Godot 4.7. One room, one evening, one
decision. See `spec.md` for the full pitch and art direction.

## Requirements

- Godot 4.7 (Forward+ rendering method)
- GDScript only - no C# or native modules

## Running

Open the project in the Godot 4.7 editor and press Play, or from the repo
root:

```sh
godot --path .
```

The project boots to the title screen at 1920x1080. Start loads the chapter
entry scene; Quit exits cleanly.

## Project layout

| Path | Purpose |
|---|---|
| `scenes/room/` | The Ziggy's interior and its assembly scenes (`ziggys_room.tscn` is the shipped room) |
| `scenes/room/ziggys_shell.tscn` | CSG-authored room shell — editable source, not instanced by the shipped room |
| `scenes/room/ziggys_shell_baked.tscn` | Baked `MeshInstance3D` shell instanced by `ziggys_room.tscn` |
| `scenes/props/` | One CSG-authored scene per prop or furniture piece — editable source |
| `scenes/props/baked/` | Baked `MeshInstance3D` version of every prop, instanced by `ziggys_room.tscn` |
| `scenes/characters/` | Meckies and the people of the bar (`npc_human.tscn` is CSG source, `npc_human_baked.tscn` is what the room ships) |
| `scenes/ui/` | Title, pause, settings, dialogue UI |
| `tools/bake_csg.gd` | Headless bake tool — CSG source scenes in, baked `MeshInstance3D` scenes out |
| `scripts/autoload/` | Singletons registered in project settings (`GameState`, `SettingsManager`, `DialogueDB`) |
| `scripts/systems/` | Gameplay systems (interaction, brownout, dialogue runner) |
| `scripts/ui/` | Scripts backing the UI scenes |
| `content/dialogue/` | Data-driven dialogue as JSON, validated by schema |
| `content/chapters/` | Data-driven chapters as JSON, validated by schema (`chapter-zero.json` is the shipped chapter) |
| `materials/` | Shared material resources (`.tres`) |
| `shaders/` | Godot shader files (`.gdshader`) |
| `tests/` | Headless smoke tests |

## CSG authoring / bake for ship (Phase 16)

Godot's docs are explicit that CSG (`CSGShape3D` and friends) is a
prototyping tool with a runtime cost — every CSG node rebuilds its own mesh
and collision shape, and doesn't batch or cull as well as a plain
`MeshInstance3D`. This project uses CSG as the **authoring layer** (fast to
block out, no imported/modelled assets, still procedurally generated) but
the **shipped room ships baked geometry**, not live CSG nodes:

- **Author here** (edit these, then re-bake): `scenes/room/ziggys_shell.tscn`,
  every scene directly under `scenes/props/` (not `scenes/props/baked/`),
  and `scenes/characters/npc_human.tscn`. These stay ordinary
  `CSGShape3D`/`CSGCombiner3D` trees — open them in the editor, tweak
  primitives and materials, and preview them like any other scene.
- **Ship this** (never hand-edited): `scenes/room/ziggys_shell_baked.tscn`,
  every scene under `scenes/props/baked/`, and
  `scenes/characters/npc_human_baked.tscn`. `scenes/room/ziggys_room.tscn`
  — the one scene actually instanced by the game — instances these, not
  the CSG source. Each is a plain `MeshInstance3D` (or a small tree of
  them) with baked-in per-surface materials, plus a `StaticBody3D` +
  `CollisionShape3D` wherever the source had `use_collision = true`.
- **Re-bake after any edit** to a source scene:

  ```sh
  godot --headless --path . --script res://tools/bake_csg.gd
  ```

  This instances every scene in `tools/bake_csg.gd`'s `TARGETS` list, lets
  the CSG tree settle, then for every independent CSG root calls
  `CSGShape3D.bake_static_mesh()` / `bake_collision_shape()` — the same
  operation the editor's *CSG → Bake Mesh Instance* menu action performs —
  and writes the result to the matching `*_baked.tscn` path. Non-CSG
  children (lights, `AudioStreamPlayer3D` generators, hand-authored
  collision, and — for `npc_human.tscn` — the `NpcHuman` script and its
  exported properties) are carried over untouched, so per-instance
  overrides set in `ziggys_room.tscn` (`npc_id`, `body_color`, `pose`, …)
  keep working exactly as before against the baked scene.
- **Emissive parts stay independently dimmable.** A handful of CSG shapes
  per prop (pendant bulbs, the oven ember, the neon tubes, the jukebox's
  arch/strips) are tagged into the `warm_lights` group so Phase 11's
  brownout beat can fade them. Baking preserves that group tag on the
  resulting `MeshInstance3D`, and `LightRegistry.scale_warm_lights()`
  (`scripts/lighting/light_registry.gd`) reads/writes the emissive
  material via `material_override` (or surface 0's material as a
  fallback) instead of `CSGShape3D`'s own `material` property, so the beat
  reads identically whether it's driving the CSG source or the baked
  scene.
- **Why NPCs bake too:** `npc_human.tscn`'s root is a plain `Node3D` (not
  `CSGCombiner3D`) carrying a hand-authored capsule
  `StaticBody3D`/`CollisionShape3D` instead of CSG's automatic
  `use_collision` body, specifically so the same script and the same bake
  pipeline used for props also works for the ten regulars — ten CSG
  figures at ~13 primitives each was the single biggest concentration of
  runtime CSG nodes in the room.

See `PERFORMANCE.md` for the frame-rate win this unlocks and the
shadow-caster audit that goes with it.

## Conventions

- Scenes are text-format `.tscn` only, kept small and composed - one scene
  per prop, assembled into the room scene - so diffs stay reviewable.
- Resources are text-format `.tres`.
- Content lives in JSON under `content/`, not in code; schemas validate it.
- The `GameState` autoload holds chapter flags (`selected_meckie`,
  `brownout_fired`, `closing_decision`) and emits a signal when each changes.
- Input actions defined in project settings: `move_forward`, `move_back`,
  `move_left`, `move_right` (WASD and arrows), `interact` (E), `pause`
  (Escape), plus explicit `ui_accept` / `ui_cancel`.
- Audio buses: `Master` with `Music`, `SFX`, and `Ambient` routed into it
  (`default_bus_layout.tres`).

## Testing

Import and parse checks plus the Sprint 1 smoke test run headless:

```sh
godot --headless --path . --import
godot --headless --path . res://tests/smoke_test.tscn
```

The smoke test verifies GameState defaults and signals, the title screen's
buttons and wiring, and that Start lands in the chapter entry scene. Note
that `--headless` cannot render; anything that produces a picture must run
windowed.

Phase 3 added the room probes and Phase 4 the lighting probes:

```sh
godot --headless --path . res://tests/room_probe.tscn      # structure, collision
godot --headless --path . res://tests/lighting_probe.tscn  # warm_lights rig, env
godot --path . res://tests/room_render_probe.tscn          # windowed screenshot
godot --path . res://tests/lighting_render_probe.tscn      # windowed, checks that
                                                           # warm AND cyan pixels
                                                           # read in one frame,
                                                           # saves 3 QA angles
```

Screenshots land in `tests/artifacts/` (gitignored).

Phase 8 added the dialogue content probe:

```sh
godot --headless --path . res://tests/dialogue_content_probe.tscn
```

Validates every NPC's content file against the schema, prints a per-NPC
pass/fail table, and checks the cross-file rules (every NPC has a
`pre_brownout` and `post_brownout` line, no two NPCs share an identical
`post_brownout` line, Caroline's `closing` entry has exactly four choices).

Phase 16 added the bake-to-mesh probes:

```sh
godot --headless --path . res://tests/room_probe.tscn        # now also asserts
                                                               # zero CSGShape3D
                                                               # nodes in the room
godot --headless --path . res://tests/fps_overlay_probe.tscn # F3 toggle + readout
godot --path . res://tests/perf_phase16_probe.tscn            # windowed, 1920x1080,
                                                               # min/avg/max fps
                                                               # across a room tour
godot --path . res://tests/qa_phase16_probe.tscn              # windowed, saves
                                                               # pre-brownout/
                                                               # mid-fade/full-
                                                               # brownout/dialogue/
                                                               # four-option shots
                                                               # to
                                                               # .turkey/screenshots/
                                                               # phase-16/
```

## Dialogue content convention (version 1)

Dialogue is data, not code: nothing in `scripts/` holds a line a player will
read. This is the shape later chapters should reuse.

- **Schema**: `content/dialogue/dialogue.schema.json` (JSON Schema, draft
  2020-12) defines the shape every NPC file must match — a top-level
  `schema_version` (currently `1`), `npc_id`, `display_name`, and `entries`
  keyed by chapter state: `pre_brownout`, `post_brownout`, and (Caroline
  only) `closing`. Each state has a non-empty `lines` array; `closing`
  additionally requires a `choices` array of exactly four `{id, text}`
  objects — the four closing-decision answers.
- **Content**: one file per NPC, `content/dialogue/<npc_id>.json`, `npc_id`
  matching the roster in `scripts/data/npc_defs.gd`. Every regular has at
  least a `pre_brownout` and a distinct `post_brownout` reaction line;
  Caroline's file additionally carries the `closing` entry.
- **Validation**: `scripts/systems/dialogue_schema_validator.gd`
  (`DialogueSchemaValidator`) is a hand-rolled interpreter for the subset of
  JSON Schema this project's schema actually uses (`type`, `required`,
  `properties`/`additionalProperties`, `items`, `minItems`/`maxItems`,
  `minLength`, `const`, local `$ref`s into `$defs`) — no addon. Errors name
  the offending path (e.g. `chad.json.entries.pre_brownout.lines[0]:
  string is empty...`) rather than just "invalid".
- **Access**: the `DialogueDB` autoload (`scripts/autoload/dialogue_db.gd`)
  loads and validates every NPC file on boot and exposes
  `get_lines(npc_id, state)` and `get_closing_choices()`. A file that's
  missing or fails validation is reported loudly via `push_error` naming
  the file and the specific violation — it never falls back to a
  placeholder string.
- **Editing**: change a line in JSON and rerun; `DialogueDB` picks it up
  with no code change. Run the probe above to confirm content is still
  schema-valid before committing.

Later chapters that add dialogue should point their content at a schema
with the same shape (bump `schema_version` if the shape changes) rather
than inventing a new one.

## Chapter content convention (version 1)

A chapter is data too: which NPCs are in the room and what happens, in
order, is a JSON file — not a scene-specific director node wired up by
hand. **`content/chapters/chapter-zero.json` is the first chapter authored
in this format**, replacing the original hand-wired implementation rather
than living alongside it (see `spec-chapters.md` for the full rationale and
`docs/SAVE_FORMAT.md` for why its three save keys never moved).

- **Schema**: `content/chapters/chapter.schema.json` (JSON Schema, draft
  2020-12) defines the shape every chapter file must match — a top-level
  `schema_version` (currently `1`), `id`, `title`, `author`, `summary`, an
  optional `requires` array (absent means "playable any time"), a `cast`
  array of NPC ids, and an ordered `beats` array. Each beat has an `id`, a
  `kind` from the closed set `ambience` / `lighting` / `dialogue` /
  `decision` / `end`, and an optional `after` trigger (`{conversations: N}`,
  optionally `since: <beat_id>`) — absent means "fires on start."
- **Content**: one file per chapter, `content/chapters/<id>.json`. A chapter
  cannot introduce a new beat kind or room geometry — every beat it can ask
  for is a kind the engine already implements, so a chapter file is data,
  never a way to run arbitrary code.
- **Validation**: `scripts/systems/chapter_schema_validator.gd` reuses the
  same hand-rolled JSON Schema interpreter dialogue content uses, plus
  `ChapterDB.check_chapter_valid()`'s business-logic checks beyond the
  schema — every `cast` id must be a real NPC with loaded dialogue content,
  and every beat's `kind` must be one of the closed five. A chapter that
  fails either is reported loudly (naming the file and the exact violation)
  and excluded from the loaded set; one bad chapter file never blocks its
  siblings.
- **Access**: the `ChapterDB` autoload (`scripts/autoload/chapter_db.gd`)
  loads and validates every chapter file on boot. `scripts/ui/chapter_select.gd`
  lists every loaded chapter (Chapter Zero included — there is no
  chapter-specific row anymore), greying out one whose `requires` isn't met
  by the current save rather than hiding it.
- **Running**: `scripts/systems/beat_runner.gd` (`BeatRunner`) walks a
  loaded chapter's `beats` in order, evaluating each one's `after` trigger
  against completed conversations, and dispatches each `kind` to the
  engine's existing implementation of it — `BrownoutDirector` for `lighting:
  brownout`, `DialogueUI` for `dialogue`/`decision`. Those nodes no longer
  decide *when* to fire (no self-registered `conversation_completed`
  listeners, no debug-key handling of their own); BeatRunner owns every
  trigger, and they're left as the callable fade/effect and prompt logic it
  invokes.
- **Editing**: change a chapter's JSON and rerun; `ChapterDB` picks it up
  with no code change. `godot --headless --path . res://tests/chapter_validation_probe.tscn`
  validates every file in `content/chapters/`.

## Lighting

The two-temperature look lives in `scenes/room/ziggys_room.tscn`: warm amber
pendants, red-pink neon and orange oven glow inside, and the cold `#00d4ff`
data-center wash (`DataCenterWash`, a shadowed DirectionalLight3D) raking
through the front window as a long cyan rectangle on the floor. One
WorldEnvironment carries glow, volumetric fog, subtle SSAO, SSR and a warm
color-correction nudge. Every warm instrument sits in the `warm_lights`
group; `scripts/lighting/light_registry.gd` (`LightRegistry`) enumerates and
scales the set for the Phase 11 brownout.
