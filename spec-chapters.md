# Chapters as content — Ziggy's chapter layer

Right now the chapter *is* the code. The brownout is a director node, closing
time is another, the room is a scene. There is one chapter and it is welded in.

Make a chapter a **JSON file**, so anyone can write one — and so writing one
goes through the same gate, the same branch and the same ownership rules that
already govern dialogue.

**Standalone by default. Entry conditions optional.**

---

## Why this shape

Five people are going to write chapters for the same bar. Forcing an order
means five contributors negotiating a sequence before anyone can add anything.
So every chapter is a self-contained evening at Ziggy's, and a chapter that
*wants* continuity can declare it — nothing else has to care.

The hard boundary, which is the whole safety story:

- **A chapter reusing the bar is DATA.** Anyone can write one. It cannot
  execute anything, because every beat it can ask for is a kind the engine
  already implements.
- **A chapter needing a new room is CODE.** That stays a reviewed pull
  request, and is out of scope here.

If a chapter file could introduce new behaviour, this whole thing would be
"run a stranger's script" wearing a JSON hat. It cannot, and it must not.

---

## The format

`content/chapters/<id>.json`, validated by `content/chapters/chapter.schema.json`.

```json
{
  "schema_version": 1,
  "id": "the-morning-after",
  "title": "The Morning After",
  "author": "oleg",
  "summary": "The lights are back. Nobody has gone home.",

  "requires": [
    { "flag": "ziggys_chapter_zero.closing_decision", "equals": "organize" }
  ],

  "cast": ["caroline", "oleg", "tonya", "grant"],

  "beats": [
    { "id": "settle",   "kind": "ambience", "preset": "warm" },
    { "id": "the_call", "kind": "lighting", "preset": "brownout",
      "after": { "conversations": 3 } },
    { "id": "decide",   "kind": "decision", "npc": "caroline",
      "after": { "conversations": 3, "since": "the_call" },
      "writes": "ziggys.the-morning-after.decision",
      "choices": ["stay_open", "call_it", "split_the_tab", "wait"] }
  ]
}
```

**`requires` is optional and defaults to empty** — an absent `requires` is a
chapter anyone can start at any time. That is the common case and must be the
easy one to write.

**`beat.kind` is a CLOSED set.** Ship exactly these, and refuse any other value
at validation:

| kind | does |
|---|---|
| `ambience` | switch the room's lighting/audio preset (`warm`, `cold`, `dark`) |
| `lighting` | run a named lighting beat — `brownout` is the one that exists |
| `dialogue` | make a named NPC say a line from their existing file |
| `decision` | an NPC asks; the answer is recorded as a flag |
| `end` | the chapter is over |

A chapter cannot add a kind. New kinds are engine work, deliberately.

**`after` is the trigger**, and it mirrors what already works: a count of
distinct conversations, optionally counted since a named beat. `on_start` if
absent.

---

## What the engine must do

1. **Load and validate** every `content/chapters/*.json` at boot, the way
   `DialogueDB` already loads dialogue. One bad chapter must not take the
   others down — report it and carry on.
2. **Offer the playable ones.** A chapter select listing every chapter whose
   `requires` are satisfied by the current save. Unmet ones are visible but
   greyed with the reason ("needs: you organised, last time"), never hidden —
   a contributor must be able to see why their chapter is not offered.
3. **Run the beats in order**, honouring `after`. The existing brownout and
   closing-time directors become implementations of the `lighting` and
   `decision` kinds rather than hardcoded sequences.
4. **Write flags** namespaced per chapter, exactly as
   `ziggys_chapter_zero.*` already is.
5. **Cast**: only the named NPCs are present in the room. The rest are absent.

---

## Chapter Zero proves the format

**Convert the existing chapter to a data file and delete the hardcoded path.**
This is the acceptance test that matters: if Chapter Zero cannot be expressed
in this format and play identically — same brownout, same four-way decision,
same save keys — the format is wrong and no amount of new chapters fixes that.

It also means every contributor's chapter runs the same code the shipped one
does, rather than a second-class path that rots.

---

## Contribution path

`content/chapters/` joins `content/dialogue/` on the allow-list in
`lib/game-contrib.js` (the `content-only` gate step), and the chapter validator
joins the gate. Nothing else about contributing changes: same branch naming,
same commit attribution, same revert-on-failure.

---

## Acceptance

1. Chapter Zero, as data, plays identically — brownout, decision, save keys.
2. A second chapter with no `requires` appears in chapter select on a fresh
   save and is playable.
3. A chapter with unmet `requires` is listed, greyed, and **states its reason**.
4. A chapter naming an NPC with no dialogue file fails validation with that
   NPC named — not a crash at runtime.
5. An unknown `beat.kind` fails validation naming the kind and the file.
6. A malformed chapter does not prevent the others from loading.
7. Decisions write namespaced flags that survive save/load.
8. `godot --headless --path . --import` stays clean, and the existing 34
   probes still pass.
9. A new probe validates every chapter file, so the contribution gate can
   call it.

---

## Traps

- **`--headless` cannot render.** It uses a dummy renderer: no GPU context,
  and `--write-movie` writes a stub that looks like success. Import checks and
  script parsing run headless; anything producing a picture must run windowed.
- **Start must reset the run.** A completed save currently leaks into a new
  run (fixed in `title_screen.gd`) — chapter select must not reintroduce it.
  Entering a chapter resets that chapter's state, never another's.
- **The room is sealed.** A `DoorwayBlocker` exists because the player could
  walk out of the world. Cast changes must not remove it.
- **Keep the bake discipline.** CSG scenes are authoring; the shipped room
  instances baked `MeshInstance3D`. Do not reintroduce live CSG.
- **One bad file must never take the layer down.** The dialogue loader's
  habits apply: a missing field means "no match", never a crash.
- **Do not touch the save format's existing keys.** Chapter Zero's three keys
  are already namespaced and a shipped save must keep loading.

---

## Explicitly NOT in scope

- New rooms, geometry, props or lighting presets from a chapter file. Code.
- A prop catalog or declarative `room.json` — that is the later tier in
  `chapter-bundle-spec.md`.
- Branching within a chapter beyond the single decision beat.
- Multiplayer, gestures, voice. Separate specs.
