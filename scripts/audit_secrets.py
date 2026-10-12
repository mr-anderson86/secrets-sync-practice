"""Audit application secrets across the cluster (Part 3B).

Flags every in-scope secret that:
  - has no `owner` label, or
  - has no `secrets.example.com/last-rotated` annotation (or an unparsable one), or
  - was last rotated more than --max-age-days ago (default 90).

Scope: only `Opaque` secrets outside `kube-*` namespaces. That skips Helm release
secrets, ServiceAccount tokens, TLS secrets and cluster internals.
Only metadata is read; secret values are never printed.

Exit codes: 0 = all clean, 1 = findings, 2 = cannot talk to the cluster.
"""
import argparse
import sys
from datetime import date, datetime, timezone

from kubernetes import client, config
from rich.console import Console
from rich.table import Table

OWNER_LABEL = "owner"
ROTATED_ANNOTATION = "secrets.example.com/last-rotated"

# Outside a terminal (CI, cron, pipes) rich defaults to 80 columns and would truncate names.
console = Console() if sys.stdout.isatty() else Console(width=160)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--max-age-days", type=int, default=90, help="max days since last rotation (default: 90)")
    p.add_argument("--exclude-namespace", action="append", default=[], metavar="NS",
                   help="extra namespace to skip (repeatable)")
    return p.parse_args()


def load_secrets():
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()  # running as a CronJob inside the cluster
    return client.CoreV1Api().list_secret_for_all_namespaces().items


def in_scope(secret, excluded):
    ns = secret.metadata.namespace
    return secret.type == "Opaque" and not ns.startswith("kube-") and ns not in excluded


def parse_date(value):
    try:
        return date.fromisoformat(value)
    except ValueError:
        return datetime.fromisoformat(value).date()  # also accept a full timestamp


def check(secret, today, max_age_days):
    labels = secret.metadata.labels or {}
    annotations = secret.metadata.annotations or {}
    owner = labels.get(OWNER_LABEL)
    rotated = annotations.get(ROTATED_ANNOTATION)

    reasons = []
    if not owner:
        reasons.append("no owner label")
    if not rotated:
        reasons.append("no last-rotated annotation")
    else:
        try:
            age = (today - parse_date(rotated)).days
        except ValueError:
            reasons.append(f"invalid last-rotated: {rotated!r}")
        else:
            if age > max_age_days:
                reasons.append(f"rotated {age} days ago (> {max_age_days})")
    return owner, rotated, reasons


def main():
    args = parse_args()
    try:
        secrets = load_secrets()
    except Exception as e:  # config, auth or connection problems
        console.print(f"[red]cannot list secrets from the cluster:[/red] {e}")
        return 2

    today = datetime.now(timezone.utc).date()
    rows = []
    for s in secrets:
        if not in_scope(s, args.exclude_namespace):
            continue
        owner, rotated, reasons = check(s, today, args.max_age_days)
        rows.append((s.metadata.namespace, s.metadata.name, owner, rotated, reasons))
    rows.sort(key=lambda r: (not r[4], r[0], r[1]))  # flagged first

    table = Table(title=f"Application secrets audit ({today}, max age {args.max_age_days}d)")
    for col in ("", "namespace", "name", "owner", "last-rotated"):
        table.add_column(col, no_wrap=True)
    table.add_column("reasons")
    for ns, name, owner, rotated, reasons in rows:
        table.add_row(
            "❌" if reasons else "✅",
            ns,
            name,
            owner or "[dim]-[/dim]",
            rotated or "[dim]-[/dim]",
            f"[red]{', '.join(reasons)}[/red]" if reasons else "[green]ok[/green]",
        )
    console.print(table)

    flagged = sum(1 for r in rows if r[4])
    if flagged:
        console.print(f"[red]{flagged} of {len(rows)} secrets need attention[/red]")
        return 1
    console.print(f"[green]all {len(rows)} secrets are compliant[/green]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
