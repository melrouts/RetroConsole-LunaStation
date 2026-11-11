#!/usr/bin/env python3
"""Load a diagnostic design into SRAM, check UART, and normally reload flash."""

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

import serial


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--loader", default="openFPGALoader")
    parser.add_argument("--bitstream", type=Path, default=Path("build/smoke.fs"))
    parser.add_argument("--report", type=Path, default=Path("build/board-check.json"))
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave successful SRAM design running for monitor inspection")
    parser.add_argument("--boot-settle-seconds", type=float, default=0,
                        help="Additional startup time before checking fresh reports (SD slot CRC scan)")
    args = parser.parse_args()
    if not 0 <= args.boot_settle_seconds <= 30:
        parser.error("--boot-settle-seconds must be between 0 and 30")
    if not args.bitstream.is_file():
        parser.error(f"Missing bitstream: {args.bitstream}")
    result = {
        "port": args.port, "sram_only": True, "pass_reports": 0,
        "bitstream_sha256": hashlib.sha256(args.bitstream.read_bytes()).hexdigest(),
        "restored_from_flash": False,
        "left_running": False,
        "boot_settle_seconds": args.boot_settle_seconds,
    }
    try:
        with serial.Serial(args.port, 115200, timeout=0.2, exclusive=True) as port:
            port.reset_input_buffer()
            try:
                subprocess.run(
                    [args.loader, "-b", "tangnano9k", "--write-sram", str(args.bitstream)],
                    check=True, timeout=60,
                )
                # The previous SRAM design may transmit while JTAG parses/loads the file.
                port.reset_input_buffer()
                time.sleep(0.5 + args.boot_settle_seconds)
                port.reset_input_buffer()
                deadline = time.monotonic() + 8
                received = bytearray()
                while time.monotonic() < deadline and result["pass_reports"] < 2:
                    received.extend(port.read(256))
                    result["pass_reports"] = received.count(b"PASS\r\n")
                    if b"FAIL\r\n" in received:
                        raise RuntimeError("The diagnostic design reported FAIL")
                if result["pass_reports"] < 2:
                    raise TimeoutError("Did not receive two PASS reports within 8 seconds")
                result["left_running"] = args.keep_running
            finally:
                if not result["left_running"]:
                    subprocess.run(
                        [args.loader, "-b", "tangnano9k", "--reset"], check=True, timeout=30
                    )
                    result["restored_from_flash"] = True
    finally:
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    state = "SRAM diagnostic left running" if result["left_running"] else "JTAG reload from flash succeeded"
    print(f"PASS: two diagnostic UART reports; {state}")


if __name__ == "__main__":
    main()
