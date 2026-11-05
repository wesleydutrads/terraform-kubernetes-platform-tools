#!/usr/bin/env python3
"""Preflight local, sem rede e sem emitir comandos, paths ou conteúdo de estado."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess


def delete_command_is_interceptable(command):
    if not isinstance(command, str) or any(c in command for c in "`$\n\r"):
        return False
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return False
    commands = [[]]
    for token in tokens:
        if token == "&&":
            commands.append([])
        elif token and all(c in ";&|<>()" for c in token):
            return False
        else:
            commands[-1].append(token)
    return all(c and c[0] == "kubectl" and not any(
        a == "--context" or a.startswith("--context=") for a in c[1:]
    ) for c in commands)


def hook_specs(modules):
    specs = {}
    for path in sorted(Path(modules).glob("*/main.tf")):
        module = path.parent.name.replace("-", "_")
        for block in re.split(r'(?=^resource ")', path.read_text(), flags=re.M):
            match = re.match(r'resource "null_resource" "([^"]+)"', block)
            if match and re.search(r"when\s*=\s*destroy", block):
                address = f"module.{module}.null_resource.{match[1]}"
                specs[address] = "delete_command" if "self.triggers.delete_command" in block else "kubectl_path"
    return specs


def evaluate(state, plan, context, specs):
    # Validar cada nível utilizado antes de acessar atributos; JSON válido não
    # implica schema Terraform válido. Nunca incluir o valor inválido no erro.
    if not isinstance(state, dict) or not isinstance(state.get("resources"), list):
        raise ValueError("state_schema")
    if plan is not None and (
        not isinstance(plan, dict) or not isinstance(plan.get("variables"), dict)
        or any(not isinstance(value, dict) for value in plan["variables"].values())
    ):
        raise ValueError("plan_schema")
    resources = {}
    for resource in state.get("resources", []):
        if not isinstance(resource, dict):
            raise ValueError("resource_schema")
        if resource.get("type") == "null_resource":
            if not isinstance(resource.get("name"), str) or not isinstance(resource.get("module", ""), str):
                raise ValueError("resource_address_schema")
            if not isinstance(resource.get("instances"), list):
                raise ValueError("instances_schema")
            for instance in resource["instances"]:
                if not isinstance(instance, dict) or not isinstance(instance.get("attributes"), dict):
                    raise ValueError("attributes_schema")
                triggers = instance["attributes"].get("triggers")
                if triggers is not None and not isinstance(triggers, dict):
                    raise ValueError("triggers_schema")
            prefix = resource.get("module", "")
            address = (prefix + "." if prefix else "") + "null_resource." + resource["name"]
            resources[address] = resource.get("instances", [])
    covered = instances = failures = 0
    for address, key in specs.items():
        found = resources.get(address, [])
        if not found:
            failures += 1
            continue
        covered += 1
        for instance in found:
            instances += 1
            triggers = instance.get("attributes", {}).get("triggers") or {}
            value = triggers.get(key)
            valid = delete_command_is_interceptable(value) if key == "delete_command" else value == "kubectl"
            failures += not valid
    variables = plan.get("variables", {}) if isinstance(plan, dict) else {}
    return {
        "expected_hook_resources": len(specs),
        "covered_hook_resources": covered,
        "covered_hook_instances": instances,
        "uncovered_hook_paths": failures,
        "state_hook_paths_ok": bool(specs) and failures == 0,
        "plan_present": isinstance(plan, dict),
        "provider_context_matches": variables.get("kubeconfig_context", {}).get("value") == context,
        "current_kubectl_path_interceptable": variables.get("kubectl_path", {}).get("value") == "kubectl",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True)
    parser.add_argument("--plan", help="JSON existente de terraform show; ausente mantém gate fechado")
    parser.add_argument("--context", required=True)
    parser.add_argument("--launcher", required=True)
    parser.add_argument("--kubectl", required=True)
    parser.add_argument("--modules-dir", default=str(Path(__file__).resolve().parents[1] / "modules"))
    args = parser.parse_args()
    try:
        if not args.context.strip():
            raise ValueError("context")
        state = json.loads(Path(args.state).read_text())
        plan = json.loads(Path(args.plan).read_text()) if args.plan else None
        if args.plan and not isinstance(plan, dict):
            raise ValueError("plan_schema")
        result = evaluate(state, plan, args.context, hook_specs(args.modules_dir))
        launcher, real = Path(args.launcher), Path(args.kubectl)
        executable = all(p.is_absolute() and p.is_file() and os.access(p, os.X_OK) for p in (launcher, real))
        result["executables_ok"] = executable and not launcher.samefile(real)
        child_env = {
            "PATH": str(launcher.parent) + os.pathsep + os.defpath,
            "HOME": os.environ.get("HOME", ""),
            "KUBECTL_REAL": str(real),
            "KUBECTL_CONTEXT_REQUIRED": args.context,
            "TF_VAR_kubeconfig_context": args.context,
        }
        result["child_path_selects_launcher"] = shutil.which("kubectl", path=child_env["PATH"]) == str(launcher)
        result["configured_context_exists"] = False
        if result["executables_ok"] and result["child_path_selects_launcher"]:
            kubeconfig = (plan or {}).get("variables", {}).get("kubeconfig_path", {}).get("value", "~/.kube/config")
            if not isinstance(kubeconfig, str) or not kubeconfig.strip():
                raise ValueError("kubeconfig")
            # config get-contexts apenas lê metadados locais; não chama API/auth exec.
            query = subprocess.run(
                [str(launcher), "--kubeconfig=" + str(Path(kubeconfig).expanduser()), "config", "get-contexts", args.context, "-o", "name"],
                env=child_env, text=True, capture_output=True, timeout=10,
            )
            result["configured_context_exists"] = query.returncode == 0 and query.stdout.strip() == args.context
        gates = ("state_hook_paths_ok", "plan_present", "provider_context_matches",
                 "current_kubectl_path_interceptable", "executables_ok",
                 "child_path_selects_launcher", "configured_context_exists")
        result["ready"] = all(result[k] for k in gates)
        print(json.dumps(result, sort_keys=True))
        return 0 if result["ready"] else 2
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Exceções de JSON/OS podem carregar fragmentos sensíveis ou paths privados.
        print(json.dumps({"ready": False, "error": "invalid_or_unavailable_local_source"}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
