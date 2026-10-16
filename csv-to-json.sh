#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s INPUT.csv [OUTPUT.json]\n' "${0##*/}" >&2
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 2
fi

input=$1
if (( $# == 2 )); then
  output=$2
else
  output=${input%.*}.json
fi

if [[ ! -f $input ]]; then
  printf 'Error: input file not found: %s\n' "$input" >&2
  exit 1
fi

python3 - "$input" "$output" <<'PY'
import csv
import json
import sys

input_path, output_path = sys.argv[1:]

with open(input_path, "r", encoding="utf-8-sig", newline="") as csv_file:
    reader = csv.DictReader(csv_file)
    if reader.fieldnames is None:
        raise SystemExit("Error: CSV file is empty or has no header row")
    if any(name is None or name == "" for name in reader.fieldnames):
        raise SystemExit("Error: CSV header contains an empty column name")

    rows = list(reader)

with open(output_path, "w", encoding="utf-8") as json_file:
    json.dump(rows, json_file, ensure_ascii=False, indent=2)
    json_file.write("\n")
PY
