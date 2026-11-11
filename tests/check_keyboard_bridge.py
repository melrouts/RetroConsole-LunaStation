"""Integration checks with a pseudo-terminal; run using Python with pyserial installed."""
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
import zlib
import struct


ROOT = Path(__file__).resolve().parents[1]


class KeyboardBridgeTest(unittest.TestCase):
    def test_serial_http_validation_and_visible_disconnect(self):
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [sys.executable, "scripts/keyboard_bridge.py", "--port", os.ttyname(slave),
             "--listen-port", "0"], cwd=ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True)
        try:
            ready = process.stdout.readline()
            self.assertIn("Keyboard bridge ready:", ready)
            origin = ready.split(" -> ")[0].split(": ", 1)[1]

            def status():
                with urllib.request.urlopen(origin + "/status", timeout=2) as response:
                    return json.load(response)

            def post(mask, sequence, request_origin=origin):
                request = urllib.request.Request(origin + "/input", method="POST",
                    data=json.dumps({"mask": mask, "sequence": sequence}).encode(),
                    headers={"Origin": request_origin, "Content-Type": "application/json"})
                try:
                    with urllib.request.urlopen(request, timeout=2) as response:
                        return response.status
                except urllib.error.HTTPError as error:
                    error.close()
                    return error.code

            with urllib.request.urlopen(origin, timeout=2) as response:
                self.assertIn(b"keydown", response.read())
            os.write(master, b"PASS\r\n")
            for _ in range(30):
                if status()["report"] == "PASS":
                    break
                time.sleep(0.1)
            self.assertEqual(status()["report"], "PASS")
            self.assertEqual(post(3, 1), 204)
            self.assertTrue(select.select([master], [], [], 1)[0])
            self.assertEqual(os.read(master, 32), b"\x83")
            self.assertEqual(post(16, 2), 400)
            self.assertEqual(post(4, 0), 409)
            self.assertEqual(post(4, 2, "http://example.invalid"), 403)
            self.assertEqual(post(0, 2), 204)
            self.assertEqual(os.read(master, 32), b"\x80")

            def post_update(image, request_origin=origin):
                request = urllib.request.Request(origin + "/update", method="POST",
                    data=image, headers={"Origin": request_origin,
                                         "Content-Type": "application/octet-stream"})
                try:
                    with urllib.request.urlopen(request, timeout=3) as response:
                        return response.status
                except urllib.error.HTTPError as error:
                    code = error.code
                    error.close()
                    return code

            image = (ROOT / "build/images/LUNAR.BIN").read_bytes()
            self.assertEqual(post_update(b"invalid"), 400)
            self.assertEqual(post_update(image, "http://example.invalid"), 403)
            failures = []
            release = threading.Event()

            def board():
                def read_exact(count):
                    result = bytearray()
                    while len(result) < count:
                        if not select.select([master], [], [], 3)[0]:
                            raise TimeoutError("Host stopped sending update")
                        result.extend(os.read(master, count-len(result)))
                    return bytes(result)
                try:
                    self.assertEqual(read_exact(9), b"\x80LUNAUPD!")
                    self.assertTrue(release.wait(5))
                    os.write(master, b"READY LUP1\n")
                    self.assertEqual(read_exact(12),
                        struct.pack("<4sII", b"LUP1", len(image), zlib.crc32(image)))
                    os.write(master, b"SEND\n")
                    for index, offset in enumerate(range(0, len(image), 64)):
                        packet = struct.pack("<H", index) + image[offset:offset+64]
                        self.assertEqual(read_exact(len(packet)+4),
                            packet + struct.pack("<I", zlib.crc32(packet)))
                        os.write(master, b"ACK\n")
                    os.write(master, b"WRITE\nDONE\nPASS\nPASS\n")
                except Exception as error:
                    failures.append(error)

            virtual_board = threading.Thread(target=board, daemon=True)
            virtual_board.start()
            self.assertEqual(post_update(image), 202)
            self.assertTrue(status()["updating"])
            self.assertEqual(post(4, 3), 423)
            self.assertEqual(post_update(image), 409)
            release.set()
            virtual_board.join(timeout=10)
            self.assertFalse(virtual_board.is_alive())
            if failures:
                raise failures[0]
            for _ in range(50):
                if not status()["updating"]:
                    break
                time.sleep(0.1)
            self.assertFalse(status()["updating"])
            self.assertIn("перезапущена: PASS", status()["update_result"])
            os.close(master)
            master = None
            for _ in range(30):
                if not status()["connected"]:
                    break
                time.sleep(0.1)
            self.assertFalse(status()["connected"])
            self.assertIn("UART error:", status()["report"])
            self.assertEqual(post(2, 3), 503)
        finally:
            process.terminate()
            process.communicate(timeout=5)
            if master is not None:
                os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main()
