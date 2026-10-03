#!/usr/bin/env python3
"""Configure publisher OAuth IDs and validate the actual Xcode build settings.

Only public client IDs are accepted. This does not register apps with providers
or claim that their server-side settings or account permissions are valid.
"""

import argparse
import os
from pathlib import Path
import re
import sys


PROVIDERS = (
    ("OneDrive", "ORGENDA_ONEDRIVE_CLIENT_ID", r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"),
    ("Google Drive", "ORGENDA_GOOGLE_CLIENT_ID", r"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com"),
    ("Dropbox", "ORGENDA_DROPBOX_CLIENT_ID", r"[A-Za-z0-9]+"),
)


def google_scheme(client_id):
    return ".".join(reversed(client_id.split(".")))


def validate_ids(values):
    errors = []
    for name, key, pattern in PROVIDERS:
        value = values.get(key, "")
        if not value:
            errors.append(f"{name}: missing {key}")
        elif not re.fullmatch(pattern, value):
            errors.append(f"{name}: invalid {key} format")
    return errors


def validate_build(values):
    errors = validate_ids(values)
    google_id = values.get("ORGENDA_GOOGLE_CLIENT_ID", "")
    if google_id:
        scheme = google_scheme(google_id)
        if values.get("ORGENDA_GOOGLE_URL_SCHEME") != scheme:
            errors.append("Google Drive: URL scheme must be the reversed iOS client ID")
        if values.get("ORGENDA_GOOGLE_REDIRECT_URI") != scheme + ":/oauth2redirect":
            errors.append("Google Drive: redirect URI must use the reversed iOS client ID and /oauth2redirect")
    for name, key, expected in (
        ("OneDrive", "ORGENDA_ONEDRIVE_REDIRECT_URI", "orgenda-onedrive://oauth"),
        ("Dropbox", "ORGENDA_DROPBOX_REDIRECT_URI", "orgenda-dropbox://oauth"),
    ):
        if values.get(key) != expected:
            errors.append(f"{name}: {key} must be {expected}")
    # Local development can still exercise Files, iCloud, WebDAV and test fixtures.
    # Any non-Debug build must contain all the sign-in options advertised by the app.
    required = values.get("CONFIGURATION") != "Debug"
    severity = "error" if required else "warning"
    for error in errors:
        print(f"{severity}: Cloud sign-in: {error}. Run python3 Scripts/cloud_oauth.py configure; see docs/CloudStorage.md.")
    return 1 if required and errors else 0


def configure(args):
    path = args.output
    values = {}
    if path.exists():
        # Preserve already configured providers when updating just one client ID.
        for line in path.read_text().splitlines():
            key, separator, value = line.partition("=")
            if separator and key.strip() in {p[1] for p in PROVIDERS}:
                values[key.strip()] = value.strip()
    supplied = [args.onedrive, args.google, args.dropbox]
    for (name, key, _), value in zip(PROVIDERS, supplied):
        if value is not None:
            values[key] = value.strip()
        elif all(value is None for value in supplied):
            current = " [Enter to keep current value]" if values.get(key) else " [Enter to skip for now]"
            value = input(f"{name} public client ID / app key{current}: ").strip()
            if value:
                values[key] = value
    # Missing IDs are allowed during setup; malformed values are never written.
    invalid = [error for error in validate_ids(values) if ": missing " not in error]
    if invalid:
        raise ValueError("; ".join(invalid))
    lines = ["// Generated public OAuth application IDs. Never put client secrets here."]
    for _, key, _ in PROVIDERS:
        lines.append(f"{key} = {values.get(key, '')}")
    google_id = values.get("ORGENDA_GOOGLE_CLIENT_ID", "")
    if google_id:
        lines.append("ORGENDA_GOOGLE_URL_SCHEME = " + google_scheme(google_id))
    path.parent.mkdir(parents=True, exist_ok=True)
    # Replace atomically, so an interrupted setup cannot truncate working settings.
    temporary = path.with_suffix(".tmp")
    temporary.write_text("\n".join(lines) + "\n")
    temporary.replace(path)
    print(f"Saved {path}. Xcode reads it on the next build; regenerating the project preserves it.")
    for error in validate_ids(values):
        print(f"Still needed: {error}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("configure", help="Save public app IDs; omit options for interactive setup")
    setup.add_argument("--onedrive", help="Microsoft Application (client) ID")
    setup.add_argument("--google", help="Google iOS OAuth client ID, not a web client or API key")
    setup.add_argument("--dropbox", help="Dropbox App key, not App secret")
    setup.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "Configurations/CloudOAuth.local.xcconfig")
    commands.add_parser("validate-build", help="Validate expanded Xcode settings from the environment")
    args = parser.parse_args()
    try:
        return configure(args) if args.command == "configure" else validate_build(os.environ)
    except (ValueError, OSError, EOFError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
