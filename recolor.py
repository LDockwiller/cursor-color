#!/usr/bin/env python3
"""Recolors a Bibata hyprcursor theme, installs it, and applies it live.

Based on recolor.py from SmoothPixels/cursor-accent (GPL-3.0-or-later).

The cursor color comes from one of three modes, read from config.json:
  "theme" (default): follow a color of the active Omarchy theme's
    colors.toml. `theme_key` picks which one ("accent" by default, but any
    key works: "blue", "magenta", "cursor", ...), so it changes on every
    theme switch.
  "fixed": always use config.json's `color`, whatever the theme is.
  "off": revert to the system's own default cursor (skips the whole build).

`style` decides where that color goes:
  "outline" (default): colored outline around a dark body (theme background).
  "filled": colored body with a dark outline.

`shape` is "modern" (rounded, default) or "original" (classic sharp-edged),
both pre-defined render targets in the vendored bibata_cursor's
config/render.json.

Usage: recolor.py [--force]

User state (config.json, the scratch build) lives in
~/.local/state/cursor-color, outside the plugin directory, so
`omarchy plugin update` never touches it.
"""
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent
STATE_DIR = Path.home() / ".local/state/cursor-color"
CONFIG_PATH = STATE_DIR / "config.json"
STAMP_PATH = STATE_DIR / "applied.json"
COLORS_PATH = Path.home() / ".local/state/omarchy/current/theme/colors.toml"
CURSOR_NAME = "Omarchy-CursorColor"
INSTALL_DIR = Path.home() / f".local/share/icons/{CURSOR_NAME}"
CURSOR_SIZE = os.environ.get("HYPRCURSOR_SIZE", "24")

SHAPE_TARGETS = {
    "modern": "Bibata-Modern-Classic",
    "original": "Bibata-Original-Classic",
}

DEFAULT_CONFIG = {
    "mode": "theme",
    "theme_key": "accent",
    "color": "#F25623",
    "shape": "modern",
    "style": "outline",
    "recent": [],
}

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def load_config():
    if CONFIG_PATH.exists():
        try:
            return {**DEFAULT_CONFIG, **json.loads(CONFIG_PATH.read_text())}
        except (json.JSONDecodeError, OSError):
            pass
    return dict(DEFAULT_CONFIG)


def load_theme_colors():
    try:
        with COLORS_PATH.open("rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return {}


def valid_hex(value, fallback):
    return value if isinstance(value, str) and HEX_RE.match(value) else fallback


def resolve_colors(config):
    """Returns (body, outline, watch, color) for the render target."""
    theme = load_theme_colors()
    dark = valid_hex(theme.get("dark_background") or theme.get("background"), "#171717")
    watch = valid_hex(theme.get("darker_background") or theme.get("background"), dark)

    if config.get("mode") == "fixed":
        color = valid_hex(config.get("color"), DEFAULT_CONFIG["color"])
    else:
        key = config.get("theme_key") or "accent"
        color = valid_hex(theme.get(key), None) or valid_hex(theme.get("accent"), "#F25623")

    if config.get("style") == "filled":
        return color, dark, watch, color
    return dark, color, watch, color


def setcursor(name):
    subprocess.run(["hyprctl", "setcursor", name, CURSOR_SIZE],
                   check=True, stdout=subprocess.DEVNULL)


def build(target, body, outline, watch):
    render_path = STATE_DIR / "render.json"
    shutil.copy(PLUGIN_DIR / "config/render.json", render_path)
    render = json.loads(render_path.read_text())
    render[target]["colors"][0]["replace"] = body
    render[target]["colors"][1]["replace"] = outline
    render[target]["colors"][2]["replace"] = watch
    render_path.write_text(json.dumps(render, indent=2))

    build_dir = STATE_DIR / "build"
    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir(parents=True)
    (build_dir / "src").symlink_to(PLUGIN_DIR / "src")
    (build_dir / "svg").symlink_to(PLUGIN_DIR / "svg")
    (build_dir / "config").mkdir()
    (build_dir / "config/render.json").symlink_to(render_path)
    (build_dir / "config/build.toml").symlink_to(PLUGIN_DIR / "config/build.toml")
    (build_dir / "config/build.right.toml").symlink_to(PLUGIN_DIR / "config/build.right.toml")

    # cursor_utils.py mixes cwd-relative source paths with --out-dir
    # (Path.relative_to), so --out-dir has to stay relative to build_dir.
    subprocess.run(
        [sys.executable, "./src/cursor_utils.py", "--hypr", "--theme", target,
         "--out-dir", "out", "--log-level", "error"],
        cwd=build_dir, check=True,
    )

    shutil.rmtree(INSTALL_DIR, ignore_errors=True)
    shutil.copytree(build_dir / "out" / target, INSTALL_DIR)
    (INSTALL_DIR / "index.theme").write_text(
        "[Icon Theme]\n"
        f"Name={CURSOR_NAME}\n"
        "Comment=Bibata cursor recolored by the cursor-color Omarchy plugin\n"
        "Inherits=Adwaita\n"
    )
    shutil.rmtree(build_dir, ignore_errors=True)


def main():
    force = "--force" in sys.argv[1:]
    config = load_config()
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    # The shell service, the picker and the CLI can all fire at once (theme
    # switch while the picker is open, login). They share the build and
    # install dirs, so serialize them.
    with (STATE_DIR / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        if config.get("mode") == "off":
            STAMP_PATH.unlink(missing_ok=True)
            setcursor("default")
            print("cursor-color: mode=off, curseur système par défaut")
            return

        shape = config.get("shape")
        if shape not in SHAPE_TARGETS:
            shape = "modern"
        target = SHAPE_TARGETS[shape]
        body, outline, watch, color = resolve_colors(config)

        # Theme switches that don't change the resolved colors (or a shell
        # restart) only need to re-select the already built theme.
        stamp = {"target": target, "body": body, "outline": outline, "watch": watch}
        try:
            unchanged = json.loads(STAMP_PATH.read_text()) == stamp
        except (OSError, json.JSONDecodeError):
            unchanged = False

        if force or not unchanged or not (INSTALL_DIR / "manifest.hl").exists():
            build(target, body, outline, watch)
            STAMP_PATH.write_text(json.dumps(stamp))

        setcursor(CURSOR_NAME)
        print(f"cursor-color: mode={config.get('mode')} shape={shape} "
              f"style={config.get('style')} color={color}")


if __name__ == "__main__":
    main()
