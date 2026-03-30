#!/usr/bin/env python3
from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import shlex
import shutil
import subprocess
from collections import Counter, OrderedDict
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


APP_ID_MAPPING = {
    "code-url-handler": "code",
    "footclient": "foot",
}

DISPLAY_NAME_OVERRIDES = {
    "bitwarden": "Bitwarden",
    "foot": "Foot",
    "geeqie": "Geeqie",
    "kitty": "Kitty",
    "mousepad": "Mousepad",
    "obsidian": "Obsidian",
    "thunar": "Files",
    "thorium-browser": "Thorium",
}

HOME = Path.home()
WAYBAR_DIR = HOME / ".config" / "waybar"
FRAGMENT_PATH = WAYBAR_DIR / "grouped-taskbar.generated.jsonc"
CSS_PATH = WAYBAR_DIR / "grouped-taskbar.generated.css"
SCRIPT_PATH = WAYBAR_DIR / "scripts" / "grouped-taskbar.py"
TASKBAR_SIGNAL = ["pkill", "-SIGUSR2", "-x", "waybar"]
WOFI_BASE_CMD = [
    "wofi",
    "--dmenu",
    "--cache-file",
    "/dev/null",
    "--gtk-dark",
    "--insensitive",
]
DESKTOP_DIRS = [
    HOME / ".local" / "share" / "applications",
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
]
ICON_DIRS = [
    HOME / ".local" / "share" / "icons",
    Path("/usr/local/share/icons"),
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
WINDOW_LINE_RE = re.compile(r"^(.*?): (.*)$")


@dataclass(frozen=True)
class DesktopMeta:
    name: str
    icon_name: str


@dataclass(frozen=True)
class WindowEntry:
    app_id: str
    title: str


@dataclass(frozen=True)
class AppGroup:
    app_id: str
    slug: str
    label: str
    text: str
    icon_path: Path | None
    count: int
    active: bool


def normalize_app_id(app_id: str) -> str:
    value = app_id.strip()
    mapped = APP_ID_MAPPING.get(value, value)
    return mapped.strip() or "app"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "app"


def atomic_write(path: Path, content: str) -> bool:
    previous = path.read_text(encoding="utf-8") if path.exists() else None
    if previous == content:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    temp_path.write_text(content, encoding="utf-8")
    temp_path.replace(path)
    return True


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C.UTF-8", "TZ": "UTC"},
    )


def list_toplevels(*matches: str) -> list[WindowEntry]:
    command = ["wlrctl", "toplevel", "list", *matches]
    completed = run_command(command)
    if completed.returncode != 0:
        return []

    windows: list[WindowEntry] = []
    for raw_line in completed.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = WINDOW_LINE_RE.match(line)
        if not match:
            continue
        app_id = normalize_app_id(match.group(1))
        title = match.group(2)
        windows.append(WindowEntry(app_id=app_id, title=title))
    return windows


@lru_cache(maxsize=1)
def desktop_index() -> dict[str, DesktopMeta]:
    index: dict[str, DesktopMeta] = {}
    for directory in DESKTOP_DIRS:
        if not directory.is_dir():
            continue
        for desktop_path in sorted(directory.glob("*.desktop")):
            parser = configparser.RawConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            try:
                with desktop_path.open(encoding="utf-8") as handle:
                    parser.read_file(handle)
            except (OSError, configparser.Error):
                continue

            if not parser.has_section("Desktop Entry"):
                continue

            entry = parser["Desktop Entry"]
            if entry.get("Type", "Application").strip() != "Application":
                continue

            if entry.get("Hidden", "false").strip().lower() == "true":
                continue

            name = entry.get("Name", "").strip() or desktop_path.stem
            icon_name = entry.get("Icon", "").strip()
            metadata = DesktopMeta(name=name, icon_name=icon_name)
            keys = {
                desktop_path.stem.lower(),
                desktop_path.name.lower().removesuffix(".desktop"),
            }

            startup_wm_class = entry.get("StartupWMClass", "").strip().lower()
            if startup_wm_class:
                keys.add(startup_wm_class)

            for key in keys:
                index.setdefault(key, metadata)

    return index


