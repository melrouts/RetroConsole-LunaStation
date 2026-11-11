import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class BoardCheckTest(unittest.TestCase):
    def run_check(self, messages, keep=False, settle=0):
        events = []
        iterator = iter(messages)

        class Port:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def reset_input_buffer(self):
                events.append("flush")

            def read(self, _size):
                events.append("read")
                return next(iterator)

        serial = types.SimpleNamespace(Serial=lambda *_args, **_kwargs: Port())
        spec = importlib.util.spec_from_file_location("board_check_test", ROOT / "scripts/check_board.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"serial": serial}):
            spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            bitstream = Path(temporary) / "test.fs"
            report = Path(temporary) / "report.json"
            bitstream.write_bytes(b"test")
            args = ["check_board", "--port", "fake", "--bitstream", str(bitstream),
                    "--report", str(report), "--boot-settle-seconds", str(settle)] + (
                        ["--keep-running"] if keep else [])
            def execute(command, **_kwargs):
                events.append("reset" if "--reset" in command else "load")
            with patch.object(sys, "argv", args), patch.object(module.subprocess, "run", execute), \
                    patch.object(module.time, "sleep") as sleep:
                with contextlib.redirect_stdout(io.StringIO()):
                    if b"FAIL\r\n" in messages:
                        with self.assertRaises(RuntimeError):
                            module.main()
                    else:
                        module.main()
                sleep.assert_called_once_with(0.5 + settle)
            import json
            result = json.loads(report.read_text())
        return events, result

    def test_discards_old_design_uart_after_loader_completes(self):
        events, result = self.run_check([b"PASS\r\n", b"PASS\r\n"], keep=True)
        self.assertEqual(events, ["flush", "load", "flush", "flush", "read", "read"])
        self.assertTrue(result["left_running"])
        self.assertEqual(result["pass_reports"], 2)

    def test_failure_always_attempts_flash_reload(self):
        events, result = self.run_check([b"FAIL\r\n"], keep=True)
        self.assertEqual(events[-1], "reset")
        self.assertTrue(result["restored_from_flash"])
        self.assertFalse(result["left_running"])

    def test_explicit_sd_settle_still_requires_two_fresh_reports(self):
        events, result = self.run_check([b"PASS\r\n", b"PASS\r\n"], keep=True, settle=2)
        self.assertEqual(result["boot_settle_seconds"], 2)
        self.assertEqual(result["pass_reports"], 2)
        self.assertEqual(events.count("flush"), 3)


if __name__ == "__main__":
    unittest.main()
