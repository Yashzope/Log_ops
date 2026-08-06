# =============================================================================
# LogOps — NASA-HTTP access log replayer
# Reads the classic NASA Kennedy Space Center WWW logs and appends them into
# the Fluent Bit tail path so the lite/full pipeline sees real public data.
#
# Source: https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html
# Format: Common Log Format (host - - [time] "METHOD path PROTO" code size)
# =============================================================================

from __future__ import annotations

import gzip
import logging
import os
import random
import re
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, TextIO

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("nasa-replayer")

_shutdown = False

# NASA CLF: host ident user [time] "request" status size
LINE_RE = re.compile(
    r'^(?P<host>\S+)\s+\S+\s+\S+\s+\[(?P<time>[^\]]+)\]\s+"'
    r'(?P<method>\S+)\s+(?P<path>\S+)(?:\s+\S+)?"\s+'
    r'(?P<code>\d+)\s+(?P<size>\S+)\s*$'
)


def _handle_signal(signum: int, _frame: object) -> None:
    global _shutdown
    logger.info("Signal %s — shutting down", signum)
    _shutdown = True


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name, str(default)).strip().lower()
    return raw in {"1", "true", "yes", "on"}


def open_nasa_log(path: Path) -> TextIO:
    """Open plain or gzip-compressed NASA log for text reading."""
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="latin-1", errors="replace")  # type: ignore[return-value]
    return path.open("r", encoding="latin-1", errors="replace")


def synthetic_latency_ms(code: int, size_raw: str) -> float:
    """
    NASA CLF has no latency field. Derive a plausible latency so Gold / Grafana
    p95 panels are meaningful while still driven by real status/size patterns.
    """
    try:
        size = int(size_raw) if size_raw != "-" else 0
    except ValueError:
        size = 0
    base = 40.0 + min(size / 5000.0, 400.0)
    if code >= 500:
        base *= random.uniform(2.5, 5.0)
    elif code >= 400:
        base *= random.uniform(1.2, 2.0)
    return round(max(5.0, random.gauss(base, base * 0.15)), 2)


def to_nginx_combined(host: str, method: str, path: str, code: str, size: str) -> str:
    """
    Emit nginx combined-style line with *current* wall clock so dashboards
    show live traffic (original 1995 timestamps stay in the message/path story).
    """
    now = datetime.now(timezone.utc).strftime("%d/%b/%Y:%H:%M:%S +0000")
    # Combined format: remote - user [time] "req" code size "referer" "agent"
    return (
        f'{host} - - [{now}] "{method} {path} HTTP/1.0" '
        f'{code} {size if size != "-" else 0} "-" "NASA-HTTP-replayer"\n'
    )


def to_app_json(
    host: str,
    method: str,
    path: str,
    code: int,
    size: str,
    latency_ms: float,
) -> str:
    """Optional JSON twin for the app_logs.json Fluent Bit input."""
    import json
    import uuid

    level = "ERROR" if code >= 500 else "WARN" if code >= 400 else "INFO"
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "nasa-www",
        "level": level,
        "message": f"{method} {path}",
        "status_code": code,
        "latency_ms": latency_ms,
        "client_ip": host if re.match(r"^\d+\.\d+\.\d+\.\d+$", host) else "0.0.0.0",
        "request_id": str(uuid.uuid4()),
        "host": "nasa-ksc-www",
        "method": method,
        "path": path,
        "bytes": size,
        "dataset": "NASA-HTTP",
    }
    return json.dumps(event) + "\n"


def iter_valid_lines(handle: TextIO) -> Iterator[re.Match[str]]:
    for raw in handle:
        if _shutdown:
            break
        line = raw.strip()
        if not line:
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        yield match


def replay_once(
    nasa_path: Path,
    nginx_path: Path,
    app_path: Path | None,
    sleep_s: float,
    synth_latency: bool,
) -> int:
    """Replay the whole file once. Returns number of lines written."""
    written = 0
    with open_nasa_log(nasa_path) as src:
        for match in iter_valid_lines(src):
            if _shutdown:
                break
            host = match.group("host")
            method = match.group("method")
            path = match.group("path")
            code = match.group("code")
            size = match.group("size")
            code_i = int(code)

            nginx_line = to_nginx_combined(host, method, path, code, size)
            with nginx_path.open("a", encoding="utf-8") as out:
                out.write(nginx_line)

            if app_path is not None:
                latency = (
                    synthetic_latency_ms(code_i, size)
                    if synth_latency
                    else 0.0
                )
                with app_path.open("a", encoding="utf-8") as out:
                    out.write(
                        to_app_json(host, method, path, code_i, size, latency)
                    )

            written += 1
            if written % 500 == 0:
                logger.info("Replayed %s NASA lines so far", written)
            if sleep_s > 0:
                time.sleep(sleep_s)
    return written


def main() -> int:
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    nasa_path = Path(
        os.getenv(
            "NASA_LOG_PATH",
            "/data/nasa/NASA_access_log_Jul95.gz",
        )
    )
    log_dir = Path(os.getenv("LOG_DIR", "/var/log/logops"))
    sleep_s = float(os.getenv("SLEEP_SECONDS", "0.05"))
    loop = env_bool("LOOP", True)
    synth_latency = env_bool("SYNTHETIC_LATENCY", True)
    write_json = env_bool("WRITE_APP_JSON", True)

    if not nasa_path.exists():
        # Fall back to committed sample for offline demos
        sample = Path("/data/nasa/sample_jul95.log")
        alt = Path("data/nasa/sample_jul95.log")
        if sample.exists():
            nasa_path = sample
        elif alt.exists():
            nasa_path = alt
        else:
            logger.error("NASA log not found at %s (run Download-Nasa.ps1)", nasa_path)
            return 1

    log_dir.mkdir(parents=True, exist_ok=True)
    nginx_path = log_dir / "nginx_access.log"
    app_path = (log_dir / "app_logs.json") if write_json else None

    logger.info(
        "Replaying %s → %s (sleep=%ss loop=%s json=%s)",
        nasa_path,
        nginx_path,
        sleep_s,
        loop,
        write_json,
    )

    total = 0
    while not _shutdown:
        n = replay_once(nasa_path, nginx_path, app_path, sleep_s, synth_latency)
        total += n
        logger.info("Pass complete (%s lines this pass, %s total)", n, total)
        if not loop or _shutdown:
            break
        logger.info("Looping dataset from the start…")

    logger.info("Shutdown after %s total lines", total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
