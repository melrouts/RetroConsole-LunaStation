#!/usr/bin/env python3
"""Local browser keyboard -> USB-UART button masks; FPGA releases keys after 250 ms."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time

import serial
from serial_update import upload, validate_image


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--listen-port", type=int, default=8769)
    args = parser.parse_args()
    html = (ROOT / "tools/keyboard.html").read_bytes()
    origin = f"http://127.0.0.1:{args.listen_port}"
    lock = threading.Lock()
    serial_lock = threading.Lock()
    stop = threading.Event()
    state = {"report": "Waiting for board UART", "updated": 0.0, "connected": True,
             "sequence": -1, "mask": 0, "updating": False, "update_result": ""}
    with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=0.2, exclusive=True) as port:
        port.reset_input_buffer()

        def receive():
            pending = bytearray()
            try:
                while not stop.is_set():
                    with serial_lock:
                        with lock:
                            updating = state["updating"]
                        if updating:
                            pending.clear()
                        else:
                            pending.extend(port.read(256))
                    if updating:
                        time.sleep(0.05)
                        continue
                    while b"\n" in pending:
                        line, _, rest = pending.partition(b"\n")
                        pending = bytearray(rest)
                        message = line.rstrip(b"\r").decode("ascii", errors="replace")
                        with lock:
                            state["report"] = message
                            state["updated"] = time.monotonic()
                    if len(pending) > 1024:
                        raise ValueError("Board sent an overlong UART status line")
            except (serial.SerialException, OSError, ValueError) as error:
                with lock:
                    state["connected"] = False
                    state["report"] = f"UART error: {error}"
                print(state["report"], flush=True)

        def update_game(image):
            def progress(message):
                with lock:
                    state["update_result"] = message
            with serial_lock:
                try:
                    upload(port, image, progress)
                except (serial.SerialException, OSError, RuntimeError, ValueError) as error:
                    progress(f"Ошибка обновления: {error}. Рабочий слот не заменяется без проверки.")
                    print(state["update_result"], flush=True)
                else:
                    with lock:
                        state["report"] = "PASS"
                        state["updated"] = time.monotonic()
                finally:
                    with lock:
                        state["updating"] = False

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/":
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", str(len(html)))
                    self.end_headers()
                    self.wfile.write(html)
                elif self.path == "/status":
                    with lock:
                        result = dict(state)
                    result["age"] = time.monotonic() - result["updated"] if result["updated"] else None
                    content = json.dumps(result).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", str(len(content)))
                    self.end_headers()
                    self.wfile.write(content)
                else:
                    self.send_error(404)

            def do_POST(self):
                if self.path not in ("/input", "/update") or self.headers.get("Origin") != origin:
                    self.send_error(403)
                    return
                if self.path == "/update":
                    try:
                        length = int(self.headers.get("Content-Length", "0"))
                        if not 36 <= length <= 7200:
                            raise ValueError("Invalid image size")
                        image = self.rfile.read(length)
                        validate_image(image)
                    except (ValueError, OSError) as error:
                        self.send_error(400, str(error))
                        return
                    with lock:
                        if state["updating"] or not state["connected"]:
                            self.send_error(409, "UART unavailable or update already running")
                            return
                        state["updating"] = True
                        state["mask"] = 0
                        state["update_result"] = "Начало обновления…"
                    threading.Thread(target=update_game, args=(image,), daemon=True).start()
                    self.send_response(202)
                    self.end_headers()
                    return
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= 128:
                        raise ValueError("Invalid request size")
                    data = json.loads(self.rfile.read(length))
                    mask, sequence = data["mask"], data["sequence"]
                    if type(mask) is not int or not 0 <= mask <= 15:
                        raise ValueError("Invalid button mask")
                    if type(sequence) is not int or not 0 <= sequence < 2**53:
                        raise ValueError("Invalid sequence")
                except (ValueError, KeyError, TypeError) as error:
                    self.send_error(400, str(error))
                    return
                with lock:
                    if state["updating"]:
                        self.send_error(423, "Game update in progress")
                        return
                    if not state["connected"]:
                        self.send_error(503, state["report"])
                        return
                    if sequence <= state["sequence"]:
                        self.send_error(409, "Stale button update")
                        return
                    try:
                        port.write(bytes([0x80 | mask]))
                    except (serial.SerialException, OSError) as error:
                        state["connected"] = False
                        state["report"] = f"UART write error: {error}"
                        self.send_error(503, state["report"])
                        print(state["report"], flush=True)
                        return
                    state["mask"] = mask
                    state["sequence"] = sequence
                self.send_response(204)
                self.end_headers()

            def log_message(self, format_string, *values):
                if len(values) < 2 or str(values[1]) not in ("200", "204"):
                    super().log_message(format_string, *values)

        server = ThreadingHTTPServer(("127.0.0.1", args.listen_port), Handler)
        origin = f"http://127.0.0.1:{server.server_port}"
        reader = threading.Thread(target=receive, daemon=True)
        reader.start()
        print(f"Keyboard bridge ready: {origin} -> {args.port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            stop.set()
            server.server_close()
            reader.join(timeout=1)
            if state["connected"]:
                port.write(b"\x80")


if __name__ == "__main__":
    main()
