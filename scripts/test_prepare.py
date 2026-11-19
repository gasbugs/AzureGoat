import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import shutil

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare", ROOT / "scripts/prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class BuildTests(unittest.TestCase):
    def test_idempotent_build_keeps_sources_and_excludes_old_wheels(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "modules/module-1/resources"
            shutil.copytree(ROOT / "modules/module-1/resources", source, ignore=shutil.ignore_patterns(".python_packages", "__pycache__"))
            old_wheels = source / "azure_function/data/.python_packages"
            old_wheels.mkdir()
            (old_wheels / "old-runtime-wheel.txt").write_text("must not ship")
            def hashes():
                return {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob("*") if p.is_file()}
            before = hashes()
            config = dict(backend_url="https://backend.example", asset_url="https://assets.example/prod", vm_ip="192.0.2.10", cosmos_endpoint="https://cosmos.example", cosmos_key="test-only-key", connection_string="test-only-connection", container_name="test-container")
            prepare.prepare(root, config)
            prepare.prepare(root, {**config, "vm_ip": "192.0.2.11"})
            self.assertEqual(before, hashes())
            self.assertFalse((root / ".build/backend/.python_packages").exists())
            index = (root / ".build/frontend/webapp/index.html").read_text(encoding="utf-8")
            self.assertIn('https://assets.example/prod/webfiles/build/static/', index)
            self.assertNotIn('src="/', index)
            js = (root / ".build/assets/webfiles/build/static/js/main.adc6b28e.js").read_text(encoding="utf-8")
            self.assertIn("https://backend.example", js)
            self.assertNotIn("AZURE_FUNCTION_URL", js)
            self.assertNotIn('"/static', js)
            self.assertIn("HostName 192.0.2.11", (root / ".build/assets/shared/files/.ssh/config.txt").read_text(encoding="utf-8"))
            posts = json.loads((root / ".build/cosmosdb/blog-posts.json").read_text(encoding="utf-8"))
            self.assertTrue(posts[0]["getRequestImageData"].startswith("https://assets.example/prod/images/"))
            settings = json.loads((root / ".build/backend/local.settings.json").read_text(encoding="utf-8"))
            self.assertEqual(settings["Values"]["AZ_DB_PRIMARYKEY"], "test-only-key")


if __name__ == "__main__":
    unittest.main()
