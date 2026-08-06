# =============================================================================
# LogOps — Shared Airflow helpers (Slack alerts + failure callbacks)
# Import these from every DAG so alerting stays consistent.
# =============================================================================

from __future__ import annotations

import json
import logging
import os
from typing import Any

import requests

logger = logging.getLogger(__name__)


def get_slack_webhook() -> str | None:
    """Read the Slack webhook URL from the environment (may be empty)."""
    url = os.getenv("SLACK_WEBHOOK_URL", "").strip()
    if not url or url.startswith("[FILL_IN"):
        return None
    return url


def send_slack_alert(message: str, severity: str = "error") -> bool:
    """
    Post a simple text message to Slack via incoming webhook.
    Returns True on success, False if skipped or failed.
    """
    webhook = get_slack_webhook()
    if webhook is None:
        logger.warning("Slack webhook not configured — skipping alert: %s", message)
        return False

    emoji = {"error": ":x:", "warn": ":warning:", "info": ":information_source:"}.get(
        severity, ":bell:"
    )
    payload = {"text": f"{emoji} *LogOps* — {message}"}

    try:
        response = requests.post(webhook, json=payload, timeout=10)
        response.raise_for_status()
        return True
    except requests.RequestException as exc:
        logger.exception("Failed to send Slack alert: %s", exc)
        return False


def task_failure_callback(context: dict[str, Any]) -> None:
    """
    Airflow on_failure_callback: notify Slack with DAG / task / exception info.
    Attach this to default_args so every task failure is visible.
    """
    dag_id = context.get("dag").dag_id if context.get("dag") else "unknown_dag"
    task_id = context.get("task_instance").task_id if context.get("task_instance") else "unknown_task"
    execution_date = context.get("execution_date")
    exception = context.get("exception")

    message = (
        f"Task *{task_id}* in DAG *{dag_id}* failed.\n"
        f"Execution: `{execution_date}`\n"
        f"Error: ```{exception}```"
    )
    send_slack_alert(message, severity="error")


def task_success_callback(context: dict[str, Any]) -> None:
    """Optional success callback for long-running jobs that need a green check."""
    dag_id = context.get("dag").dag_id if context.get("dag") else "unknown_dag"
    task_id = context.get("task_instance").task_id if context.get("task_instance") else "unknown_task"
    send_slack_alert(f"Task *{task_id}* in DAG *{dag_id}* succeeded.", severity="info")


def sla_miss_callback(dag, task_list, blocking_task_list, slas, blocking_tis) -> None:  # noqa: ANN001
    """Airflow SLA miss callback — fires when a task runs past its SLA."""
    task_ids = ", ".join(t.task_id for t in task_list) if task_list else "unknown"
    send_slack_alert(
        f"SLA miss on DAG *{dag.dag_id}* for tasks: {task_ids}",
        severity="warn",
    )


def require_env(name: str) -> str:
    """Fetch a required environment variable or raise a clear beginner-friendly error."""
    value = os.getenv(name, "").strip()
    if not value or value.startswith("[FILL_IN"):
        raise ValueError(
            f"Environment variable {name} is missing. "
            f"Copy .env.example to .env and replace [FILL_IN_YOUR_XXX] placeholders."
        )
    return value
