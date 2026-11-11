# Sourced by the .agy scripts: sets $PY to a working Python 3 (macOS/Linux usually only have python3).
# Each candidate is run, not just looked up: on Windows "python3" can be a Microsoft Store stub that fails.
py_ok() { "$1" -c 'import sys; sys.exit(sys.version_info[0] < 3)' >/dev/null 2>&1; }
PY=""
if [ -n "$AGY_PYTHON" ]; then
  py_ok "$AGY_PYTHON" && PY="$AGY_PYTHON"
else
  for p in python3 python py; do py_ok "$p" && PY="$p" && break; done
fi
[ -n "$PY" ] || { echo "Python 3 not found${AGY_PYTHON:+ at AGY_PYTHON=$AGY_PYTHON}. Install it, or set AGY_PYTHON to its path." >&2; exit 69; }
