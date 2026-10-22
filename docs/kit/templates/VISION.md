# <GAME> – vision (locked for the vertical slice)

Approved by: <designer>, <date>. Changes go through the decisions table only.

## Pitch and pillars
<two sentences>

1. <pillar>: <what the player feels; how we test it in the slice>
2. <pillar>
3. <pillar>

Non-goals for the slice: <list>

## Core loop with numbers
| Item | Value | Knob |
|---|---|---|
| Phase lengths | <build x min / fight y min> | `data/rounds/<id>.tres` |
| Win / lose | <...> | |
| Resources | <list; is there a soft currency? decide now> | |
| Start stock | <...> | |
| Population / workers | <in slice / deferred / never> | |
| Run length | <...> | |

## Reference games (one per dimension, frozen for the slice)
| Dimension | Reference | What we copy | What we don't |
|---|---|---|---|
| Camera | <e.g. SC2 / Anno / Manor Lords> | | |
| Selection and orders | | | |
| HUD layout | | | |
| Look | key art + `docs/ART_BIBLE.md` | | |
| Economy feel | | | |

## Genre conventions checklist
Mark each `slice`, `later` or `never`. Each item was a separate, late request in Felsenburg.

| Convention | Status |
|---|---|
| Camera: pan (keys, edge, drag), zoom, rotate, **tilt**, focus on selection | |
| Selection: click, box, **double-click = all visible of type**, triple-click = all of type, shift-add | |
| Control groups (set, recall, double-tap to jump) | |
| Orders: move, **attack-move**, stop, hold, patrol, rally point, waypoint queue | |
| Production: queue (max N), cancel, **stop production** (frees workers), repeat | |
| Range and area indicators: off by default, shown on selection or hover | |
| Feedback: click markers, attack cursor, health bars rule, alerts, minimap pings | |
| UI: fixed-size panels that never grow with their content, tooltips, hotkey labels | |
| Key profiles (e.g. classic and grid), rebinding | |
| Pause, game speed, save and load, settings (graphics, sound, keys) | |
| Tutorial or first-run hints | |
| Loading screen with progress | |
| Accessibility: UI scale, colour-blind safe team colours | |

## Target machine and budgets
- Target machine: <exact model, OS, GPU>; it is on hand for test runs: <yes/how>.
- Frame target: <30/60> fps locked at <resolution> on the <default> preset.
- Budgets (copied into `perf/budgets.json`): main thread ≤ <x> ms in the heaviest scene; tick ≤ <y> ms; GPU ≤ <z> ms;
  no frame > <n> ms outside loading; draws ≤ <d>; triangles ≤ <t> M.
- Scale: map <a × b m>; max units <n>; max enemies per wave <n> (the heavy perf scene uses 2×); animals <n>;
  props <n>.

## Fantasy-critical system
<The one system the fantasy needs (Felsenburg: villagers who haul and build). In the slice: yes/no. If no, it is a
non-goal, not a stub.>

## Decisions
Every switch is data or one constant. The designer can overrule; tracks use the default and never invent one.

| id | Question | Default | Knob | Owner | Status |
|---|---|---|---|---|---|
| D1 | <e.g. are walls walkable by units> | <yes> | `data/...` | <track> | locked |
