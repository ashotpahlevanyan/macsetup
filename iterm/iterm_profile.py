#!/usr/bin/env python3
"""Read/write the iTerm2 default profile.

  export OUT.json            < `defaults export com.googlecode.iterm2 -`
      Save the current default profile (minus machine-specific keys) as JSON.

  apply BASE.json [--scheme S.json] [--font PS_NAME] [--size N] [--dir PATH]
                             < `defaults export com.googlecode.iterm2 -`
      Print a new prefs plist (to stdout) whose default profile is BASE with
      the color scheme / font / start directory applied. Feed the result to
      `defaults import com.googlecode.iterm2 -`.

The profile goes into the regular preferences (not a Dynamic Profile), so
edits you make later in iTerm2's UI are kept and `newmac capture` sees them.
"""
import argparse
import json
import plistlib
import sys

GUID = "newmac-default-profile"
DROP = {"Guid", "Default Bookmark", "Working Directory", "Custom Directory",
        "Bound Hosts", "Dynamic Profile Parent Name"}


def read_prefs():
    data = sys.stdin.buffer.read()
    return plistlib.loads(data) if data.strip() else {}


def jsonable(v):
    try:
        json.dumps(v)
        return True
    except TypeError:
        return False


def cmd_export(args):
    prefs = read_prefs()
    profiles = prefs.get("New Bookmarks", [])
    default = prefs.get("Default Bookmark Guid")
    prof = next((p for p in profiles if p.get("Guid") == default), None)
    if prof is None and profiles:
        prof = profiles[0]
    if prof is None:
        sys.exit("No iTerm2 profile found to export.")
    out = {k: v for k, v in prof.items() if k not in DROP and jsonable(v)}
    out["Name"] = "My Material (saved)"
    with open(args.out, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)


def cmd_apply(args):
    prefs = read_prefs()
    with open(args.base) as f:
        prof = json.load(f)

    if args.scheme:
        with open(args.scheme) as f:
            scheme = json.load(f)
        # .itermcolors keys ("Ansi 0 Color", "Background Color", ...) map 1:1
        # onto profile keys. Drop the old light/dark variants so the scheme
        # wins in both appearance modes.
        for k in [k for k in prof if k.endswith(("(Light)", "(Dark)"))]:
            del prof[k]
        prof.update(scheme)
        prof["Use Separate Colors for Light and Dark Mode"] = False
        prof["Name"] = args.name or "newmac"
    elif args.name:
        prof["Name"] = args.name

    if args.font:
        size = args.size or prof.get("Normal Font", "x 18").rsplit(" ", 1)[-1]
        prof["Normal Font"] = f"{args.font} {size}"
        prof["Non Ascii Font"] = f"{args.font} {size}"
    elif args.size:
        name = prof.get("Normal Font", "Menlo-Regular 18").rsplit(" ", 1)[0]
        prof["Normal Font"] = f"{name} {args.size}"

    if args.dir:
        prof["Custom Directory"] = "Yes"
        prof["Working Directory"] = args.dir

    prof["Guid"] = GUID
    others = [p for p in prefs.get("New Bookmarks", []) if p.get("Guid") != GUID]
    prefs["New Bookmarks"] = [prof] + others
    prefs["Default Bookmark Guid"] = GUID
    # Small quality-of-life prefs
    prefs.setdefault("PromptOnQuit", False)
    prefs.setdefault("SUEnableAutomaticChecks", True)
    sys.stdout.buffer.write(plistlib.dumps(prefs, fmt=plistlib.FMT_XML))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export"); e.add_argument("out")
    a = sub.add_parser("apply")
    a.add_argument("base")
    a.add_argument("--scheme")
    a.add_argument("--font")
    a.add_argument("--size")
    a.add_argument("--dir")
    a.add_argument("--name")
    args = p.parse_args()
    {"export": cmd_export, "apply": cmd_apply}[args.cmd](args)


if __name__ == "__main__":
    main()
