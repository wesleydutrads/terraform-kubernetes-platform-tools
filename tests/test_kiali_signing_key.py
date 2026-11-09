#!/usr/bin/env python3
"""Avalia os values reais do Kiali com OpenTofu/Terraform, sem providers/init/plan/cloud."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TF = os.environ.get("TF_BIN", "terraform")
MODULE = ROOT / "modules/observability"
TOKEN = "unit-test-token-000000000000000"  # valor fictício, nunca um segredo real

BASE = {
    "monitoring_token": TOKEN,
    "hosts": {"kiali": "k.example.invalid", "grafana": "g.example.invalid",
              "tracing": "t.example.invalid", "prometheus": "p.example.invalid"},
    "gateway_name": "shared",
    "gateway_namespace": "gateway-system",
    "kubeconfig_path": "/dev/null",
    "kubectl_path": "kubectl",
}


def values_expression(source):
    segment = source[source.index('resource "helm_release" "kiali"'):]
    return segment.split("values = [", 1)[1].split("yamlencode(", 1)[1].split("\n    })\n  ]", 1)[0] + "\n    }"


@unittest.skipUnless(shutil.which(TF), "Terraform/OpenTofu indisponível; fornecer TF_BIN")
class KialiSigningKeyContract(unittest.TestCase):
    def evaluate(self, extra=None):
        main = (MODULE / "main.tf").read_text()
        locals_block = main.split("locals {", 1)[1].split("\n}\n", 1)[0]
        with tempfile.TemporaryDirectory(prefix="kiali-signing-key-test-") as tmp:
            path = Path(tmp)
            (path / "variables.tf").write_text((MODULE / "variables.tf").read_text())
            (path / "main.tf").write_text(
                "locals {" + locals_block + "\n}\nlocals {\n  v = " + values_expression(main) + "\n}\n")
            (path / "t.tfvars.json").write_text(json.dumps({**BASE, **(extra or {})}))
            result = subprocess.run(
                [TF, "console", "-no-color", "-var-file=t.tfvars.json"], cwd=path,
                input="nonsensitive(jsonencode(local.v))\n", capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(json.loads(result.stdout.strip()))

    def test_default_keeps_legacy_signing_key(self):
        values = self.evaluate()
        self.assertEqual(values["login_token"]["signing_key"], TOKEN)
        self.assertNotIn("pod_annotations", values["deployment"])
        self.assertNotIn("custom_secrets", values["deployment"])

    def test_dedicated_uses_secret_reference(self):
        values = self.evaluate({"kiali_dedicated_signing_key_enabled": True,
                                "kiali_signing_key_rotation": "2"})
        self.assertEqual(values["login_token"]["signing_key"], "secret:kiali-signing-key:signing-key")
        self.assertEqual(values["deployment"]["pod_annotations"]["kiali.io/signing-key-rotation"], "2")
        self.assertNotIn(TOKEN, json.dumps(values))

    def test_dedicated_keeps_secret_mounted_via_custom_secrets(self):
        values = self.evaluate({"kiali_dedicated_signing_key_enabled": True})
        self.assertEqual(values["deployment"]["custom_secrets"], [{
            "name": "kiali-signing-key",
            "mount": "/kiali-override-secrets/login-token-signing-key",
            "optional": False,
        }])
        # Mesmo mountPath que o chart usa para login_token.signing_key (volume login-token-signing-key).
        self.assertTrue(values["deployment"]["custom_secrets"][0]["mount"].endswith("/login-token-signing-key"))

    def test_dedicated_ignored_when_kiali_disabled(self):
        values = self.evaluate({"kiali_dedicated_signing_key_enabled": True, "enable_kiali": False})
        self.assertEqual(values["login_token"]["signing_key"], TOKEN)
        self.assertNotIn("custom_secrets", values["deployment"])
        self.assertNotIn("pod_annotations", values["deployment"])


if __name__ == "__main__":
    unittest.main()
