"""Renderiza HCL real em fixtures sem providers, backend, credenciais ou rede.

TF_BIN deve apontar para um Terraform cuja procedência já foi verificada.
Executa somente plan/show sobre locals e variáveis copiados para temporários;
nunca carrega recursos, provisioners, estado ou backend do consumidor.
Requer PyYAML já instalado. Não instala dependências.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import yaml

MODULES = Path(__file__).resolve().parents[1] / "modules"
TF = os.environ.get("TF_BIN")
BASE = {"gateway_name": "public", "gateway_namespace": "istio-system", "kubeconfig_path": "/nonexistent/synthetic"}
ALIAS = {"old.example.test": {"http_listener_name": "http", "https_listener_name": "https", "tls_secret_name": "wildcard-old-example-test-tls"}}


@unittest.skipUnless(TF, "Defina TF_BIN para um executável Terraform verificado")
class DomainCoexistence(unittest.TestCase):
    def render(self, module, values, names, success=True):
        with tempfile.TemporaryDirectory(prefix="coexistence-fixture-") as tmp:
            root = Path(tmp)
            source = (MODULES / module / "main.tf").read_text()
            # Cada módulo começa com um bloco locals autocontido; não copia recursos.
            locals_text = "locals {" + source.split("locals {", 1)[1].split("\nresource ", 1)[0]
            if module == "keycloak":
                # Os dois locals de senha não participam dos manifests testados.
                # Retira apenas referências a random_password, sem copiá-los.
                locals_text = re.sub(r"(?m)^  (admin_password|database_password)\s*=.*\n", "", locals_text)
            self.assertTrue(locals_text.startswith("locals {"))
            self.assertNotRegex(locals_text, r'(?m)^(resource|data|module|provider|terraform)\s')
            (root / "main.tf").write_text(locals_text)
            (root / "variables.tf").write_text((MODULES / module / "variables.tf").read_text())
            outputs = "\n".join(f'output "{n}" {{\n value = local.{n}\n sensitive = true\n}}' for n in names)
            if module == "platform":
                # Reutiliza a precondição real; não duplica a lógica do contrato.
                condition = re.search(r'resource "null_resource" "public_gateway".*?precondition \{(.*?)\n    \}', source, re.S).group(1)
                outputs += '\noutput "contract" {\n value = true\n precondition {' + condition + '\n }\n}\n'
            (root / "outputs.tf").write_text(outputs)
            (root / "input.tfvars.json").write_text(json.dumps(values))
            env = {"PATH": os.defpath, "HOME": tmp, "CHECKPOINT_DISABLE": "1", "TF_INPUT": "0", "TF_IN_AUTOMATION": "1", "TF_CLI_CONFIG_FILE": "/dev/null"}
            result = subprocess.run([TF, f"-chdir={tmp}", "plan", "-input=false", "-refresh=false", "-lock=false", "-var-file=input.tfvars.json", "-out=fixture.plan", "-no-color"], env=env, capture_output=True, text=True, timeout=25)
            if not success:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Error:", result.stderr)
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            show = subprocess.run([TF, f"-chdir={tmp}", "show", "-json", "fixture.plan"], env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(show.returncode, 0, show.stderr)
            plan = json.loads(show.stdout)
            self.assertFalse(plan.get("resource_changes"))
            return {key: entry["value"] for key, entry in plan["planned_values"]["outputs"].items()}

    def platform(self, **changes):
        return dict(domain_name="new.example.test", acme_email="acme@example.test", kubeconfig_path="/nonexistent/synthetic", compartment_ocid="synthetic", region="synthetic", **changes)

    def test_default_single_domain(self):
        result = self.render("platform", self.platform(enable_wildcard_certificate=True), ["public_gateway_manifest", "public_gateway_fallback_manifest"])
        gateway = yaml.safe_load(result["public_gateway_manifest"])
        self.assertEqual([x["name"] for x in gateway["spec"]["listeners"]], ["http", "https"])
        fallback = list(yaml.safe_load_all(result["public_gateway_fallback_manifest"]))[-1]
        self.assertEqual(fallback["spec"]["hostnames"], ["*.new.example.test"])

    def test_four_stable_listeners_and_routes(self):
        result = self.render("platform", self.platform(enable_wildcard_certificate=True, public_gateway_listener_names={"http": "cloudflare-http", "https": "cloudflare-https"}, additional_application_domains=ALIAS), ["public_gateway_manifest", "public_gateway_fallback_manifest", "bookinfo_route_manifest", "bookinfo_service_entry_manifest"])
        listeners = {x["name"]: x for x in yaml.safe_load(result["public_gateway_manifest"])["spec"]["listeners"]}
        self.assertEqual(set(listeners), {"http", "https", "cloudflare-http", "cloudflare-https"})
        self.assertEqual(listeners["http"]["hostname"], "*.old.example.test")
        self.assertEqual(listeners["https"]["tls"]["certificateRefs"][0]["name"], "wildcard-old-example-test-tls")
        self.assertEqual(listeners["cloudflare-https"]["hostname"], "*.new.example.test")
        for key, text in result.items():
            if key in ("contract", "public_gateway_manifest"):
                continue
            obj = list(yaml.safe_load_all(text))[-1]
            field = "hosts" if obj["kind"] == "ServiceEntry" else "hostnames"
            self.assertEqual(len(obj["spec"][field]), 2)
            for parent in obj["spec"].get("parentRefs", []):
                self.assertNotIn("sectionName", parent)
                self.assertEqual(parent["name"], "public")

    def test_http_only_alias_without_certificate(self):
        values = self.platform(enable_wildcard_certificate=False, additional_application_domains={"old.example.test": {"http_listener_name": "legacy-http"}})
        result = self.render("platform", values, ["public_gateway_manifest"])
        self.assertEqual([x["protocol"] for x in yaml.safe_load(result["public_gateway_manifest"])["spec"]["listeners"]], ["HTTP", "HTTP"])

    def test_reject_listener_collision(self):
        self.render("platform", self.platform(additional_application_domains=ALIAS), ["public_gateway_manifest"], success=False)

    def test_reject_primary_domain_as_alias(self):
        self.render("platform", self.platform(additional_application_domains={"new.example.test": {"http_listener_name": "other-http"}}), ["public_gateway_manifest"], success=False)

    def test_reject_https_without_secret(self):
        self.render("platform", self.platform(additional_application_domains={"old.example.test": {"http_listener_name": "other-http", "https_listener_name": "other-https"}}), ["public_gateway_manifest"], success=False)

    def test_application_routes_and_service_entries(self):
        cases = {
            "keycloak": (dict(BASE, host="auth.new.example.test", database_host="192.0.2.10", additional_hosts=["auth.old.example.test"]), ["route_manifest", "service_entry_manifest"]),
            "argocd": (dict(BASE, host="argocd.new.example.test", additional_hosts=["argocd.old.example.test"]), ["route_manifest", "service_entry_manifest"]),
            "profiling": (dict(BASE, host="pyroscope.new.example.test", additional_hosts=["pyroscope.old.example.test"], additional_egress_hosts=["auth.old.example.test"]), ["route_manifest", "service_entry_manifest"]),
            "observability": (dict(BASE, hosts={x: f"{x}.new.example.test" for x in ["kiali", "grafana", "tracing", "prometheus"]}, monitoring_token="synthetic", enable_prometheus_route=True, additional_hosts={x: [f"{x}.old.example.test"] for x in ["kiali", "grafana", "tracing", "prometheus"]}, additional_egress_hosts=["auth.old.example.test"]), ["kiali_route_manifest", "grafana_route_manifest", "tracing_route_manifest", "prometheus_route_manifest", "public_host_service_entry_manifest", "oauth_public_host_service_entry_manifest"]),
            "lab-apps": (dict(BASE, hosts={"grafana": "grafana.new.example.test", "opentelemetry_loadgen": "loadgen.new.example.test"}, additional_hosts={"opentelemetry_demo": ["otel-demo.old.example.test"], "opentelemetry_loadgen": ["loadgen.old.example.test"]}, additional_egress_hosts=["auth.old.example.test"]), ["opentelemetry_demo_route_manifest", "opentelemetry_loadgen_route_manifest", "opentelemetry_demo_service_entry_manifest", "opentelemetry_loadgen_service_entry_manifest"]),
        }
        count = 0
        for module, (values, names) in cases.items():
            with self.subTest(module=module):
                results = self.render(module, values, names)
                for text in results.values():
                    obj = yaml.safe_load(text)
                    if obj["kind"] == "HTTPRoute":
                        count += 1
                        self.assertEqual(len(obj["spec"]["hostnames"]), 2)
                        self.assertTrue(any(x.endswith(".new.example.test") for x in obj["spec"]["hostnames"]))
                        self.assertTrue(any(x.endswith(".old.example.test") for x in obj["spec"]["hostnames"]))
                        self.assertTrue(all("sectionName" not in x for x in obj["spec"]["parentRefs"]))
                    else:
                        self.assertTrue(any(x.endswith(".old.example.test") for x in obj["spec"]["hosts"]))
        self.assertEqual(count, 9)


if __name__ == "__main__":
    unittest.main()
