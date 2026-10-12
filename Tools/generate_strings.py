#!/usr/bin/env python3
"""Writes Pitwall/Resources/Localizable.xcstrings (source: Dutch, plus English)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from strings_en import EN
out = {"sourceLanguage": "nl", "version": "1.0", "strings": {}}
for key in sorted(EN):
    out["strings"][key] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": EN[key]}}}}
path = os.path.join(os.path.dirname(__file__), "..", "Pitwall", "Resources", "Localizable.xcstrings")
with open(path, "w") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)
print("Wrote", len(EN), "strings")
