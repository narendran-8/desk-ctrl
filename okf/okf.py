#!/usr/bin/env python3
"""OKF helper: keeps the knowledge files healthy and cheap to update. Standard library only.

  python3 okf/okf.py check                 validate everything (run it before finishing a task)
  python3 okf/okf.py stale                 docs whose source files changed after the doc's `updated:`
  python3 okf/okf.py log "Title" [-d DOC,DOC] [-f FILE,FILE] [-t "tests"] [-n "note"]
                                           add an entry to LATEST.md (rotates old ones into CHANGELOG.md),
                                           stamp the listed docs as updated today, rebuild okf.json
  python3 okf/okf.py touch DOC [DOC ...]   stamp docs as updated today (no log entry)
  python3 okf/okf.py manifest              rebuild okf.json (machine-readable index)

Run from anywhere: paths are relative to the project root (the folder above okf/).
"""
import datetime, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
KEEP_LATEST = 12          # entries kept in LATEST.md; older ones move to CHANGELOG.md
MAX_LINES = 160           # budget per doc (a doc is read whole, so keep it small)
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
SPECIAL = {"LATEST.md", "CHANGELOG.md"}   # no front matter budget checks on the log files' length


def docs():
    return sorted(f for f in os.listdir(HERE) if f.endswith(".md"))


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def write(name, text):
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        f.write(text)


def front(text):
    m = FM.match(text)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            v = v.strip()
            if v.startswith("[") and v.endswith("]"):
                v = [x.strip() for x in v[1:-1].split(",") if x.strip()]
            meta[k.strip()] = v
    return meta, text[m.end():]


def today():
    return datetime.date.today().isoformat()


def set_updated(name, day):
    text = read(name)
    if FM.match(text):
        text = re.sub(r"(?m)^updated:.*$", f"updated: {day}", text, count=1)
        write(name, text)


