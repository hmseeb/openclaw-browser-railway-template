#!/usr/bin/env python3
"""Set name/icon/description (the slug comes from the stored name), then publish in Auromations.

Usage: publish.py              # OpenClaw (w/ Browser)
       SHEET_DIR=dashboard publish.py   # OpenClaw (w/ Dashboard)
"""
import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.claude/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

HERE = pathlib.Path(os.environ.get("SHEET_DIR") or pathlib.Path(__file__).parent)
WS = "fc4796db-2c6c-4354-a564-d4a1d900af53"
TID = (HERE / "template-id").read_text().strip()
NAME = json.loads((HERE / "template.json").read_text())["name"]
DESC = {
    "OpenClaw (w/ Browser)": "OpenClaw agent with Chromium and backups. Needs Hobby plan, about 2 GB RAM",
    "OpenClaw (w/ Dashboard)": "OpenClaw agent with dashboard and backups. Needs Hobby plan, about 2 GB RAM",
}[NAME]
ICON = "https://openclaw.ai/favicon.svg"
assert len(DESC) <= 75 and "\u2014" not in DESC
readme = (HERE / "TEMPLATE_OVERVIEW.md").read_text()
assert "\u2014" not in readme

rw.gql("mutation($id:String!,$i:TemplateUpsertSettingsInput!){templateUpsertSettings(id:$id,input:$i){id}}",
       {"id": TID, "i": {"workspaceId": WS, "name": NAME, "image": ICON, "description": DESC}}, internal=True)
got = rw.gql("query($id:String!){template(id:$id){name}}", {"id": TID})["template"]["name"]
assert got == NAME, got
r = rw.gql("mutation($id:String!,$i:TemplatePublishInput!){templatePublish(id:$id,input:$i){id code status}}",
           {"id": TID, "i": {"workspaceId": WS, "category": "AI/ML", "description": DESC, "image": ICON, "readme": readme}})
print(r)
