"""Render README assets from output captured by the complete launcher tests.

Development-only dependencies: Pillow and ffmpeg. No image generation service
or device connection is involved. Every animation frame is labeled as a fixture.
"""
from pathlib import Path
import json
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "assets"
OUT.mkdir(parents=True, exist_ok=True)
lines = [line for line in (ROOT / "reports" / "workflow-demo.txt").read_text(encoding="utf-8-sig").splitlines() if line]
results = json.loads((ROOT / "reports" / "test-results.json").read_text(encoding="utf-8-sig"))
assert results["Passed"], "Generate promotional assets only from a passing run."
total = results["WindowsDiagnosticAssertions"] + sum(s["Passed"] for s in results["CSuites"])

hero = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 520" role="img" aria-labelledby="title desc">
<title id="title">iPhone Activation Toolkit</title><desc id="desc">One cable. One workflow. A Windows toolkit for device diagnostics and standard Apple server activation.</desc>
<defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#0f172a"/><stop offset="1" stop-color="#152d32"/></linearGradient><pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0H0V40" fill="none" stroke="#ffffff" stroke-opacity=".035"/></pattern></defs>
<rect width="1280" height="520" rx="24" fill="url(#bg)"/><rect width="1280" height="520" rx="24" fill="url(#grid)"/>
<rect x="54" y="47" width="38" height="38" rx="11" fill="#22c55e"/><path d="M66 57h14v10H66zM73 67v8m-4 0h8" fill="none" stroke="#0f172a" stroke-width="3" stroke-linecap="round"/>
<text x="108" y="73" fill="#f8fafc" font-family="Segoe UI,Arial,sans-serif" font-size="22" font-weight="600">iPhone Activation Toolkit</text>
<text x="54" y="187" fill="#f8fafc" font-family="Segoe UI,Arial,sans-serif" font-size="64" font-weight="700">One cable.</text>
<text x="54" y="264" fill="#86efac" font-family="Segoe UI,Arial,sans-serif" font-size="64" font-weight="700">One workflow.</text>
<text x="57" y="318" fill="#cbd5e1" font-family="Segoe UI,Arial,sans-serif" font-size="21">Connect. Inspect. Activate. Verify.</text>
<rect x="57" y="350" width="201" height="43" rx="9" fill="#22c55e"/><text x="78" y="378" fill="#0f172a" font-family="Consolas,monospace" font-size="18" font-weight="700">run-iphone.cmd</text>
<text x="58" y="460" fill="#cbd5e1" font-family="Segoe UI,Arial,sans-serif" font-size="16">Windows · PowerShell · Created by Aalok Bhandari</text>
<rect x="660" y="112" width="566" height="288" rx="15" fill="#0b1220" stroke="#475569"/>
<path d="M660 153h566" stroke="#334155"/><circle cx="683" cy="133" r="5" fill="#fb7185"/><circle cx="701" cy="133" r="5" fill="#fbbf24"/><circle cx="719" cy="133" r="5" fill="#4ade80"/>
<text x="742" y="138" fill="#94a3b8" font-family="Consolas,monospace" font-size="13">SOFTWARE FIXTURE PREVIEW</text>
<g font-family="Consolas,monospace" font-size="16"><text x="687" y="190" fill="#f8fafc">&gt; run-iphone.cmd</text><text x="687" y="228" fill="#cbd5e1">[1/5] Check tools and runtime</text><text x="687" y="258" fill="#cbd5e1">[2/5] Find the selected phone</text><text x="687" y="288" fill="#cbd5e1">[3/5] Read model, iOS and state</text><text x="687" y="318" fill="#cbd5e1">[4/5] Standard Apple activation</text><text x="687" y="348" fill="#86efac">[5/5] Verify final device state</text><text x="687" y="380" fill="#94a3b8">Same device. Observable results.</text></g>
</svg>'''
(OUT / "hero.svg").write_text(hero, encoding="utf-8")
(OUT / "tests.svg").write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="183" height="20" role="img" aria-label="Recorded assertions: {total} passed"><title>Recorded assertions: {total} passed</title><rect width="119" height="20" rx="3" fill="#334155"/><rect x="116" width="67" height="20" rx="3" fill="#15803d"/><g fill="white" text-anchor="middle" font-family="Verdana,Arial,sans-serif" font-size="11"><text x="58" y="14">recorded assertions</text><text x="150" y="14">{total} passed</text></g></svg>''', encoding="utf-8")

def font(name, size):
    path = Path("C:/Windows/Fonts") / name
    return ImageFont.truetype(str(path), size)

mono = font("consola.ttf", 23)
title_font = font("seguisb.ttf", 29)
small = font("segoeui.ttf", 19)

def frame(visible):
    im = Image.new("RGB", (1280, 720), "#0f172a")
    d = ImageDraw.Draw(im)
    d.text((42, 27), "iPhone Activation Toolkit", font=title_font, fill="#f8fafc")
    d.rounded_rectangle((42, 87, 1238, 638), radius=16, fill="#0b1220", outline="#475569", width=1)
    for x, color in [(65, "#fb7185"), (86, "#fbbf24"), (107, "#4ade80")]:
        d.ellipse((x, 108, x + 10, 118), fill=color)
    d.text((146, 100), "SOFTWARE FIXTURE DEMO / production launcher", font=small, fill="#94a3b8")
    d.line((43, 139, 1236, 139), fill="#334155")
    d.text((64, 164), "> .\\run-iphone.ps1 -ToolDirectory <fixture-tools>", font=mono, fill="#86efac")
    for i, line in enumerate(lines[:visible]):
        color = "#86efac" if line.startswith("Workflow complete") else "#e2e8f0"
        d.text((64, 213 + i * 47), line, font=mono, fill=color)
    d.text((44, 665), "Recorded test output. Simulated phone and activation service; no physical-device footage.", font=small, fill="#cbd5e1")
    return im

frames = [frame(i) for i in range(len(lines) + 1)]
durations = [850] + [650] * (len(frames) - 2) + [2300]
frames[-1].save(OUT / "workflow-demo.png", optimize=True)
paletted = [im.convert("P", palette=Image.Palette.ADAPTIVE, colors=128) for im in frames]
paletted[0].save(OUT / "workflow-demo.gif", save_all=True, append_images=paletted[1:], duration=durations, loop=0, optimize=True)
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(OUT / "workflow-demo.gif"),
                "-movflags", "+faststart", "-pix_fmt", "yuv420p", str(OUT / "workflow-demo.mp4")], check=True)
print(f"Generated README banner, {total}-assertion badge, static poster, GIF, and MP4.")
