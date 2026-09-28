#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEST="$ROOT/app/Madeira/x86_64-vcruntime"
CACHE="$ROOT/toolchains/downloads"
EXE="${VC_REDIST_X64:-$CACHE/vc_redist.x64.exe}"
URL="https://aka.ms/vc14/vc_redist.x64.exe"
DLLS=(
  concrt140.dll
  msvcp140.dll
  msvcp140_1.dll
  msvcp140_2.dll
  msvcp140_atomic_wait.dll
  msvcp140_codecvt_ids.dll
  vcamp140.dll
  vccorlib140.dll
  vcomp140.dll
  vcruntime140.dll
  vcruntime140_1.dll
  vcruntime140_threads.dll
)

command -v 7zz >/dev/null || { echo "ERROR: 7zz is required (brew install sevenzip)" >&2; exit 1; }
mkdir -p "$DEST" "$CACHE"

if [[ ! -f "$EXE" ]]; then
  echo "Downloading the official Microsoft Visual C++ x64 Redistributable..."
  curl --fail --location --retry 3 "$URL" -o "$EXE.tmp"
  mv "$EXE.tmp" "$EXE"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Burn installers can contain multiple concatenated CABs, with extensionless
# nested payloads and names such as vcruntime140.dll_amd64. 7-Zip's automatic
# EXE detection extracts only the first container in current redistributables.
python3 - "$EXE" "$TMP" "$DEST" "${DLLS[@]}" <<'PYEXTRACT'
from pathlib import Path
import shutil
import struct
import subprocess
import sys

exe, work, dest = map(Path, sys.argv[1:4])
wanted = sys.argv[4:]
data = exe.read_bytes()
containers = []
pos = 0
while True:
    offset = data.find(b"MSCF", pos)
    if offset < 0:
        break
    pos = offset + 4
    if offset + 36 > len(data):
        continue
    reserved, size, reserved2, files_offset, reserved3 = struct.unpack_from(
        "<IIIII", data, offset + 4
    )
    if (reserved or reserved2 or reserved3 or size < 36
            or offset + size > len(data) or not 36 <= files_offset < size):
        continue
    cab = work / f"container-{offset}.cab"
    cab.write_bytes(data[offset:offset + size])
    containers.append(cab)
    pos = offset + size
if not containers:
    raise SystemExit("ERROR: no CAB containers found in Microsoft redistributable")

# Extract the outer Burn containers, then their extensionless CAB payloads.
# Inspect the file magic, not package-specific names or CAB ordering.
extracted = work / "extracted"
queue = [(cab, 0) for cab in containers]
index = 0
while queue:
    cab, depth = queue.pop(0)
    if depth > 3:
        raise SystemExit("ERROR: unexpected CAB nesting in redistributable")
    out = extracted / str(index)
    index += 1
    out.mkdir(parents=True)
    subprocess.run(["7zz", "x", "-y", str(cab), f"-o{out}"],
                   check=True, stdout=subprocess.DEVNULL)
    for candidate in sorted(out.rglob("*")):
        if candidate.is_file():
            with candidate.open("rb") as handle:
                if handle.read(4) == b"MSCF":
                    queue.append((candidate, depth + 1))


def is_intact_x64_dll(path):
    payload = path.read_bytes()
    try:
        pe = struct.unpack_from("<I", payload, 0x3C)[0]
        machine = struct.unpack_from("<H", payload, pe + 4)[0]
        optional_magic = struct.unpack_from("<H", payload, pe + 24)[0]
        cert_offset, cert_size = struct.unpack_from(
            "<II", payload, pe + 24 + 112 + 4 * 8
        )
        return (payload[:2] == b"MZ" and payload[pe:pe + 4] == b"PE\0\0"
                and machine == 0x8664 and optional_magic == 0x20B
                and cert_offset > 0 and cert_size > 0
                and cert_offset + cert_size <= len(payload))
    except struct.error:
        return False


files = [p for p in sorted(extracted.rglob("*")) if p.is_file()]
selected = []
for name in wanted:
    # Some ARM64 compatibility DLLs report an AMD64 PE machine type too.
    # Respect the CAB's architecture suffix as well as checking the PE header.
    candidates = [p for p in files
                  if p.name.lower() in (name, name + "_amd64", name + "_x64")]
    source = next((p for p in candidates if is_intact_x64_dll(p)), None)
    if source is None:
        raise SystemExit(f"ERROR: intact x64 {name} not found in redistributable")
    selected.append((source, dest / name))

# Copy only after every required DLL passes the architecture and certificate
# bounds checks. These checks preserve the embedded Authenticode data; they
# do not cryptographically verify Microsoft's signature.
for source, target in selected:
    shutil.copyfile(source, target)
print(f"Visual C++ runtime: extracted {len(selected)} x64 DLLs to {dest}")
PYEXTRACT
