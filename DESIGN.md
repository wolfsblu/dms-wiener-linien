# DMS Public Transit Tracker — design notes

A DankMaterialShell plugin that shows real-time departure times for selected
Wiener Linien stops on the DankBar.

## Where the code lives

DMS discovers plugins by scanning `~/.config/DankMaterialShell/plugins/`.
Each plugin is one directory.

```
~/.config/DankMaterialShell/plugins/dms-wiener-linien/
├── plugin.json                  # manifest
├── PublicTransit.qml            # bar widget + popout (PluginComponent)
├── PublicTransitSettings.qml    # settings UI (PluginSettings)
├── WienerLinienClient.qml       # HTTP wrapper around the realtime API
├── data/
│   └── stations.json            # static station lookup (name → stopId)
└── assets/
    └── transit.svg
```

Recommended workflow:

- Develop in a standalone git repo and symlink:
  `ln -s ~/Projects/dms-wiener-linien ~/.config/DankMaterialShell/plugins/dms-wiener-linien`
- Hot reload with `dms ipc call plugins reload publicTransit` — no shell restart.
- Once stable, declaratively install via `xdg.configFile."DankMaterialShell/plugins/dms-wiener-linien".source = ./dms-wiener-linien;`
  in a home-manager module. State lives at
  `~/.local/state/DankMaterialShell/publicTransitTracker_state.json`.

## plugin.json

```json
{
  "id": "publicTransitTracker",
  "name": "Public Transit Tracker",
  "description": "Track departure times of public transit",
  "version": "0.2.0",
  "author": "Lukas Wolfsberger",
  "type": "widget",
  "component": "./PublicTransit.qml",
  "settings": "./PublicTransitSettings.qml",
  "permissions": ["network", "settings_read", "settings_write"]
}
```

`network` is required for the realtime API calls. `process` is not needed
(no `xdg-open` required for this plugin).

## Wiener Linien Realtime API

**Base URL:** `http://www.wienerlinien.at/ogd_realtime/`

**Endpoint used:** `monitor?stopId=<id>&stopId=<id>...`

GET request, response is JSON. Multiple stopIds can be stacked in one call.
The response delivers the next ~70 min of departures per stop.

### Key response fields

```
data.monitors[].locationStop.properties.title      — station display name
data.monitors[].locationStop.properties.name       — DIVA number (internal)
data.monitors[].locationStop.properties.attributes.rbl  — RBL (= stopId)
data.monitors[].lines[].name                       — line name ("U3", "13A", "D")
data.monitors[].lines[].towards                    — destination name
data.monitors[].lines[].type                       — vehicle type (see below)
data.monitors[].lines[].departures.departure[].departureTime.countdown  — minutes
data.monitors[].lines[].departures.departure[].departureTime.timeReal   — ISO datetime
data.monitors[].lines[].departures.departure[].departureTime.timePlanned
```

### Vehicle types

| `type` value   | Meaning          |
|----------------|------------------|
| `ptMetro`      | U-Bahn           |
| `ptTram`       | Straßenbahn      |
| `ptBus`        | Bus              |
| `ptBusNight`   | Nightline bus    |

### Error codes

| Code | Meaning                      |
|------|------------------------------|
| 311  | DB unavailable               |
| 312  | Stop does not exist          |
| 316  | Query limit reached          |
| 320  | Invalid GET parameter        |
| 321  | Missing GET parameter        |
| 322  | No data in DB                |

## Station search (settings UI)

The realtime API has no station search endpoint — it only accepts numeric
`stopId`. Station search is solved by bundling a static lookup file:

**`data/stations.json`** — derived from the Wiener Linien OGD Haltestellen
CSV (open data, updated periodically by Wiener Linien). Format:

```json
[
  { "name": "Karlsplatz", "stopId": 60200773, "lines": ["U1","U2","U4"] },
  { "name": "Stephansplatz", "stopId": 60200660, "lines": ["U1","U3"] }
]
```

The settings UI filters this list client-side as the user types. No network
call for search. When the bundled data grows stale, the user can still
manually enter a stopId as a fallback.

## Settings UI (`PublicTransitSettings.qml`)

1. **Search field** — type-to-filter against `stations.json` by station name
2. **Search results list** — shows matching stations with their line names;
   tap/click to add to tracked list
3. **Tracked stations list** — ordered list of selected stations; reorder
   via drag-handle, remove via × button
4. **Poll interval** — slider or text field (default 60 s, minimum 30 s)

Settings are persisted via `pluginData` (DMS settings API).

## Bar widget (`PublicTransit.qml`)

### Compact bar row

One line in the DankBar, reading left to right. For each tracked station show
the next 2 departures across all lines, as inline chips:

```
Karlsplatz  [U1] 3′  [U4] 7′  ·  Schwedenplatz  [U4] 2′  [2] 5′
```

- Station name as plain text label
- Each departure as a colored pill: `[line] Xmin`
- Stations separated by a centre-dot `·`
- If no departure data yet (first load): show `—`
- If API returns an error for a stop: show a warning icon next to that station

### Line badge colors

Colors match the official Vienna transit color scheme:

| Line(s)        | Color         |
|----------------|---------------|
| U1             | `#e2001a` red |
| U2             | `#9b2f83` purple |
| U3             | `#f47d00` orange |
| U4             | `#006f3c` green |
| U6             | `#9b6b34` brown |
| Tram (all)     | `#e2001a` red |
| Bus            | `#1d5a96` blue |
| Nightline      | `#22375b` dark blue |

Line name is rendered as white text on the colored background.

### Popout panel

Clicking the bar widget opens a popout with full departure boards:

- One section per tracked station (station name as header)
- One row per line: `[badge] Line  →  Destination   3 min  /  17:42`
  - Shows both countdown and absolute time
  - `timeReal` when available, else `timePlanned`
- Lines sorted: metros first, then trams, then buses
- If `barrierFree: true` on a departure, show a small wheelchair icon

## Data flow

```
Settings (pluginData)
  └─ trackedStops: [ { name, stopId }, ... ]
  └─ pollInterval: 60

Timer (pollInterval)
  └─ WienerLinienClient.fetchMonitor(stopIds[])
       └─ GET /monitor?stopId=A&stopId=B
       └─ parse → DepartureModel []
            └─ bar widget re-renders
            └─ pluginService.savePluginState({ lastFetch, cache })
```

All stopIds for tracked stations are batched into a single API call per poll
cycle to minimise requests. The API supports multiple `stopId` parameters.

## State vs settings

- **Settings** (`pluginData`, user-edited): `trackedStops[]`, `pollInterval`
- **State** (`pluginService.savePluginState`): `lastFetch` timestamp,
  `departures` cache (shown immediately on next load before first poll)

## Notifications

Not planned for the initial version. The bar widget always shows live data;
a notification threshold (e.g. "alert when next U3 < 2 min") can be added
later via `dms ipc call notifications send`.