def icon_sort_key(path: Path) -> tuple[int, int, str]:
    as_posix = path.as_posix()
    penalty = 1000
    if "/Papirus/" in as_posix:
        penalty -= 60
    if "/hicolor/" in as_posix:
        penalty -= 50
    if "/Adwaita/" in as_posix:
        penalty -= 40
    if "/scalable/" in as_posix:
        penalty -= 30
    if path.suffix == ".svg":
        penalty -= 20

    match = re.search(r"/(\d+)x(\d+)/", as_posix)
    if match:
        size = int(match.group(1))
        penalty += abs(size - 24)

    return penalty, len(as_posix), as_posix


@lru_cache(maxsize=256)
def resolve_icon_path(icon_name: str) -> Path | None:
    if not icon_name:
        return None

    explicit_path = Path(icon_name)
    if explicit_path.is_absolute() and explicit_path.is_file():
        return explicit_path

    pixmap_base = Path("/usr/share/pixmaps")
    for suffix in ("", ".svg", ".png", ".xpm"):
        candidate = pixmap_base / f"{icon_name}{suffix}"
        if candidate.is_file():
            return candidate

    candidates: list[Path] = []
    for base_dir in ICON_DIRS:
        if not base_dir.is_dir():
            continue
        for extension in ("svg", "png", "xpm"):
            candidates.extend(base_dir.rglob(f"{icon_name}.{extension}"))
        if explicit_path.suffix:
            candidates.extend(base_dir.rglob(icon_name))

    if not candidates:
        return None

    return min(candidates, key=icon_sort_key)


def app_metadata(app_id: str) -> tuple[str, Path | None]:
    lookup_key = app_id.lower()
    desktop = desktop_index().get(lookup_key)
    label = DISPLAY_NAME_OVERRIDES.get(app_id)
    icon_name = ""

    if desktop is not None:
        if label is None:
            label = desktop.name
        icon_name = desktop.icon_name

    if label is None:
        label = app_id.replace("-", " ").title()

    icon_path = resolve_icon_path(icon_name or app_id)
    return label, icon_path


def grouped_windows() -> list[AppGroup]:
    windows = list_toplevels()
    active_windows = {
        (window.app_id, window.title)
        for window in list_toplevels("state:active")
    }

    grouped: "OrderedDict[str, list[WindowEntry]]" = OrderedDict()
    for window in windows:
        grouped.setdefault(window.app_id, []).append(window)

    slugs_in_use: set[str] = set()
    groups: list[AppGroup] = []
    for app_id, app_windows in grouped.items():
        label, icon_path = app_metadata(app_id)
        base_slug = slugify(app_id)
        slug = base_slug
        suffix = 2
        while slug in slugs_in_use:
            slug = f"{base_slug}-{suffix}"
            suffix += 1
        slugs_in_use.add(slug)

        count = len(app_windows)
        if icon_path is not None:
            text = f"({count})" if count > 1 else " "
        else:
            text = label if count == 1 else f"{label} ({count})"

        active = any((window.app_id, window.title) in active_windows for window in app_windows)
        groups.append(
            AppGroup(
                app_id=app_id,
                slug=slug,
                label=label,
                text=text,
                icon_path=icon_path,
                count=count,
                active=active,
            )
        )

    return groups


def render_fragment(groups: list[AppGroup]) -> str:
    payload: OrderedDict[str, object] = OrderedDict()
    payload["modules-center"] = [f"custom/task-{group.slug}" for group in groups]

    for group in groups:
        payload[f"custom/task-{group.slug}"] = {
            "format": group.text,
            "tooltip": False,
            "exec-on-event": False,
            "on-click": f"{shlex.quote(str(SCRIPT_PATH))} menu --app-id {shlex.quote(group.app_id)}",
        }

    return json.dumps(payload, indent=2, ensure_ascii=False) + "\n"


