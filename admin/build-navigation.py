"""Keep the offline Admin navigation SVGs identical to the React source."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent
icons = json.loads((here / "src/navigation-icons.json").read_text(encoding="utf-8"))
source = "// Generated from admin/src/navigation-icons.json.\nwindow.AdminNavIcons = "
source += json.dumps(icons, ensure_ascii=False) + ";\n"
source += """window.AdminNavIcon = (name) => '<svg class="admin-nav-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + (window.AdminNavIcons[name] || window.AdminNavIcons.dashboard).map(d => '<path d="' + d + '"/>').join('') + '</svg>';\n"""
(here.parent / "preview/admin/nav-icons.js").write_text(source, encoding="utf-8")
