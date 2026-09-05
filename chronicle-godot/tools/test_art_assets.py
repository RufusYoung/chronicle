import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from check_art_assets import validate


class ArtBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.put("art/README.md", b"provenance")
        self.put("art/reference/.gdignore", b"")
        self.put("export_presets.cfg", b'exclude_filter="art/reference/*,art/source/*,\xe7\xb4\xa0\xe6\x9d\x90\xe5\x8c\x85/*"')
        self.put("art/icons/sample.svg", b"runtime")
        self.put("art/reference/legacy/sample.png", b"original")
        self.put("素材包/sample.png", b"original")
        rows = []
        for path, data, status, source in [
            ("icons/sample.svg", b"runtime", "runtime", ""),
            ("reference/legacy/sample.png", b"original", "reference_only", "素材包/sample.png"),
        ]:
            rows.append({"path": path, "sha256": hashlib.sha256(data).hexdigest(),
                         "status": status, "source": source, "provenance": "README.md"})
        self.put("art/catalog.json", json.dumps({"files": rows}).encode())

    def put(self, path, data):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def test_valid_catalog(self):
        self.assertEqual(validate(self.root), [])

    def test_changed_runtime_asset(self):
        self.put("art/icons/sample.svg", b"changed")
        self.assertTrue(any("changed without catalog" in row for row in validate(self.root)))

    def test_backup_preservation(self):
        self.put("素材包/sample.png", b"modified backup")
        self.assertTrue(any("differs from original" in row for row in validate(self.root)))

    def test_uncatalogued_and_scattered_assets(self):
        self.put("art/icons/new.svg", b"new")
        self.put("scenes/scattered.png", b"new")
        errors = validate(self.root)
        self.assertTrue(any("Uncatalogued" in row for row in errors))
        self.assertTrue(any("outside dedicated" in row for row in errors))

    def test_reference_cannot_enter_formal_surface(self):
        self.put("scripts/rebuild/invalid.gd", b'const X = preload("res://art/reference/legacy/sample.png")')
        self.assertTrue(any("Disallowed formal" in row for row in validate(self.root)))

    def test_export_and_import_exclusions_required(self):
        self.put("export_presets.cfg", b'exclude_filter=""')
        (self.root / "art/reference/.gdignore").unlink()
        errors = validate(self.root)
        self.assertTrue(any("export exclusion" in row for row in errors))
        self.assertTrue(any("excluded from Godot import" in row for row in errors))


if __name__ == "__main__":
    unittest.main(verbosity=2)
