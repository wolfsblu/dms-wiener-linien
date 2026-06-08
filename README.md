# dms-wiener-linien

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin that shows real-time
Wiener Linien departure times on the DankBar.

## Features

- Bar pill showing the next 1–2 departures per tracked stop as coloured line
  badges (`U3 2′  4A 7′`), updated on a configurable interval.
- Popout with a full departure board: all tracked stops, sorted metro → tram →
  bus → night bus, with next three countdowns and a barrier-free indicator.
- Station picker in settings: type-to-filter across all 1 700+ Wiener Linien
  stops, click to add, click the × to remove.
- Automatic 5-minute backoff when the API rate limit is hit, with a human-readable
  status message instead of a raw error code.

## Requirements

- DankMaterialShell with Quickshell ≥ 0.3.0.

No additional tools or credentials. The Wiener Linien Realtime API is open and
unauthenticated.

## Installing

Clone the repo into the DMS plugins directory and enable it under
Settings → Plugins:

```sh
git clone https://github.com/Klievan/dms-wiener-linien \
    ~/.config/DankMaterialShell/plugins/dms-wiener-linien
```

For development, symlink instead:

```sh
ln -s ~/Projects/dms-wiener-linien \
    ~/.config/DankMaterialShell/plugins/dms-wiener-linien
```

After edits, reload without restarting DMS:

```sh
dms ipc call plugins reload wienerLinien
```

With Nix / home-manager:

```nix
xdg.configFile."DankMaterialShell/plugins/dms-wiener-linien".source =
  ./dms-wiener-linien;
```

## Configuration

Settings → Plugins → Wiener Linien:

- **Tracked stations**: search by name, click to add. Stops are queried in a
  single batched API call per poll cycle.
- **Poll interval**: 30 s / 1 min / 2 min / 5 min (default 1 min). The Wiener
  Linien API asks that clients do not poll more than once every 15 seconds; the
  plugin enforces this as a hard floor regardless of the chosen interval.

## Updating station data

The station search is powered by a bundled static file (`data/stations.js`)
generated from the [Wiener Linien OGD open data](https://www.wienerlinien.at/ogd_realtime/doku/).
To refresh it, download the three CSVs and run the script:

```sh
# Download
curl -O https://data.wien.gv.at/csv/wienerlinien-ogd-haltestellen.csv
curl -O https://data.wien.gv.at/csv/wienerlinien-ogd-steige.csv
curl -O https://data.wien.gv.at/csv/wienerlinien-ogd-linien.csv

# Regenerate
python3 scripts/generate_stations.py \
    wienerlinien-ogd-haltestellen.csv \
    wienerlinien-ogd-steige.csv \
    wienerlinien-ogd-linien.csv
```

## API

Uses the [Wiener Linien Realtime API v1.5](https://www.wienerlinien.at/ogd_realtime/doku/):

```
GET http://www.wienerlinien.at/ogd_realtime/monitor?stopId=<rbl>&stopId=<rbl>…
```

No API key required. Multiple stop IDs are batched into one request per poll.

## License

MIT. See [LICENSE](LICENSE).
