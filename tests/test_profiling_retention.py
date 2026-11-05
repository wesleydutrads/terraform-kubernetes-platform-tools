#!/usr/bin/env python3
"""Avalia os values reais com Terraform, sem providers/init/plan/cloud."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TF = os.environ.get("TF_BIN", "terraform")
MODULE = ROOT / "modules/profiling"


def values_expression(source):
    # Primeiro yamlencode é o objeto completo dos values do release Pyroscope.
    return source.split("values = [", 1)[1].split("yamlencode(", 1)[1].split("\n    })", 1)[0] + "\n    }"


@unittest.skipUnless(shutil.which(TF), "Terraform indisponível; fornecer TF_BIN")
class RetentionContract(unittest.TestCase):
    def evaluate(self, seconds=None, baseline=False):
        if baseline:
            # Golden sanitizado gerado de e5ba1fb, com storage=null e DNS genérico.
            golden = ROOT / "tests/fixtures/profiling-default-values.json"
            return subprocess.CompletedProcess([], 0, "", ""), json.loads(golden.read_text())
        main = (MODULE / "main.tf").read_text()
        with tempfile.TemporaryDirectory(prefix="profiling-retention-test-") as tmp:
            path = Path(tmp)
            (path / "variables.tf").write_text((MODULE / "variables.tf").read_text())
            (path / "main.tf").write_text("locals {\n  values = " + values_expression(main) + "\n}\n")
            # Somente valores genéricos; nenhum tfvars, state ou credencial real.
            args = [TF, "console", "-no-color", "-var=host=profiles.example.invalid",
                    "-var=gateway_name=shared", "-var=gateway_namespace=gateway-system"]
            if seconds is not None:
                (path / "test.tfvars.json").write_text(json.dumps({
                    "compactor_blocks_retention_period_seconds": json.loads(seconds)
                }))
                args.append("-var-file=test.tfvars.json")
            validation = subprocess.run([TF, "validate", "-no-color"], cwd=tmp,
                                        text=True, capture_output=True, timeout=30,
                                        env={**os.environ, "CHECKPOINT_DISABLE": "1"})
            if validation.returncode:
                return validation, None
            result = subprocess.run(args, input="nonsensitive(jsonencode(local.values))\n", text=True,
                                    cwd=tmp, capture_output=True, timeout=30,
                                    env={**os.environ, "TF_IN_AUTOMATION": "1", "CHECKPOINT_DISABLE": "1"})
            if result.returncode:
                return result, None
            return result, json.loads(json.loads(result.stdout.strip()))

    def test_default_preserves_all_values(self):
        current, values = self.evaluate()
        baseline, old = self.evaluate(baseline=True)
        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        self.assertEqual(values, old)
        self.assertNotIn("compactor.blocks-retention-period", values["pyroscope"]["extraArgs"])

    def test_explicit_null_preserves_all_values(self):
        result, values = self.evaluate("null")
        baseline, old = self.evaluate(baseline=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        self.assertEqual(values, old)

    def test_opt_in_only_adds_retention_flag(self):
        _, baseline = self.evaluate(baseline=True)
        for seconds in ("0", "1", "3600", "9223372036"):
            with self.subTest(seconds=seconds):
                result, values = self.evaluate(seconds)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(values["pyroscope"]["extraArgs"].pop("compactor.blocks-retention-period"), seconds + "s")
                self.assertEqual(values, baseline)

    def test_invalid_values_rejected_by_terraform(self):
        for seconds in ("-1", "0.5", "9223372037", '"24h"', '""', "true", "[]"):
            with self.subTest(seconds=seconds):
                result, _ = self.evaluate(seconds)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("compactor_blocks_retention_period_seconds", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
