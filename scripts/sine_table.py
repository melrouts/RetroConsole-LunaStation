#!/usr/bin/env python3
"""Generate a quarter-wave Q1.15 sine table for the fixed-point game."""
import math
from pathlib import Path

values = [round(math.sin(index * math.pi / 128) * 32767) for index in range(65)]
Path("build/sine_table.h").write_text(
    "static const int16_t sine_quarter[65] = {\n    " +
    ", ".join(str(value) for value in values) + "\n};\n"
)
