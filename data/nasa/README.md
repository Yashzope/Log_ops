# NASA-HTTP dataset for LogOps

**Chosen public dataset** for [PROBLEM_STATEMENT.md](../docs/PROBLEM_STATEMENT.md).

| Item | Value |
| ---- | ----- |
| Name | NASA-HTTP |
| Origin | NASA Kennedy Space Center WWW server (Jul–Aug 1995) |
| Official page | https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html |
| File used | `NASA_access_log_Jul95.gz` (July 1995, ~20 MB compressed) |
| Format | Common Log Format — host, timestamp, request, HTTP status, bytes |
| License | Freely redistributable (Internet Traffic Archive terms) |

## Files in this folder

| File | Tracked in git? | Purpose |
| ---- | --------------- | ------- |
| `NASA_access_log_Jul95.gz` | No (large) | Full July trace — download via `scripts/Download-Nasa.ps1` |
| `sample_jul95.log` | Optional / large | First 100k lines for smoke tests |
| `README.md` | Yes | This file |

## How LogOps uses it

```powershell
.\scripts\Download-Nasa.ps1
.\scripts\Start-Lite-Nasa.ps1
```

`nasa-replayer` streams lines into `/var/log/logops/nginx_access.log` (+ JSON twin)
so Fluent Bit → Kafka → ClickHouse → Grafana sees **real public web logs**.

Original 1995 timestamps are not used for dashboard time range; wall-clock time
is applied on replay so Grafana “last 15 minutes” works. Status codes and paths
remain authentic. Latency is synthesized from status/size because CLF has none.

## Citation

Arlitt, M. & Williamson, C. “Web Server Workload Characterization: The Search for Invariants,” ACM SIGMETRICS 1996. Dataset via the Internet Traffic Archive (NASA-HTTP).
