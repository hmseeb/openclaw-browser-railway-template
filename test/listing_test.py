#!/usr/bin/env python3
"""Listing guard for both templates: deployers on Trial (1 GB) or Free (0.5 GB) OOM-loop,
so the description and the top of the readme must say Hobby plan and about 2 GB RAM, and
the templates must pin a versioned image tag that CI pushed (not :latest).

Usage: test/listing_test.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
src = (ROOT / "publish.py").read_text()
desc = dict(re.findall(r'"(OpenClaw \(w/ \w+\))": "([^"]*)"', src))
fails = 0


def check(name, ok):
    global fails
    print(("ok    " if ok else "FAIL  ") + name)
    fails += not ok


for sheet in (ROOT, ROOT / "dashboard"):
    t = json.loads((sheet / "template.json").read_text())
    d = desc.get(t["name"], "")
    head = "\n".join((sheet / "TEMPLATE_OVERVIEW.md").read_text().splitlines()[:6])
    image = next(iter(t["services"].values()))["source"]["image"]
    tag = image.rsplit(":", 1)[1]
    check(f"{t['name']}: description <= 75 chars, no em dash", 0 < len(d) <= 75 and "—" not in d)
    check(f"{t['name']}: description says Hobby and 2 GB", "Hobby" in d and "2 GB" in d)
    check(f"{t['name']}: readme opens with the Hobby plan and 2 GB RAM", "Hobby" in head and "2 GB" in head)
    check(f"{t['name']}: image pinned to <version>-r<revision>",
          re.fullmatch(r"\d{4}\.\d+\.\d+-r" + (ROOT / "REVISION").read_text().strip(), tag) is not None)
    check(f"{t['name']}: pinned version matches the Dockerfile default",
          tag.split("-r")[0] in (ROOT / "Dockerfile").read_text())

# Third listing: same Browser sheet, Telegram-first name, readme and description.
TG = "OpenClaw AI Agent (Telegram + Browser)"
tdesc = dict(re.findall(r'"(OpenClaw [^"]*)": "([^"]*)"', src)).get(TG, "")
tg_md = ROOT / "TEMPLATE_OVERVIEW.telegram.md"
tg = tg_md.read_text() if tg_md.exists() else ""
check(f"{TG}: description <= 75 chars, no em dash", 0 < len(tdesc) <= 75 and "—" not in tdesc)
check(f"{TG}: description is Telegram-first and says Hobby", tdesc.startswith("Telegram") and "Hobby" in tdesc)
tg_head = "\n".join(tg.splitlines()[:6])
check(f"{TG}: readme opens with Hobby plan and 2 GB RAM", "Hobby" in tg_head and "2 GB" in tg_head)
check(f"{TG}: readme has no angle brackets, no >, no em dash", tg and not re.search(r"[<>—]", tg))
check(f"{TG}: readme covers BotFather, pairing and the browser",
      all(w in tg for w in ("BotFather", "/newbot", "pairing", "Chromium", "TELEGRAM_BOT_TOKEN")))
check(f"{TG}: readme is not a copy of the Browser listing",
      tg and tg.splitlines()[0] != (ROOT / "TEMPLATE_OVERVIEW.md").read_text().splitlines()[0])
check(f"{TG}: publish.py selects it by TEMPLATE_NAME", "TEMPLATE_NAME" in src and "TEMPLATE_OVERVIEW" in src)
check(f"{TG}: upsert.py honors TEMPLATE_NAME", "TEMPLATE_NAME" in (ROOT / "upsert.py").read_text())

print(f"\n{fails} failed")
sys.exit(1 if fails else 0)
