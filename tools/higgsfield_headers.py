"""Print the authenticated Higgsfield Blender token for Codex MCP."""
import json
from pathlib import Path

AUTH = Path(r"C:/Users/ramon/AppData/Local/Higgsfield/Blender/Data/auth.json")
data = json.loads(AUTH.read_text(encoding="utf-8"))
token = data.get("access_token", "").strip()
if not token:
    raise SystemExit("Higgsfield Blender session has no access token")
print(json.dumps({"Authorization": f"Bearer {token}"}))
