"""Pack _ipa_extract/Payload into an unsigned .ipa (zip with Payload/ at root)."""
from __future__ import annotations

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / "_ipa_extract" / "Payload"
OUT = ROOT / "RXTikTok-repacked-UNSIGNED.ipa"


def main() -> None:
    if not PAYLOAD.is_dir():
        raise SystemExit(f"Missing {PAYLOAD}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()
    skip_suffix = {".id0", ".id1", ".id2", ".nam", ".til", ".id3"}
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in PAYLOAD.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() in skip_suffix:
                continue
            arc = Path("Payload") / path.relative_to(PAYLOAD)
            try:
                zf.write(path, arc.as_posix())
            except OSError as e:
                print(f"Skip (locked/unreadable): {path} ({e})")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
