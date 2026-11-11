#!/usr/bin/env python3
"""Reject a nextpnr smoke build without constrained, passing system timing."""

import argparse
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--min-mhz", type=float, default=27)
    parser.add_argument("--expect-mhz", type=float, action="append", default=[])
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    clocks = report["fmax"]
    if not clocks:
        parser.error("No clock timing was reported")
    if args.expect_mhz:
        actual = sorted(clock["constraint"] for clock in clocks.values())
        expected = sorted(args.expect_mhz)
        if len(actual) != len(expected) or any(
                not math.isclose(a, e, rel_tol=0.0001) for a, e in zip(actual, expected)):
            parser.error(f"Missing/unexpected clock constraints: {actual}; expected {expected}")
    for name, clock in clocks.items():
        achieved = clock["achieved"]
        constraint = clock["constraint"]
        if not (math.isfinite(achieved) and math.isfinite(constraint)
                and math.isfinite(args.min_mhz) and args.min_mhz > 0
                and constraint >= args.min_mhz and achieved >= constraint):
            parser.error(f"Timing failure: {name}: {clock}")
        print(f"{name}: {achieved:.2f} MHz, requirement {constraint:.2f} MHz")
    for name, resource in report["utilization"].items():
        if name == "IOLOGIC_DUMMY" and resource["available"] == 0:
            print(f"{name}: {resource['used']} serializer placement placeholders (not fabric capacity)")
            continue
        if resource["used"] > resource["available"]:
            parser.error(f"Resource overflow: {name}: {resource}")
    print("PASS: smoke-build clock timing and resource limits (not release hold sign-off)")


if __name__ == "__main__":
    main()
