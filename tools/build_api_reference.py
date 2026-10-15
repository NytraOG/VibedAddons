"""Erzeugt docs/api-reference.html aus Blizzards generierter API-Dokumentation.

Quelle: wow-ui-source (Branch "forever") -> Interface/AddOns/Blizzard_APIDocumentationGenerated
Zusaetzlich wird Blizzards eigener UI-Code nach Aufrufbeispielen indexiert.

Aufruf:  python tools/build_api_reference.py
"""

import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_SOURCE = os.path.join(ROOT, "wow-ui-source")
DOC_DIR = os.path.join(UI_SOURCE, "Interface", "AddOns", "Blizzard_APIDocumentationGenerated")
TEMPLATE = os.path.join(ROOT, "tools", "api-reference.template.html")
OUTPUT = os.path.join(ROOT, "docs", "api-reference.html")

MAX_EXAMPLES = 4
SKIP_DIRS = {"Blizzard_APIDocumentationGenerated", "Blizzard_APIDocumentation"}

# --- Minimaler Parser fuer Lua-Tabellenliterale -------------------------------

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<number>-?(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][-+]?\d+)?))
  | (?P<ident>[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)
  | (?P<punct>[{}=,;():\[\]])
  | (?P<op>[-+*/%^])
""", re.VERBOSE | re.DOTALL)


def tokenize(text):
    pos = 0
    out = []
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise ValueError("Unerwartetes Zeichen an Position %d: %r" % (pos, text[pos:pos + 20]))
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "comment", "eq"):
            continue
        out.append((kind, m.group(kind)))
    return out


def unquote(s):
    body = s[1:-1]
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


class Parser:
    def __init__(self, tokens):
        self.t = tokens
        self.i = 0

    def peek(self, offset=0):
        j = self.i + offset
        return self.t[j] if j < len(self.t) else (None, None)

    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok

    def expect(self, value):
        kind, val = self.next()
        if val != value:
            raise ValueError("Erwartet %r, gefunden %r" % (value, val))

    def value(self):
        v = self.primary()
        if self.peek()[0] != "op":
            return v
        # Rechenausdruck (z.B. bei Konstanten) als Text uebernehmen
        parts = [str(v)]
        while self.peek()[0] == "op":
            parts.append(self.next()[1])
            parts.append(str(self.primary()))
        return " ".join(parts)

    def primary(self):
        kind, val = self.next()
        if val == "{":
            return self.table()
        if kind == "string":
            return unquote(val)
        if kind == "number":
            return int(val, 16) if val.lower().startswith(("0x", "-0x")) else (float(val) if re.search(r"[.eE]", val) else int(val))
        if kind == "ident":
            return {"true": True, "false": False, "nil": None}.get(val, val)
        raise ValueError("Unerwarteter Wert %r" % val)

    def table(self):
        items, keyed = [], {}
        while True:
            kind, val = self.peek()
            if val == "}":
                self.next()
                break
            if kind == "ident" and self.peek(1)[1] == "=":
                self.next()
                self.next()
                keyed[val] = self.value()
            elif val == "[":
                self.next()
                key = self.value()
                self.expect("]")
                self.expect("=")
                keyed[str(key)] = self.value()
            else:
                items.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.next()
        if keyed and items:
            keyed["__array"] = items
            return keyed
        return keyed if keyed else items


def parse_doc_file(path):
    with open(path, encoding="utf-8") as f:
        tokens = tokenize(f.read())
    tables = []
    p = Parser(tokens)
    while p.i < len(tokens):
        kind, val = p.next()
        if val == "local" and p.peek()[0] == "ident" and p.peek(1)[1] == "=" and p.peek(2)[1] == "{":
            local_name = p.next()[1]
            p.next()
            p.next()
            table = p.table()
            if isinstance(table, dict):
                table.setdefault("Name", local_name)
                tables.append(table)
    return tables


# --- Umwandlung ins kompakte Datenmodell -------------------------------------

def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def doc_text(entry):
    return " ".join(str(x) for x in as_list(entry.get("Documentation"))) or None


def extra_flags(entry, known):
    flags = {}
    for k, v in entry.items():
        if k in known:
            continue
        if isinstance(v, list):
            v = ", ".join(str(x) for x in v)
        flags[k] = v
    return flags or None


PARAM_KNOWN = {"Name", "Type", "InnerType", "Nilable", "Default", "Mixin", "Documentation", "EnumValue", "Value"}


def param(p):
    out = {"n": p.get("Name"), "t": p.get("Type")}
    if p.get("InnerType"):
        out["in"] = p["InnerType"]
    if p.get("Nilable"):
        out["nil"] = 1
    if "Default" in p:
        out["def"] = p["Default"]
    if p.get("Mixin"):
        out["mx"] = p["Mixin"]
    if "EnumValue" in p:
        out["v"] = p["EnumValue"]
    if "Value" in p:
        out["v"] = p["Value"]
    d = doc_text(p)
    if d:
        out["d"] = d
    f = extra_flags(p, PARAM_KNOWN)
    if f:
        out["f"] = f
    return out


FN_KNOWN = {"Name", "Type", "Arguments", "Returns", "Documentation"}
EV_KNOWN = {"Name", "Type", "LiteralName", "Payload", "Documentation"}
TB_KNOWN = {"Name", "Type", "Fields", "Values", "Arguments", "Documentation"}
SYS_KNOWN = {"Name", "Type", "Namespace", "Functions", "Events", "Tables", "Predicates", "Documentation"}


def convert_system(raw, filename):
    sys_ = {
        "n": raw.get("Name"),
        "ns": raw.get("Namespace"),
        "t": raw.get("Type"),
        "file": filename,
        "fn": [],
        "ev": [],
        "tb": [],
    }
    d = doc_text(raw)
    if d:
        sys_["d"] = d
    f = extra_flags(raw, SYS_KNOWN)
    if f:
        sys_["f"] = f
    for fn in as_list(raw.get("Functions")):
        o = {"n": fn["Name"], "a": [param(x) for x in as_list(fn.get("Arguments"))],
             "r": [param(x) for x in as_list(fn.get("Returns"))]}
        d = doc_text(fn)
        if d:
            o["d"] = d
        f = extra_flags(fn, FN_KNOWN)
        if f:
            o["f"] = f
        sys_["fn"].append(o)
    for ev in as_list(raw.get("Events")):
        o = {"n": ev["Name"], "lit": ev.get("LiteralName"), "p": [param(x) for x in as_list(ev.get("Payload"))]}
        d = doc_text(ev)
        if d:
            o["d"] = d
        f = extra_flags(ev, EV_KNOWN)
        if f:
            o["f"] = f
        sys_["ev"].append(o)
    for tb in as_list(raw.get("Tables")):
        rows = as_list(tb.get("Fields")) or as_list(tb.get("Values")) or as_list(tb.get("Arguments"))
        o = {"n": tb["Name"], "t": tb.get("Type"), "fl": [param(x) for x in rows]}
        d = doc_text(tb)
        if d:
            o["d"] = d
        f = extra_flags(tb, TB_KNOWN)
        if f:
            o["f"] = f
        sys_["tb"].append(o)
    return sys_


# --- Aufrufbeispiele aus Blizzards UI-Code ------------------------------------

NS_CALL_RE = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(")
GLOBAL_CALL_RE = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(")
METHOD_CALL_RE = re.compile(r":([A-Za-z_]\w*)\s*\(")
EVENT_RE = re.compile(r"\"([A-Z][A-Z0-9_]{2,})\"")


def index_examples(ns_keys, global_keys, method_keys, event_keys):
    found = defaultdict(lambda: {"c": 0, "ex": [], "files": set()})

    def add(key, rel, lineno, line):
        e = found[key]
        e["c"] += 1
        if len(e["ex"]) < MAX_EXAMPLES and rel not in e["files"]:
            e["files"].add(rel)
            e["ex"].append([rel, lineno, line.strip()[:200]])

    base = os.path.join(UI_SOURCE, "Interface")
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(".lua"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, UI_SOURCE).replace(os.sep, "/")
            with open(path, encoding="utf-8", errors="replace") as f:
                for lineno, line in enumerate(f, 1):
                    stripped = line.lstrip()
                    if stripped.startswith("--"):
                        continue
                    for m in NS_CALL_RE.finditer(line):
                        key = m.group(1) + "." + m.group(2)
                        if key in ns_keys:
                            add(key, rel, lineno, line)
                    for m in GLOBAL_CALL_RE.finditer(line):
                        if m.group(1) in global_keys:
                            add(m.group(1), rel, lineno, line)
                    for m in METHOD_CALL_RE.finditer(line):
                        key = ":" + m.group(1)
                        if key in method_keys:
                            add(key, rel, lineno, line)
                    for m in EVENT_RE.finditer(line):
                        if m.group(1) in event_keys:
                            add(m.group(1), rel, lineno, line)
    return {k: {"c": v["c"], "ex": v["ex"]} for k, v in found.items()}


def main():
    if not os.path.isdir(DOC_DIR):
        sys.exit("Doku-Ordner nicht gefunden: %s\nErst wow-ui-source klonen (siehe README.md)." % DOC_DIR)

    systems = []
    for name in sorted(os.listdir(DOC_DIR)):
        if not name.endswith(".lua"):
            continue
        for raw in parse_doc_file(os.path.join(DOC_DIR, name)):
            systems.append(convert_system(raw, name))

    ns_keys, global_keys, method_keys, event_keys = set(), set(), set(), set()
    for s in systems:
        for fn in s["fn"]:
            if s["t"] == "ScriptObject":
                method_keys.add(":" + fn["n"])
            elif s["ns"]:
                ns_keys.add(s["ns"] + "." + fn["n"])
            else:
                global_keys.add(fn["n"])
        for ev in s["ev"]:
            if ev["lit"]:
                event_keys.add(ev["lit"])

    examples = index_examples(ns_keys, global_keys, method_keys, event_keys)

    version_file = os.path.join(UI_SOURCE, "version.txt")
    version = open(version_file, encoding="utf-8").read().strip() if os.path.exists(version_file) else "?"

    data = {"version": version, "systems": systems, "examples": examples}
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")

    with open(TEMPLATE, encoding="utf-8") as f:
        html = f.read()
    html = html.replace("/*__DATA__*/null", payload)

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write(html)

    n_fn = sum(len(s["fn"]) for s in systems)
    n_ev = sum(len(s["ev"]) for s in systems)
    n_tb = sum(len(s["tb"]) for s in systems)
    print("Build %s: %d Systeme, %d Funktionen, %d Events, %d Typen, %d Beispiel-Keys"
          % (version, len(systems), n_fn, n_ev, n_tb, len(examples)))
    print("Geschrieben: %s (%.1f MB)" % (OUTPUT, os.path.getsize(OUTPUT) / 1e6))


if __name__ == "__main__":
    main()
