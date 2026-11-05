"""Contrato offline do wrapper local: clone isolado, Bash e Python, sem Terraform."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
IS_LIBRARY = (SOURCE / "modules").is_dir()


class ValidateLocalTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="validate-local-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.repo = self.work / "checkout with spaces"
        scripts = self.repo / "scripts"
        scripts.mkdir(parents=True)
        for name in ("validate.sh", "env.sh"):
            shutil.copyfile(SOURCE / "scripts" / name, scripts / name)
        self.roots = [self.repo]
        if IS_LIBRARY:
            self.roots = [self.repo / "modules" / name for name in ("a module", "z-module")]
            for root in self.roots:
                root.mkdir(parents=True)
            (self.repo / "modules" / "not-a-directory").write_text("ignored")
        self.log = self.work / "calls.jsonl"
        self.cli = self.work / "fake terraform"
        self.cli.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['VALIDATE_TEST_LOG'], 'a') as log:\n"
            "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "assert os.environ['CHECKPOINT_DISABLE'] == '1'\n"
            "assert os.environ['TF_INPUT'] == '0'\n"
            "assert os.environ['TF_IN_AUTOMATION'] == '1'\n"
            "key = 'VALIDATE_INIT_EXIT' if sys.argv[2] == 'init' else 'VALIDATE_EXIT'\n"
            "sys.exit(int(os.environ.get(key, '0')))\n"
        )
        self.cli.chmod(0o700)
        # Não herdar credenciais, opções Terraform nem flags de teste do chamador.
        self.env = {
            "PATH": os.defpath,
            "HOME": str(self.work),
            "LC_ALL": "C",
            "TF_BIN": str(self.cli),
            "VALIDATE_TEST_LOG": str(self.log),
        }

    def run_script(self, *args, **overrides):
        self.log.unlink(missing_ok=True)
        result = subprocess.run(
            [shutil.which("bash"), str(self.repo / "scripts/validate.sh"), *args],
            cwd=self.work, env=dict(self.env, **overrides),
            text=True, capture_output=True, timeout=10,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_default_only_validates_anchored_roots(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [[f"-chdir={root}", "validate"] for root in self.roots])

    def test_init_is_explicit_and_precedes_each_validation(self):
        result, calls = self.run_script("--init")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = []
        for root in self.roots:
            expected.extend([
                [f"-chdir={root}", "init", "-backend=false", "-input=false"],
                [f"-chdir={root}", "validate"],
            ])
        self.assertEqual(calls, expected)

    def test_validate_failure_stops_iteration(self):
        result, calls = self.run_script(VALIDATE_EXIT="23")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(len(calls), 1)
        self.assertIn("review initialization separately", result.stderr)

    def test_init_failure_never_validates(self):
        result, calls = self.run_script("--init", VALIDATE_INIT_EXIT="24")
        self.assertEqual(result.returncode, 24)
        self.assertEqual(calls, [[f"-chdir={self.roots[0]}", "init", "-backend=false", "-input=false"]])

    def test_validate_failure_after_successful_init_stops_iteration(self):
        result, calls = self.run_script("--init", VALIDATE_EXIT="25")
        self.assertEqual(result.returncode, 25)
        self.assertEqual([call[1] for call in calls], ["init", "validate"])

    def test_missing_cli_fails_without_install(self):
        result, calls = self.run_script(TF_BIN=str(self.work / "absent"))
        self.assertEqual(result.returncode, 127)
        self.assertIn("nothing was installed", result.stderr)
        self.assertEqual(calls, [])

    def test_usage_never_invokes_cli(self):
        for args, code in [
            (("--help",), 0), (("-h",), 0), (("--unknown",), 2),
            (("--init", "--init"), 2), (("--help", "--init"), 2),
            (("-h", "extra"), 2),
        ]:
            with self.subTest(args=args):
                result, calls = self.run_script(*args)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(calls, [])

    @unittest.skipUnless(IS_LIBRARY, "Consumidor valida a raiz, não enumera módulos")
    def test_empty_module_tree_is_failure_without_cli_calls(self):
        shutil.rmtree(self.repo / "modules")
        (self.repo / "modules").mkdir()
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("No module directories found", result.stderr)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
