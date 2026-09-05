"""Validate the art catalog and the boundary between runtime and reference art."""

import hashlib
import json
from pathlib import Path
import re
import sys

MEDIA = {".png", ".jpg", ".jpeg", ".svg", ".webp", ".ttf", ".otf",
         ".ogg", ".wav", ".mp3", ".glb", ".gltf", ".blend", ".psd"}


def validate(project: Path) -> list[str]:
    errors = []
    art = project / "art"
    catalog = json.loads((art / "catalog.json").read_text(encoding="utf-8-sig"))
    listed = set()
    for entry in catalog["files"]:
        relative = entry["path"]
        path = (art / relative).resolve()
        if not path.is_relative_to(art.resolve()) or relative in listed:
            errors.append(f"Invalid or duplicate catalog path: {relative}")
            continue
        listed.add(relative)
        if not path.is_file():
            errors.append(f"Missing art: {relative}")
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            errors.append(f"Art changed without catalog review: {relative}")
        if entry["status"] == "reference_only":
            source = project / entry["source"]
            if not relative.startswith("reference/"):
                errors.append(f"Uncleared art outside quarantine: {relative}")
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                errors.append(f"Backup copy differs from original: {relative}")
        elif entry["status"] != "runtime" or not entry.get("provenance"):
            errors.append(f"Missing release classification: {relative}")
        if not (art / entry["provenance"]).is_file():
            errors.append(f"Missing provenance: {relative}")
    for path in art.rglob("*"):
        if path.is_file() and path.suffix.lower() in MEDIA and path.relative_to(art).as_posix() not in listed:
            errors.append(f"Uncatalogued art: {path.relative_to(art)}")
    exempt = (".godot/", "_archive/", "素材包/", "texts/reports/", "art/")
    for path in project.rglob("*"):
        relative = path.relative_to(project).as_posix()
        if path.is_file() and path.suffix.lower() in MEDIA and not relative.startswith(exempt):
            errors.append(f"Art outside dedicated directory: {relative}")
    if not (art / "reference/.gdignore").is_file():
        errors.append("Reference assets must be excluded from Godot import")
    preset = (project / "export_presets.cfg").read_text(encoding="utf-8")
    for pattern in ("art/reference/*", "art/source/*", "素材包/*"):
        if pattern not in preset:
            errors.append(f"Missing export exclusion: {pattern}")
    # Formal scenes and scripts must never load the quarantined backup library.
    for folder in ("scripts/rebuild", "scenes/rebuild"):
        for path in (project / folder).rglob("*"):
            if path.suffix not in (".gd", ".tscn"):
                continue
            for ref in re.findall(r'res://[^"\s]+', path.read_text(encoding="utf-8-sig")):
                if ref.startswith(("res://素材包/", "res://art/reference/", "res://assets/")):
                    errors.append(f"Disallowed formal resource: {path.name}: {ref}")
                if ref.startswith("res://art/") and not (project / ref[6:]).is_file():
                    errors.append(f"Missing formal art reference: {ref}")
    return errors


if __name__ == "__main__":
    project = Path(__file__).resolve().parents[1]
    problems = validate(project)
    for problem in problems:
        print(problem)
    print(f"ART_ASSETS_RESULT {'FAIL' if problems else 'PASS'}")
    sys.exit(bool(problems))
