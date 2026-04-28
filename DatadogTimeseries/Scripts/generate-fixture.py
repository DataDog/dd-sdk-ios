#!/usr/bin/env python3
# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------
"""
Generates a realistic 60-sample CSV fixture for DatadogTimeseries tests.

Output: Tests/DatadogTimeseriesTests/Fixtures/input_realistic_60s.csv

CSV format: timestamp,metric,value
- 60 seconds of data (t=1 to t=60), interleaved memory then cpu per second
- 120 data rows total + 1 header row

Memory shape:
- Base: 31_000_000 bytes (~31MB)
- Slow drift: deterministic +500..+2000 bytes/s (cycle of 8 fixed offsets)
- Allocation jumps at t=12 (+1_500_000), t=30 (+2_000_000), t=50 (+1_000_000)
- Deallocation at t=40 (-800_000)

CPU shape:
- Baseline: cycling through [5.0, 7.5, 6.0, 8.5, 5.5, 9.0]
- Burst at t=15..17: [65.0, 72.0, 58.0]
- Burst at t=35..37: [80.0, 75.0, 68.0]
- Burst at t=55..57: [55.0, 62.0, 50.0]
"""

import os

BASE_TIMESTAMP = 1700000001000000000
NS_PER_SECOND = 1_000_000_000

OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Tests", "DatadogTimeseriesTests", "Fixtures", "input_realistic_60s.csv"
)

# Deterministic per-second drift values (cycle of 8, repeating)
DRIFT_CYCLE = [500, 800, 1200, 1500, 700, 1000, 2000, 600]

# Allocation events: {second -> delta}
ALLOC_EVENTS = {
    12: +1_500_000,
    30: +2_000_000,
    40: -800_000,
    50: +1_000_000,
}

# CPU baseline cycling values
CPU_BASELINE = [5.0, 7.5, 6.0, 8.5, 5.5, 9.0]

# CPU burst overrides: {second -> value}
CPU_BURSTS = {
    15: 65.0,
    16: 72.0,
    17: 58.0,
    35: 80.0,
    36: 75.0,
    37: 68.0,
    55: 55.0,
    56: 62.0,
    57: 50.0,
}


def generate_rows():
    rows = []
    memory = 31_000_000
    baseline_index = 0

    for i, second in enumerate(range(1, 61)):
        timestamp = BASE_TIMESTAMP + (second - 1) * NS_PER_SECOND

        # --- Memory ---
        drift = DRIFT_CYCLE[i % len(DRIFT_CYCLE)]
        memory += drift
        if second in ALLOC_EVENTS:
            memory += ALLOC_EVENTS[second]
        rows.append((timestamp, "memory_usage", memory))

        # --- CPU ---
        if second in CPU_BURSTS:
            cpu = CPU_BURSTS[second]
        else:
            cpu = CPU_BASELINE[baseline_index % len(CPU_BASELINE)]
            baseline_index += 1

        # Format cpu: no trailing zeros for whole numbers, keep one decimal otherwise
        if cpu == int(cpu):
            cpu_str = f"{int(cpu)}.0"
        else:
            cpu_str = str(cpu)

        rows.append((timestamp, "cpu_usage", cpu_str))

    return rows


def main():
    rows = generate_rows()

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    with open(OUTPUT_PATH, "w") as f:
        f.write("timestamp,metric,value\n")
        for timestamp, metric, value in rows:
            f.write(f"{timestamp},{metric},{value}\n")

    data_rows = len(rows)
    print(f"Generated: {OUTPUT_PATH}")
    print(f"Data rows: {data_rows} (expected 120)")

    # Quick sanity check on first few rows
    print("\nFirst 6 rows:")
    for row in rows[:6]:
        print(f"  {row[0]},{row[1]},{row[2]}")


if __name__ == "__main__":
    main()
