#!/usr/bin/env python3
"""
Generate data/stations.js from Wiener Linien OGD open data CSVs.

Download the three CSV files from:
  https://data.wien.gv.at/csv/wienerlinien-ogd-haltestellen.csv
  https://data.wien.gv.at/csv/wienerlinien-ogd-steige.csv
  https://data.wien.gv.at/csv/wienerlinien-ogd-linien.csv

Usage:
  python3 scripts/generate_stations.py \\
      haltestellen.csv steige.csv linien.csv

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
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    haltestellen_path, steige_path, linien_path = sys.argv[1:]

    # LINIEN_ID -> line name (e.g. "U3", "13A")
    line_names = {}
    for row in load_csv(linien_path):
        lid = row.get("LINIEN_ID", "").strip()
        name = row.get("BEZEICHNUNG", "").strip()
        if lid and name:
            line_names[lid] = name

    # HALTESTELLEN_ID -> station name
    station_names = {}
    for row in load_csv(haltestellen_path):
        hid = row.get("HALTESTELLEN_ID", "").strip()
        name = row.get("NAME", "").strip()
        if hid and name:
            station_names[hid] = name

    # Group RBL numbers and line names by station
    station_rbls  = defaultdict(set)
    station_lines = defaultdict(set)
    for row in load_csv(steige_path):
        hid = row.get("FK_HALTESTELLEN_ID", "").strip()
        rbl = row.get("RBL_NUMMER", "").strip()
        lid = row.get("FK_LINIEN_ID", "").strip()
        if hid and rbl:
            try:
                station_rbls[hid].add(int(rbl))
            except ValueError:
                pass
        if hid and lid in line_names:
            station_lines[hid].add(line_names[lid])

    # Build sorted station list (skip stations with no RBL/stop point)
    stations = []
    for hid, name in sorted(station_names.items(), key=lambda x: x[1]):
        if hid not in station_rbls:
            continue
        stations.append({
            "name": name,
            "stopIds": sorted(station_rbls[hid]),
            "lines": sorted(station_lines[hid]),
        })

    out = Path(__file__).parent.parent / "data" / "stations.js"
    with open(out, "w", encoding="utf-8") as f:
        f.write(".pragma library\nvar stations = ")
        json.dump(stations, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")

    print(f"Written {len(stations)} stations → {out}")

if __name__ == "__main__":
    main()
