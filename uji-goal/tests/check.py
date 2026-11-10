#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="uji-goal-tests-") as data:
    for mode in ("core", "runner", "integration"):
        subprocess.run(
            ["uji", "run", "--config-dir", str(ROOT / "tests/config"),
             "--data-dir=" + data, mode],
            cwd=ROOT, check=True, timeout=30,
        )
