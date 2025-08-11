import subprocess
from typing import Tuple, Optional


def run_cmd(cmd: list[str], cwd: Optional[str] = None) -> Tuple[str, str, int]:
    """Run a shell command and capture (stdout, stderr, exit code)."""
    process = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate()
    return stdout, stderr, process.returncode


def log_json(file_obj, record: dict) -> None:
    """Write a JSON record to the given file-like object."""
    import json
    file_obj.write(json.dumps(record) + "\n")