def approx_tokens(text):
    return max(1, len(text) // 4)


def manifest():
    out = []
    for name in docs():
        text = read(name)
        meta, body = front(text)
        out.append({
            "file": name,
            "id": meta.get("id", name[:-3].lower()),
            "summary": meta.get("summary", ""),
            "updated": meta.get("updated", ""),
            "sources": meta.get("sources", []),
            "lines": text.count("\n") + 1,
            "approx_tokens": approx_tokens(text),
        })
    with open(os.path.join(HERE, "okf.json"), "w", encoding="utf-8") as f:
        json.dump({"project": "DeskCtrl", "generated": today(), "docs": out}, f, indent=1)
        f.write("\n")
    return out


def check():
    problems = []
    names = docs()
    index = read("INDEX.md") if "INDEX.md" in names else ""
    for name in names:
        text = read(name)
        meta, _ = front(text)
        lines = text.count("\n") + 1
        for key in ("id", "summary", "updated"):
            if not meta.get(key):
                problems.append(f"{name}: front matter lacks '{key}'")
        if name not in SPECIAL and lines > MAX_LINES:
            problems.append(f"{name}: {lines} lines (budget {MAX_LINES}) - split it or trim it")
        if name != "INDEX.md" and name not in index:
            problems.append(f"{name}: not listed in INDEX.md")
        for src in meta.get("sources", []) if isinstance(meta.get("sources", []), list) else []:
            if not os.path.exists(os.path.join(ROOT, src)):
                problems.append(f"{name}: source '{src}' does not exist (renamed or removed?)")
        if meta.get("updated") and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", meta["updated"]):
            problems.append(f"{name}: 'updated' must be YYYY-MM-DD")
    latest = read("LATEST.md") if "LATEST.md" in names else ""
    n = len(re.findall(r"(?m)^## \d{4}-\d{2}-\d{2}", latest))
    if n > KEEP_LATEST:
        problems.append(f"LATEST.md has {n} entries (keep {KEEP_LATEST}); run 'log' or move the oldest to CHANGELOG.md")
    for p in problems:
        print("PROBLEM:", p)
    stale_docs = stale(quiet=True)
    for name, src in stale_docs:
        print(f"STALE?  {name}: {src} changed after the doc's 'updated' date")
    if not problems:
        print(f"OKF ok: {len(names)} docs, LATEST has {n} entries")
    return 1 if problems else 0


def stale(quiet=False):
    found = []
    for name in docs():
        meta, _ = front(read(name))
        day = meta.get("updated")
        srcs = meta.get("sources", [])
        if not day or not isinstance(srcs, list):
            continue
        try:
            limit = datetime.datetime.strptime(day, "%Y-%m-%d") + datetime.timedelta(days=1)
        except ValueError:
            continue
        for src in srcs:
            path = os.path.join(ROOT, src)
            if os.path.exists(path) and datetime.datetime.fromtimestamp(os.path.getmtime(path)) > limit:
                found.append((name, src))
                break
    if not quiet:
        for name, src in found:
            print(f"{name}: {src} is newer than the doc")
        if not found:
            print("no stale docs")
    return found


def log(title, docs_touched, files, tests, note):
    day = today()
    entry = [f"## {day} · {title}"]
    if files:
        entry.append("- files: " + ", ".join(files))
    if docs_touched:
        entry.append("- docs: " + ", ".join(docs_touched))
    if tests:
        entry.append("- tests: " + tests)
    if note:
        entry.append("- note: " + note)
    entry = "\n".join(entry) + "\n"
    text = read("LATEST.md")
    meta_end = FM.match(text).end()
    head, body = text[:meta_end], text[meta_end:]
    # body = intro lines, then entries starting with "## "
    first = body.find("\n## ")
    intro, entries = (body, "") if first < 0 else (body[:first + 1], body[first + 1:])
    parts = re.split(r"(?m)^(?=## \d{4}-\d{2}-\d{2})", entries)
    parts = [p for p in parts if p.strip()]
    parts.insert(0, entry + "\n")
    keep, spill = parts[:KEEP_LATEST], parts[KEEP_LATEST:]
    write("LATEST.md", head + intro + "".join(keep))
    set_updated("LATEST.md", day)
    if spill:
        ch = read("CHANGELOG.md")
        cm = FM.match(ch).end()
        chb = ch[cm:]
        marker = chb.find("\n## ")
        chb = chb[:marker + 1] + "".join(spill) + chb[marker + 1:] if marker >= 0 else chb + "".join(spill)
        write("CHANGELOG.md", ch[:cm] + chb)
        set_updated("CHANGELOG.md", day)
    for d in docs_touched:
        d = d if d.endswith(".md") else d + ".md"
        if d in docs():
            set_updated(d, day)
        else:
            print(f"warning: no such doc {d}")
    manifest()
    print(f"logged: {title} ({len(keep)} in LATEST, {len(spill)} moved to CHANGELOG)")


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[1]
    if cmd == "check":
        manifest()
        return check()
    if cmd == "stale":
        stale()
        return 0
    if cmd == "manifest":
        manifest()
        print("okf.json rebuilt")
        return 0
    if cmd == "touch":
        for d in argv[2:]:
            set_updated(d if d.endswith(".md") else d + ".md", today())
        manifest()
        return 0
    if cmd == "log":
        args = argv[2:]
        if not args:
            print("usage: log \"Title\" [-d docs] [-f files] [-t tests] [-n note]")
            return 2
        title, opts = args[0], {"-d": "", "-f": "", "-t": "", "-n": ""}
        i = 1
        while i < len(args) - 1:
            if args[i] in opts:
                opts[args[i]] = args[i + 1]
                i += 2
            else:
                i += 1
        split = lambda s: [x.strip() for x in s.split(",") if x.strip()]
        log(title, split(opts["-d"]), split(opts["-f"]), opts["-t"], opts["-n"])
        return 0
    print("unknown command; try --help")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
