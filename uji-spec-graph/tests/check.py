#!/usr/bin/env python3
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="uji-spec-graph-") as temporary:
    directory = Path(temporary)
    work = directory / "project"
    work.mkdir()
    result = subprocess.run(
        ["uji", "run", "--config-dir", str(ROOT / "tests/config"),
         "--data-dir=" + str(directory / "data"), "spec-graph-test"],
        cwd=work, check=True, capture_output=True, text=True, timeout=60,
    )
    assert "passed real uji" in result.stdout, result.stdout + result.stderr
    print(result.stdout.strip())
