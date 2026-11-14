"""Gates de contexto, metadados de estado e comandos antigos, sem APIs/credenciais."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "scripts/preflight-kubectl-context.py"
spec = importlib.util.spec_from_file_location("preflight", SOURCE)
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class ContextPreflightTest(unittest.TestCase):
    def evaluate(self, trigger=None, plan_context="fixture", present=True, key="kubectl_path"):
        state = {"resources": [{"module": "module.fixture", "type": "null_resource", "name": "route",
                 "instances": [{"attributes": {"triggers": trigger or {"kubectl_path": "kubectl"}}}]}] if present else []}
        plan = {"variables": {"kubeconfig_context": {"value": plan_context}, "kubectl_path": {"value": "kubectl"}}}
        return preflight.evaluate(state, plan, "fixture", {"module.fixture.null_resource.route": key})

    def test_old_bare_path_is_covered_without_new_trigger(self):
        result = self.evaluate()
        self.assertTrue(result["state_hook_paths_ok"])
        self.assertTrue(result["provider_context_matches"])
        self.assertEqual(result["covered_hook_instances"], 1)

    def test_missing_hook_fails_closed(self):
        self.assertFalse(self.evaluate(present=False)["state_hook_paths_ok"])

    def test_nonbare_stored_path_fails_closed(self):
        for value in ("/usr/bin/kubectl", "./kubectl", "kubectl --context=other", ""):
            self.assertFalse(self.evaluate({"kubectl_path": value})["state_hook_paths_ok"])

    def test_null_or_other_provider_context_fails_closed(self):
        for value in (None, "other", ""):
            self.assertFalse(self.evaluate(plan_context=value)["provider_context_matches"])

    def test_legacy_delete_chain_is_covered(self):
        command = "kubectl delete service fixture && kubectl delete deployment fixture"
        self.assertTrue(self.evaluate({"delete_command": command}, key="delete_command")["state_hook_paths_ok"])

    def test_shell_operators_substitution_and_context_overrides_rejected(self):
        for command in ("kubectl delete x; echo x", "kubectl delete x | cat", "kubectl $(command)",
                        "kubectl `command`", "kubectl --context=other delete x", "kubectl delete x &&",
                        "/bin/kubectl delete x", "kubectl delete x > file", ""):
            self.assertFalse(preflight.delete_command_is_interceptable(command), command)

    def test_no_plan_cannot_pass_provider_gate(self):
        result = preflight.evaluate({"resources": []}, None, "fixture", {})
        self.assertFalse(result["plan_present"])
        self.assertFalse(result["provider_context_matches"])
        self.assertFalse(result["state_hook_paths_ok"])

    def test_cli_pass_and_sanitized_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "modules/fixture"
            module.mkdir(parents=True)
            (module / "main.tf").write_text('resource "null_resource" "route" {\n provisioner "local-exec" {\n when = destroy\n command = self.triggers.kubectl_path\n }\n}\n')
            state = root / "state.json"
            state.write_text(json.dumps({"resources": [{"module": "module.fixture", "type": "null_resource", "name": "route", "instances": [{"attributes": {"triggers": {"kubectl_path": "kubectl"}}}]}]}))
            plan = root / "plan.json"
            plan.write_text(json.dumps({"variables": {"kubeconfig_context": {"value": "fixture"}, "kubectl_path": {"value": "kubectl"}}}))
            launcher = root / "kubectl"
            real = root / "kubectl-real"
            for file in (launcher, real):
                file.write_text('#!/bin/sh\nprintf "%s\\n" "$KUBECTL_CONTEXT_REQUIRED"\n')
                file.chmod(0o700)
            args = [sys.executable, str(SOURCE), "--state", str(state), "--plan", str(plan), "--context", "fixture", "--modules-dir", str(root / "modules"), "--launcher", str(launcher), "--kubectl", str(real)]
            result = subprocess.run(args, env={"PATH": os.defpath}, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertTrue(json.loads(result.stdout)["ready"])
            valid_state = state.read_text()
            state.write_text('{"private_secret_value":invalid')
            result = subprocess.run(args, env={"PATH": os.defpath}, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("private_secret_value", result.stdout + result.stderr)
            self.assertNotIn(str(state), result.stdout + result.stderr)
            malformed_states = [[], None, {"resources": None}, {"resources": [None]},
                                {"resources": [{"type": "null_resource", "name": "fixture", "instances": None}]},
                                {"resources": [{"type": "null_resource", "name": "fixture", "instances": [{"attributes": []}]}]},
                                {"resources": [{"type": "null_resource", "name": "fixture", "instances": [{"attributes": {"triggers": []}}]}]}]
            malformed_plans = [[], None, {"variables": []}, {"variables": {"kubeconfig_context": None}}]
            for malformed in malformed_states:
                state.write_text(json.dumps(malformed))
                result = subprocess.run(args, env={"PATH": os.defpath}, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(json.loads(result.stdout), {"ready": False, "error": "invalid_or_unavailable_local_source"})
                self.assertEqual(result.stderr, "")
            state.write_text(valid_state)
            for malformed in malformed_plans:
                plan.write_text(json.dumps(malformed))
                result = subprocess.run(args, env={"PATH": os.defpath}, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(json.loads(result.stdout), {"ready": False, "error": "invalid_or_unavailable_local_source"})
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
