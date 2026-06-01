#!/usr/bin/env python3
import argparse
from collections import Counter
from pathlib import Path


PRELUDE = [
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,lan,DIRECT",
    "IP-CIDR,10.0.0.0/8,DIRECT",
    "IP-CIDR,100.64.0.0/10,DIRECT",
    "IP-CIDR,127.0.0.0/8,DIRECT",
    "IP-CIDR,169.254.0.0/16,DIRECT",
    "IP-CIDR,172.16.0.0/12,DIRECT",
    "IP-CIDR,192.168.0.0/16,DIRECT",
    "DOMAIN-SUFFIX,doubleclick.net,REJECT",
    "DOMAIN-SUFFIX,googleadservices.com,REJECT",
    "DOMAIN-SUFFIX,googlesyndication.com,REJECT",
    "DOMAIN-SUFFIX,adservice.google.com,REJECT",
    "DOMAIN-KEYWORD,adservice,REJECT",
    "DOMAIN-SUFFIX,apple-relay.apple.com,PROXY",
    "DOMAIN-SUFFIX,apple-relay.cloudflare.com,PROXY",
    "DOMAIN-SUFFIX,apple-relay.fastly-edge.com,PROXY",
    "DOMAIN-SUFFIX,apple-relay.akamaized.net,PROXY",
    "DOMAIN-SUFFIX,apple-relay.mask.apple-dns.net,PROXY",
    "DOMAIN,copilot.microsoft.com,PROXY",
    "DOMAIN,copilot.bing.com,PROXY",
    "DOMAIN-SUFFIX,githubcopilot.com,PROXY",
    "DOMAIN-SUFFIX,openai.com,PROXY",
    "DOMAIN-SUFFIX,chatgpt.com,PROXY",
    "DOMAIN-SUFFIX,oaistatic.com,PROXY",
    "DOMAIN-SUFFIX,oaiusercontent.com,PROXY",
    "DOMAIN-SUFFIX,sora.com,PROXY",
    "DOMAIN-SUFFIX,anthropic.com,PROXY",
    "DOMAIN-SUFFIX,claude.ai,PROXY",
    "DOMAIN-SUFFIX,perplexity.ai,PROXY",
    "DOMAIN-SUFFIX,poe.com,PROXY",
    "DOMAIN-SUFFIX,gemini.google.com,PROXY",
    "DOMAIN-SUFFIX,generativelanguage.googleapis.com,PROXY",
    "DOMAIN-SUFFIX,aistudio.google.com,PROXY",
    "DOMAIN-SUFFIX,ai.google.dev,PROXY",
    "DOMAIN-SUFFIX,cursor.com,PROXY",
    "DOMAIN-SUFFIX,cursor.sh,PROXY",
    "DOMAIN-SUFFIX,windsurf.com,PROXY",
    "DOMAIN-SUFFIX,codeium.com,PROXY",
    "DOMAIN-SUFFIX,github.com,PROXY",
    "DOMAIN-SUFFIX,githubassets.com,PROXY",
    "DOMAIN-SUFFIX,githubusercontent.com,PROXY",
    "DOMAIN-SUFFIX,github.io,PROXY",
    "DOMAIN-SUFFIX,gitlab.com,PROXY",
    "DOMAIN-SUFFIX,npmjs.com,PROXY",
    "DOMAIN-SUFFIX,registry.npmjs.org,PROXY",
    "DOMAIN-SUFFIX,docker.com,PROXY",
    "DOMAIN-SUFFIX,docker.io,PROXY",
    "DOMAIN-SUFFIX,ghcr.io,PROXY",
    "DOMAIN-SUFFIX,pypi.org,PROXY",
    "DOMAIN-SUFFIX,pythonhosted.org,PROXY",
    "DOMAIN-SUFFIX,rubygems.org,PROXY",
    "DOMAIN-SUFFIX,google.com,PROXY",
    "DOMAIN-SUFFIX,googleapis.com,PROXY",
    "DOMAIN-SUFFIX,gstatic.com,PROXY",
    "DOMAIN-SUFFIX,youtube.com,PROXY",
    "DOMAIN-SUFFIX,youtu.be,PROXY",
    "DOMAIN-SUFFIX,ytimg.com,PROXY",
    "DOMAIN-SUFFIX,googlevideo.com,PROXY",
    "DOMAIN-SUFFIX,telegram.org,PROXY",
    "DOMAIN-SUFFIX,t.me,PROXY",
    "DOMAIN-SUFFIX,x.com,PROXY",
    "DOMAIN-SUFFIX,twitter.com,PROXY",
    "DOMAIN-SUFFIX,facebook.com,PROXY",
    "DOMAIN-SUFFIX,fbcdn.net,PROXY",
    "DOMAIN-SUFFIX,instagram.com,PROXY",
    "DOMAIN-SUFFIX,threads.net,PROXY",
    "DOMAIN-SUFFIX,whatsapp.com,PROXY",
    "DOMAIN-SUFFIX,whatsapp.net,PROXY",
    "DOMAIN-SUFFIX,tiktok.com,PROXY",
    "DOMAIN-SUFFIX,tiktokcdn.com,PROXY",
    "DOMAIN-SUFFIX,ttwstatic.com,PROXY",
    "DOMAIN-SUFFIX,reddit.com,PROXY",
    "DOMAIN-SUFFIX,redditmedia.com,PROXY",
    "DOMAIN-SUFFIX,redd.it,PROXY",
    "DOMAIN-SUFFIX,discord.com,PROXY",
    "DOMAIN-SUFFIX,discord.gg,PROXY",
    "DOMAIN-SUFFIX,discordapp.com,PROXY",
    "DOMAIN-SUFFIX,discordapp.net,PROXY",
    "DOMAIN-SUFFIX,netflix.com,PROXY",
    "DOMAIN-SUFFIX,nflxvideo.net,PROXY",
    "DOMAIN-SUFFIX,nflximg.net,PROXY",
    "DOMAIN-SUFFIX,nflxso.net,PROXY",
    "DOMAIN-SUFFIX,nflxext.com,PROXY",
    "DOMAIN-SUFFIX,spotify.com,PROXY",
]


