# =============================================================================
# Build a smaller sample from the NASA gz (used by Download-Nasa.ps1)
# =============================================================================
from __future__ import annotations

import gzip
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    src = root / "data" / "nasa" / "NASA_access_log_Jul95.gz"
    sample = root / "data" / "nasa" / "sample_jul95.log"
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000

    if not src.exists():
        print(f"missing {src}", file=sys.stderr)
        return 1

    n = 0
    with gzip.open(src, "rt", encoding="latin-1", errors="replace") as f, sample.open(
        "w", encoding="utf-8"
    ) as out:
        for line in f:
            out.write(line)
            n += 1
            if n >= limit:
                break

    print(f"sample_lines={n} bytes={sample.stat().st_size} path={sample}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
