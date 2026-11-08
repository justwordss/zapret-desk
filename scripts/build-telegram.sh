#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/.build-local}"
PYTHON="${PYTHON_BINARY:-python3}"
mkdir -p "$BUILD"
"$PYTHON" -m venv "$BUILD/tg-env"
"$BUILD/tg-env/bin/pip" install -r "$ROOT/telegram/requirements-build.txt"
# PyInstaller universal2 requires all native libraries to contain both slices.
# Python.org's universal2 interpreter and cryptography wheel already do.
PYVER="$("$BUILD/tg-env/bin/python" -c 'import sys;print(f"{sys.version_info.major}{sys.version_info.minor}")')"
"$BUILD/tg-env/bin/pip" download --no-deps --only-binary=:all: --platform macosx_10_13_x86_64 --python-version "$PYVER" cffi==2.0.0 -d "$BUILD/tg-wheels"
"$BUILD/tg-env/bin/python" - "$BUILD" <<'PY'
from pathlib import Path
import sys,sysconfig,zipfile,subprocess
root=Path(sys.argv[1]);native=next(Path(sysconfig.get_paths()['platlib']).glob('_cffi_backend*.so'))
if 'x86_64' not in subprocess.check_output(['lipo','-archs',str(native)],text=True):
 wheel=next((root/'tg-wheels').glob('*x86_64.whl'))
 with zipfile.ZipFile(wheel) as z:
  name=next(n for n in z.namelist() if n.endswith('.so'));(root/'cffi-x86.so').write_bytes(z.read(name))
 subprocess.run(['lipo','-create',str(native),str(root/'cffi-x86.so'),'-output',str(root/'cffi-universal.so')],check=True)
 native.write_bytes((root/'cffi-universal.so').read_bytes())
PY
PYINSTALLER_CONFIG_DIR="$BUILD/pyinstaller-cache" "$BUILD/tg-env/bin/pyinstaller" --noconfirm --onedir --console --target-arch universal2 --name tgws --distpath "$BUILD/tg-dist" --workpath "$BUILD/tg-pyi" --specpath "$BUILD" --paths "$ROOT/telegram" --collect-all certifi "$ROOT/telegram/launcher.py"
"$BUILD/tg-dist/tgws/tgws" --self-test
