#!/usr/bin/env python3
"""
Generate data/stations.js from Wiener Linien OGD open data CSVs.

Download the four CSV files from https://www.wienerlinien.at/ogd_realtime/doku/
(the ogd/ directory also links wienerlinien_ogd_Beschreibung.pdf describing them):

  https://www.wienerlinien.at/ogd_realtime/doku/ogd/wienerlinien-ogd-haltestellen.csv
  https://www.wienerlinien.at/ogd_realtime/doku/ogd/wienerlinien-ogd-haltepunkte.csv
  https://www.wienerlinien.at/ogd_realtime/doku/ogd/wienerlinien-ogd-linien.csv
  https://www.wienerlinien.at/ogd_realtime/doku/ogd/wienerlinien-ogd-fahrwegverlaeufe.csv

Usage:
  python3 scripts/generate_stations.py \\
      haltestellen.csv haltepunkte.csv linien.csv fahrwegverlaeufe.csv

Joins (schema changed in ~2026, see wienerlinien_ogd_Beschreibung.pdf):
  haltestellen.DIVA        -> station name (PlatformText)
  haltepunkte.StopID       -> RBL number used by the realtime monitor API
  haltepunkte.DIVA         -> station each RBL belongs to
  linien.LineID            -> line name (LineText)
  fahrwegverlaeufe         -> which LineID serves which StopID

Output: data/stations.js  (QML .pragma library module)
"""

import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

def load_csv(path):
    with open(path, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, delimiter=";"))

def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)

    haltestellen_path, haltepunkte_path, linien_path, fahrweg_path = sys.argv[1:]

    # LINIEN_ID -> line name (e.g. "U3", "13A")
    line_names = {}
    for row in load_csv(linien_path):
        lid = row.get("LineID", "").strip()
        name = row.get("LineText", "").strip()
        if lid and name:
            line_names[lid] = name

    # DIVA -> station name
    station_names = {}
    for row in load_csv(haltestellen_path):
        diva = row.get("DIVA", "").strip()
        name = row.get("PlatformText", "").strip()
        if diva and name:
            station_names[diva] = name

    # StopID (RBL) -> station DIVA
    stop_diva = {}
    for row in load_csv(haltepunkte_path):
        sid = row.get("StopID", "").strip()
        diva = row.get("DIVA", "").strip()
        if sid and diva:
            try:
                stop_diva[sid] = diva
            except ValueError:
                pass

    # Group RBLs and line names by station
    station_rbls  = defaultdict(set)
    station_lines = defaultdict(set)
    for sid, diva in stop_diva.items():
        station_rbls[diva].add(int(sid))
    for row in load_csv(fahrweg_path):
        lid = row.get("LineID", "").strip()
        sid = row.get("StopID", "").strip()
        diva = stop_diva.get(sid)
        if diva and lid in line_names:
            station_lines[diva].add(line_names[lid])

    # Build sorted station list (skip stations without any stop point)
    stations = []
    for diva, name in sorted(station_names.items(), key=lambda x: x[1]):
        if diva not in station_rbls:
            continue
        stations.append({
            "name": name,
            "stopIds": sorted(station_rbls[diva]),
            "lines": sorted(station_lines[diva]),
        })

    out = Path(__file__).parent.parent / "data" / "stations.js"
    with open(out, "w", encoding="utf-8") as f:
        f.write(".pragma library\nvar stations = ")
        json.dump(stations, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")

    print(f"Written {len(stations)} stations \u2192 {out}")

if __name__ == "__main__":
    main()
