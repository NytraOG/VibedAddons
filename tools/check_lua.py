"""Prueft alle Addons in AddOns/ mit echtem Lua 5.1 (via lupa) auf Syntaxfehler
und ob jede in der .toc gelistete Datei existiert.

Aufruf:  tools/.venv/Scripts/python tools/check_lua.py
Einrichtung (einmalig):  python -m venv tools/.venv && tools/.venv/Scripts/python -m pip install lupa
"""

import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = os.path.join(ROOT, "AddOns")

lua = lua51.LuaRuntime()
compile_chunk = lua.eval("function(src, name) local f, err = loadstring(src, name); return err end")


def check_toc(addon_dir, toc_path):
    errors = []
    with open(toc_path, encoding="utf-8-sig") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            path = os.path.join(addon_dir, line.split()[0].replace("\\", os.sep))
            if not os.path.isfile(path):
                errors.append("%s:%d: Datei fehlt: %s" % (os.path.relpath(toc_path, ROOT), lineno, line))
    return errors


def main():
    errors = []
    checked = 0
    for addon in sorted(os.listdir(ADDONS)):
        addon_dir = os.path.join(ADDONS, addon)
        if not os.path.isdir(addon_dir):
            continue
        for name in os.listdir(addon_dir):
            if name.endswith(".toc"):
                errors += check_toc(addon_dir, os.path.join(addon_dir, name))
        for dirpath, _, filenames in os.walk(addon_dir):
            for name in filenames:
                if not name.endswith(".lua"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                with open(path, encoding="utf-8") as f:
                    err = compile_chunk(f.read(), "@" + rel)
                checked += 1
                if err:
                    errors.append(err)
    for e in errors:
        print(e)
    print("%d Lua-Dateien geprüft, %d Fehler" % (checked, len(errors)))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
