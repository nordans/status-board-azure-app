import argparse
import ipaddress
import json
import shutil
import subprocess
import time
from pathlib import Path
from urllib.request import urlopen


def run_az(*arguments: str) -> str:
    executable = shutil.which("az")
    if executable is None:
        raise RuntimeError("Azure CLI is required")
    result = subprocess.run(
        [executable, *arguments, "--only-show-errors"],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return result.stdout


def public_ipv4(value: str) -> str:
    address = ipaddress.ip_address(value.strip())
    if address.version != 4 or not address.is_global:
        raise ValueError("A public IPv4 address is required")
    return str(address)


def open_access(
    state_file: Path, resource_group: str, account: str, container: str, address: str
) -> None:
    address = public_ipv4(address)
    if state_file.exists():
        raise RuntimeError("A backend access record already exists; clean it up first")
    account_config = json.loads(
        run_az("storage", "account", "show", "-g", resource_group, "-n", account, "-o", "json")
    )
    rules = account_config["networkRuleSet"]
    if rules["defaultAction"] != "Deny" or account_config["publicNetworkAccess"] != "Enabled":
        raise RuntimeError("The backend must use a public endpoint with a deny-by-default firewall")
    already_allowed = any(
        ipaddress.ip_address(address) in ipaddress.ip_network(rule["ipAddressOrRange"])
        for rule in rules.get("ipRules", [])
        if rule.get("action", "Allow") == "Allow"
    )
    record = {
        "resource_group": resource_group,
        "account": account,
        "address": address,
        "added": not already_allowed,
    }
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps(record), encoding="utf-8")
    if not already_allowed:
        run_az(
            "storage",
            "account",
            "network-rule",
            "add",
            "-g",
            resource_group,
            "--account-name",
            account,
            "--ip-address",
            address,
            "-o",
            "none",
        )
    deadline = time.monotonic() + 300
    while True:
        try:
            exists = json.loads(
                run_az(
                    "storage",
                    "container",
                    "exists",
                    "--auth-mode",
                    "login",
                    "--account-name",
                    account,
                    "--name",
                    container,
                    "-o",
                    "json",
                )
            )["exists"]
            if not exists:
                raise RuntimeError("The development state container does not exist")
            return
        except subprocess.CalledProcessError:
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "Backend access did not become available within five minutes"
                ) from None
            time.sleep(5)


def close_access(state_file: Path, resource_group: str, account: str) -> None:
    if not state_file.exists():
        return
    record = json.loads(state_file.read_text(encoding="utf-8"))
    if record["account"] != account or record["resource_group"] != resource_group:
        raise RuntimeError("Backend cleanup context does not match the recorded account")
    if record["added"]:
        run_az(
            "storage",
            "account",
            "network-rule",
            "remove",
            "-g",
            resource_group,
            "--account-name",
            account,
            "--ip-address",
            public_ipv4(record["address"]),
            "-o",
            "none",
        )
    state_file.unlink()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["open", "close"])
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--container", default="tfstate")
    parser.add_argument("--state-file", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.operation == "close":
        close_access(arguments.state_file, arguments.resource_group, arguments.account)
    else:
        with urlopen("https://api.ipify.org", timeout=15) as response:
            address = response.read(128).decode("ascii")
        open_access(
            arguments.state_file,
            arguments.resource_group,
            arguments.account,
            arguments.container,
            address,
        )


if __name__ == "__main__":
    main()
