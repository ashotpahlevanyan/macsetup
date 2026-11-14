#!/usr/bin/env python3
"""Turn `defaults read com.apple.HIToolbox AppleEnabledInputSources` output
into "Name|ID" lines, the format of macos/input-sources.txt."""
import re
import sys

text = sys.stdin.read()

for entry in re.findall(r"\{(.*?)\}", text, re.S):
    name = re.search(r'"KeyboardLayout Name" = "?([^";]+)"?;', entry)
    layout_id = re.search(r'"KeyboardLayout ID" = "?(-?\d+)"?;', entry)
    if name and layout_id:
        print(f"{name.group(1)}|{layout_id.group(1)}")
