"""Add the real presentation sample to the earlier reviewer fixture, without changing its cases."""
from pathlib import Path
import sys

source = Path(__file__).with_name("render-sequential.swift").read_text()
lines = []
count = 0
for line in source.splitlines():
    lines.append(line)
    if line.lstrip().startswith("model.lyricPosition = "):
        indent = line[: len(line) - len(line.lstrip())]
        lines.append(indent + "model.lyricSample = model.lyricPosition.map { DesktopLyricSample(position: $0, sampledAt: $0, rate: 1) }")
        count += 1
assert count == 3, "Review fixture changed; inspect the three synthetic position writes."
Path(sys.argv[1]).write_text("// Synthetic sample time advances with position at rate 1; discontinuous positions remain jumps.\n" + "\n".join(lines) + "\n")
