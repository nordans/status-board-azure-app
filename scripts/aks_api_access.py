import argparse
import ipaddress
import json
import shutil
import subprocess
import time
from pathlib import Path
from urllib.request import urlopen

from scripts.infra_backend_access import public_ipv4


def run_az(*arguments: str) -> str:
    executable = shutil.which("az")
    if executable is None:
        raise RuntimeError("Azure CLI is required")
    return subprocess.run(
        [executable, *arguments, "--only-show-errors"],
        check=True,
        capture_output=True,
        text=True,
        timeout=900,
    ).stdout


def cluster_config(group: str, cluster: str) -> dict:
    return json.loads(run_az("aks", "show", "-g", group, "-n", cluster, "-o", "json"))


def allowed_ranges(config: dict) -> list[str]:
    ranges = config.get("apiServerAccessProfile", {}).get("authorizedIpRanges") or []
    if not ranges or any(ipaddress.ip_network(value).prefixlen == 0 for value in ranges):
        raise RuntimeError("AKS must retain a nonempty restricted API allowlist")
    return ranges


def update_ranges(group: str, cluster: str, ranges: list[str]) -> None:
    run_az(
        "aks",
        "update",
        "-g",
        group,
        "-n",
        cluster,
        "--api-server-authorized-ip-ranges",
        ",".join(ranges),
        "-o",
        "none",
    )


def open_access(record_file: Path, group: str, cluster: str, address: str) -> None:
    address = public_ipv4(address)
    if record_file.exists():
        raise RuntimeError("An API access record already exists; clean it up first")
    config = cluster_config(group, cluster)
    if config["provisioningState"] != "Succeeded":
        raise RuntimeError("AKS must finish provisioning before opening runner access")
    ranges = allowed_ranges(config)
    added = not any(ipaddress.ip_address(address) in ipaddress.ip_network(item) for item in ranges)
    record = {"group": group, "cluster": cluster, "cidr": f"{address}/32", "added": added}
    record_file.write_text(json.dumps(record), encoding="utf-8")
    if added:
        update_ranges(group, cluster, [*ranges, record["cidr"]])


def close_access(record_file: Path, group: str, cluster: str) -> None:
    if not record_file.exists():
        return
    record = json.loads(record_file.read_text(encoding="utf-8"))
    if record["group"] != group or record["cluster"] != cluster:
        raise RuntimeError("API cleanup context does not match the recorded cluster")
    public_ipv4(record["cidr"].removesuffix("/32"))
    if record["added"]:
        deadline = time.monotonic() + 900
        while True:
            config = cluster_config(group, cluster)
            if config["provisioningState"] in {"Succeeded", "Failed"}:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("AKS is still busy; the recorded runner rule requires cleanup")
            time.sleep(10)
        current = allowed_ranges(config)
        if record["cidr"] in current:
            remaining = [value for value in current if value != record["cidr"]]
            if not remaining:
                raise RuntimeError(
                    "Refusing to remove the last API rule; restore the operator allowlist"
                )
            update_ranges(group, cluster, remaining)
    record_file.unlink()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["open", "close"])
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--cluster", required=True)
    parser.add_argument("--record-file", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        if arguments.operation == "close":
            close_access(arguments.record_file, arguments.resource_group, arguments.cluster)
        else:
            with urlopen("https://api.ipify.org", timeout=15) as response:
                address = response.read(128).decode("ascii")
            open_access(arguments.record_file, arguments.resource_group, arguments.cluster, address)
    except subprocess.CalledProcessError as error:
        parser.exit(1, error.stderr or "Azure CLI failed without error details\n")


if __name__ == "__main__":
    main()