def render_css(groups: list[AppGroup]) -> str:
    if not groups:
        return "/* No grouped taskbar modules are currently active. */\n"

    selectors = [f"#custom-task-{group.slug}" for group in groups]
    hover_selectors = [f"#custom-task-{group.slug}:hover" for group in groups]
    css_lines = [
        ",\n".join(selectors),
        "{",
        "  margin: 5px 4px;",
        "  padding: 0 12px;",
        "  min-height: 30px;",
        "  border-radius: 12px;",
        "  background: @panel_alt;",
        "  border: 1px solid @border;",
        "  color: @text;",
        "  font-weight: 600;",
        "}",
        "",
        ",\n".join(hover_selectors),
        "{",
        "  background: @panel_hover;",
        "  border-color: @border_strong;",
        "}",
        "",
    ]

    for group in groups:
        selector = f"#custom-task-{group.slug}"
        css_lines.extend(
            [
                f"{selector} {{",
                f"  min-width: {'18px' if group.icon_path is not None else '0'};",
                f"  padding-left: {'34px' if group.icon_path is not None else '12px'};",
                "}",
                "",
            ]
        )

        if group.icon_path is not None:
            css_lines.extend(
                [
                    f"{selector} {{",
                    f"  background-image: url(\"{group.icon_path.as_uri()}\");",
                    "  background-repeat: no-repeat;",
                    "  background-position: 10px center;",
                    "  background-size: 18px 18px;",
                    "}",
                    "",
                ]
            )

        if group.active:
            css_lines.extend(
                [
                    f"{selector} {{",
                    "  background-color: rgba(109, 196, 237, 0.18);",
                    "  border-color: rgba(109, 196, 237, 0.42);",
                    "  color: @sky;",
                    "}",
                    "",
                    f"{selector}:hover {{",
                    "  background-color: rgba(109, 196, 237, 0.24);",
                    "  border-color: rgba(109, 196, 237, 0.52);",
                    "}",
                    "",
                ]
            )

    return "\n".join(css_lines).strip() + "\n"


def render_files(*, reload_waybar: bool) -> bool:
    groups = grouped_windows()
    changed = False
    changed = atomic_write(FRAGMENT_PATH, render_fragment(groups)) or changed
    changed = atomic_write(CSS_PATH, render_css(groups)) or changed

    if changed and reload_waybar:
        subprocess.run(TASKBAR_SIGNAL, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    return changed


def choose(prompt: str, options: list[str]) -> str | None:
    if not options:
        return None

    command = [*WOFI_BASE_CMD, "--prompt", prompt]
    completed = subprocess.run(
        command,
        input="\n".join(options) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None

    selection = completed.stdout.strip()
    return selection or None


def focus_menu(app_id: str) -> int:
    app_id = normalize_app_id(app_id)
    windows = list_toplevels(f"app_id:{app_id}")
    if not windows:
        return 0

    active_windows = {
        (window.app_id, window.title)
        for window in list_toplevels("state:active")
    }
    label, _icon_path = app_metadata(app_id)
    title_counts = Counter(window.title for window in windows)
    title_seen: Counter[str] = Counter()
    menu_labels: list[str] = []
    selection_map: dict[str, str] = {}

    for window in windows:
        raw_title = window.title
        display_title = raw_title if raw_title else "(untitled)"
        if title_counts[raw_title] > 1:
            title_seen[raw_title] += 1
            display_title = f"{display_title} [{title_seen[raw_title]}/{title_counts[raw_title]}]"

        if (window.app_id, window.title) in active_windows:
            display_title = f"* {display_title}"

        menu_labels.append(display_title)
        selection_map[display_title] = raw_title

    selection = choose(label, menu_labels)
    if selection is None:
        return 0

    target_title = selection_map.get(selection)
    if target_title is None:
        return 0

    subprocess.run(
        ["wlrctl", "toplevel", "focus", f"app_id:{app_id}", f"title:{target_title}"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate and control the grouped Waybar taskbar")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("render", help="Render the current grouped taskbar fragment and CSS")
    subparsers.add_parser("refresh", help="Render grouped taskbar files and reload Waybar if they changed")

    menu_parser = subparsers.add_parser("menu", help="Show a Wofi window menu for one app group")
    menu_parser.add_argument("--app-id", required=True, help="Normalized app_id to focus from")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "render":
        render_files(reload_waybar=False)
        return 0

    if args.command == "refresh":
        render_files(reload_waybar=True)
        return 0

    if args.command == "menu":
        return focus_menu(args.app_id)

    parser.error(f"unsupported command: {args.command}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
