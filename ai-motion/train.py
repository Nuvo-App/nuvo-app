"""Reproducible starter dataset preparation for landmark-sequence training."""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def load_records(path: Path):
    records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    if not records:
        raise SystemExit("No training records found.")
    users = {record.get("user_id") for record in records}
    labels = {record.get("label") for record in records}
    if None in users or None in labels:
        raise SystemExit("Every record needs user_id and label.")
    if len(users) < 3:
        raise SystemExit("Need at least three distinct users before training.")
    if len(labels) < 2:
        raise SystemExit("Need at least two labels before training.")
    return records


def split_by_user(records):
    by_user = defaultdict(list)
    for record in records:
        by_user[record["user_id"]].append(record)
    users = sorted(by_user)
    test_users = set(users[::5]) or {users[-1]}
    test = [r for user in test_users for r in by_user[user]]
    train = [r for user in users if user not in test_users for r in by_user[user]]
    return train, test


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    records = load_records(args.input)
    train, test = split_by_user(records)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "dataset_manifest.json").write_text(json.dumps({
        "schemaVersion": 1,
        "trainRecords": len(train),
        "testRecords": len(test),
        "trainUsers": sorted({r["user_id"] for r in train}),
        "testUsers": sorted({r["user_id"] for r in test}),
        "labels": sorted({r["label"] for r in records}),
    }, indent=2) + "\n")
    print(f"Prepared {len(train)} train and {len(test)} test records.")
    print("Next step: run the pinned PyTorch training job in Vertex AI.")


if __name__ == "__main__":
    main()
