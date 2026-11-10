#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="uji-tools-pack-") as temporary:
    directory = Path(temporary)
    checkout = directory / "site" / "checkout with spaces"
    shutil.copytree(
        ROOT,
        checkout,
        ignore=shutil.ignore_patterns(".git", "node_modules", "build", "dist", "__pycache__"),
    )
    work = directory / "unrelated-project"
    work.mkdir()
    result = subprocess.run(
        ["uji", "run", "--config-dir", str(ROOT / "tests/config"),
         "--data-dir=" + str(directory / "data"), "pack-test"],
        cwd=work,
        env={**os.environ, "UJI_TOOLS_TEST_ROOT": str(checkout)},
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert "passed root pack" in result.stdout, result.stdout + result.stderr
    print(result.stdout.strip())
