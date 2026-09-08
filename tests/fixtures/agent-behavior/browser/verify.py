from pathlib import Path
import subprocess
import sys

result = subprocess.run(["node", str(Path(__file__).with_name("verify-browser.mjs")), sys.argv[1]])
sys.exit(result.returncode)
