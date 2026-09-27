#!/usr/bin/env python3
"""Inline the image assets into code.js, which is what Figma runs."""
import base64, json, os, pathlib

here = pathlib.Path(__file__).parent
moon = here.parents[1] / "Sources/NotefyApp/Resources/Pet/moon-idle.png"

assets = {
    "moon": base64.b64encode(moon.read_bytes()).decode(),
    "grain": base64.b64encode((here / "grain.png").read_bytes()).decode(),
}
tpl = (here / "code.template.js").read_text()
assert '"__ASSETS__"' in tpl, "marker missing from template"
(here / "code.js").write_text(tpl.replace('"__ASSETS__"', json.dumps(assets)))
print("code.js written,", round(os.path.getsize(here / "code.js") / 1024), "KB")
