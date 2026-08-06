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
| `scenes/room/` | The Ziggy's interior and its assembly scenes |
| `scenes/props/` | One scene per prop or furniture piece, composed into the room |
| `scenes/characters/` | Meckies and the people of the bar |
| `scenes/ui/` | Title, pause, settings, dialogue UI |
| `scripts/autoload/` | Singletons registered in project settings (`GameState`, `SettingsManager`, `DialogueDB`) |
| `scripts/systems/` | Gameplay systems (interaction, brownout, dialogue runner) |
| `scripts/ui/` | Scripts backing the UI scenes |
| `content/dialogue/` | Data-driven dialogue as JSON, validated by schema |
| `materials/` | Shared material resources (`.tres`) |
| `shaders/` | Godot shader files (`.gdshader`) |
| `tests/` | Headless smoke tests |

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

## Lighting

The two-temperature look lives in `scenes/room/ziggys_room.tscn`: warm amber
pendants, red-pink neon and orange oven glow inside, and the cold `#00d4ff`
data-center wash (`DataCenterWash`, a shadowed DirectionalLight3D) raking
through the front window as a long cyan rectangle on the floor. One
WorldEnvironment carries glow, volumetric fog, subtle SSAO, SSR and a warm
color-correction nudge. Every warm instrument sits in the `warm_lights`
group; `scripts/lighting/light_registry.gd` (`LightRegistry`) enumerates and
scales the set for the Phase 11 brownout.
