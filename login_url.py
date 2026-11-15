#!/usr/bin/env python3
"""Print the OPENCLAW_LOGIN_URL of a deployed project (contains the gateway token; do not log it).

Usage: login_url.py <projectId>
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.claude/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

pid = sys.argv[1]
p = rw.gql("""query($id:String!){project(id:$id){environments{edges{node{id name}}}
  services{edges{node{id name}}}}}""", {"id": pid})["project"]
env = next(e["node"]["id"] for e in p["environments"]["edges"] if e["node"]["name"] == "production")
sid = next(s["node"]["id"] for s in p["services"]["edges"] if s["node"]["name"] == "OpenClaw")
v = rw.gql("query($p:String!,$e:String!,$s:String!){variables(projectId:$p,environmentId:$e,serviceId:$s)}",
           {"p": pid, "e": env, "s": sid})["variables"]
print(v["OPENCLAW_LOGIN_URL"])
