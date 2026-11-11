"""Host protocol checks without requiring pyserial or hardware."""
from collections import deque
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from game_image import pack
from serial_update import line_until, upload


class Board:
    def __init__(self, image, failure=None):
        self.image = image
        self.failure = failure
        self.pending = deque()
        self.writes = []
        self.blocks = 0

    def read(self, count):
        return self.pending.popleft() if self.pending else b""

    def flush(self):
        pass

    def reset_input_buffer(self):
        self.pending.clear()

    def reply(self, text):
        self.pending.extend(bytes([byte]) for byte in text)

    def write(self, data):
        self.writes.append(data)
        if data == b"\x80":
            return
        if data == b"LUNAUPD!":
            self.reply(b"ERR slots\n" if self.failure == "slots" else b"READY LUP1\n")
        elif data.startswith(b"LUP1"):
            assert struct.unpack("<4sII", data) == (
                b"LUP1", len(self.image), zlib.crc32(self.image))
            self.reply(b"SEND\n")
        else:
            packet, crc = data[:-4], data[-4:]
            assert struct.unpack("<I", crc)[0] == zlib.crc32(packet)
            assert struct.unpack("<H", packet[:2])[0] == self.blocks
            assert packet[2:] == self.image[self.blocks*64:(self.blocks+1)*64]
            self.blocks += 1
            if self.failure == "block":
                self.reply(b"ERR block\n")
                return
            self.reply(b"ACK\n")
            if self.blocks*64 >= len(self.image):
                self.reply(b"WRITE\n")
                if self.failure == "write":
                    self.reply(b"ERR write\n")
                else:
                    self.reply(b"DONE\nPASS\n")
                    if self.failure != "reboot":
                        self.reply(b"PASS\n")


class SerialUpdateTest(unittest.TestCase):
    def setUp(self):
        self.image = pack(bytes(range(128)), ram_bytes=8192, stack_bytes=1024, abi=1)

    def test_packet_crc_pacing_commit_and_fresh_boot(self):
        board = Board(self.image)
        progress = []
        upload(board, self.image, progress.append)
        self.assertEqual(board.blocks, 3)
        self.assertIn("PASS", progress[-1])
        self.assertFalse(board.pending)

    def test_explicit_errors_never_report_success(self):
        for failure in ("slots", "block", "write"):
            with self.subTest(failure=failure):
                progress = []
                with self.assertRaisesRegex(RuntimeError, f"ERR {failure}"):
                    upload(Board(self.image, failure), self.image, progress.append)
                self.assertFalse(any("перезапущена: PASS" in message for message in progress))

    def test_invalid_image_does_not_touch_uart(self):
        board = Board(self.image)
        with self.assertRaises(ValueError):
            upload(board, b"not a LUNA image")
        self.assertEqual(board.writes, [])

    def test_timeout_and_overlong_response(self):
        board = Board(self.image)
        with patch("serial_update.time.monotonic", side_effect=[0, 0, 2]):
            with self.assertRaises(TimeoutError):
                line_until(board, b"PASS", 1)
        board.reply(b"x"*1025)
        with self.assertRaisesRegex(RuntimeError, "Overlong"):
            line_until(board, b"PASS", 1)

    def test_done_alone_is_not_success(self):
        board = Board(self.image, "reboot")
        clock = iter(range(10000))
        with patch("serial_update.time.monotonic", side_effect=lambda: next(clock)*0.01):
            with self.assertRaises(TimeoutError):
                upload(board, self.image)


if __name__ == "__main__":
    unittest.main()