def extract_rules(text: str) -> list[str]:
    raw = []
    in_rule = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_rule = stripped == "[Rule]"
            continue
        if in_rule:
            raw.append(stripped)

    rules = []
    i = 0
    while i < len(raw):
        line = raw[i]
        if not line or line.startswith("#"):
            i += 1
            continue
        if i + 1 < len(raw) and raw[i + 1] in {",PROXY", ",DIRECT", ",REJECT"} and line.count(",") == 1:
            rules.append(line + raw[i + 1])
            i += 2
            continue
        rules.append(line)
        i += 1
    return rules


def policy(rule: str) -> str:
    parts = [part.strip() for part in rule.split(",")]
    if len(parts) >= 4 and parts[-1] == "no-resolve":
        return parts[-2]
    return parts[-1]


def merge_rules(rules: list[str]) -> list[str]:
    middle = []
    geo = []
    final = []
    for rule in PRELUDE + rules:
        if rule.startswith("FINAL"):
            final.append(rule)
        elif rule.startswith("GEOIP,CN"):
            geo.append(rule)
        else:
            middle.append(rule)

    seen = set()
    merged = []
    for rule in middle + geo + final:
        if rule not in seen:
            merged.append(rule)
            seen.add(rule)

    if "GEOIP,CN,DIRECT" not in merged:
        merged.append("GEOIP,CN,DIRECT")
    if not merged or merged[-1] != "FINAL,PROXY":
        merged = [r for r in merged if not r.startswith("FINAL")]
        merged.append("FINAL,PROXY")
    return merged


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge Shadowrocket rules with a safer modern prelude.")
    parser.add_argument("input", type=Path, help="Existing Shadowrocket .conf file")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output rules-only file")
    args = parser.parse_args()

    rules = merge_rules(extract_rules(args.input.read_text(errors="ignore")))
    args.output.write_text("\n".join(rules) + "\n")
    counts = Counter(policy(rule) for rule in rules)
    print(f"wrote={args.output}")
    print(f"rules={len(rules)}")
    print("policies=" + ",".join(f"{key}:{counts[key]}" for key in sorted(counts)))


if __name__ == "__main__":
    main()
