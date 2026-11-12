"""Prepare WordPress's real acknowledgement UI and retain package notice files."""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Pin:
    identity: str
    location: str
    revision: str
    version: str | None


@dataclass(frozen=True)
class Notice:
    name: str
    text: str
    content: bytes


def safe_identity(value: object) -> str:
    if not isinstance(value, str) or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', value) is None:
        raise ValueError(f'Unsafe or missing package identity: {value!r}')
    return value.casefold()


def read_pins(resolved: Path) -> list[Pin]:
    if resolved.is_symlink() or not resolved.is_file():
        raise ValueError(f'Expected a regular resolved file, not a symlink: {resolved}')
    document = json.loads(resolved.read_text(encoding='utf-8'))
    if not isinstance(document, dict) or not isinstance(document.get('pins'), list) or not document['pins']:
        raise ValueError('Resolved file must contain a nonempty pins array')
    pins: list[Pin] = []
    identities: set[str] = set()
    for raw in document['pins']:
        if not isinstance(raw, dict):
            raise ValueError('Each pin must be an object')  # noqa: TRY004 - Invalid JSON content, not a Python API type.
        identity = safe_identity(raw.get('identity'))
        if identity in identities:
            raise ValueError(f'duplicate package identity: {identity}')
        identities.add(identity)
        location = raw.get('location')
        if raw.get('kind') != 'remoteSourceControl' or not isinstance(location, str) or not location.strip():
            raise ValueError(f'Malformed remote source pin: {identity}')
        state = raw.get('state')
        if not isinstance(state, dict):
            raise ValueError(f'Missing pin state: {identity}')  # noqa: TRY004 - Invalid JSON content.
        revision = state.get('revision')
        if not isinstance(revision, str) or re.fullmatch(r'[a-fA-F0-9]{40}', revision) is None:
            raise ValueError(f'Missing or malformed revision: {identity}')
        version = state.get('version')
        if 'version' in state and (not isinstance(version, str) or not version.strip()):
            raise ValueError(f'Malformed version: {identity}')
        pins.append(Pin(identity, location, revision, version))
    return sorted(pins, key=lambda pin: pin.identity)


def regular_directory(path: Path) -> Path:
    if path.is_symlink() or not path.is_dir():
        raise ValueError(f'Expected a directory, not a symlink: {path}')
    return path.resolve(strict=True)


def checkout_directories(checkouts: Path) -> dict[str, list[Path]]:
    directories: dict[str, list[Path]] = {}
    for path in checkouts.iterdir():
        # Reject linked checkouts even when a link points back inside the root.
        if path.is_symlink():
            raise ValueError(f'Unsafe checkout symlink: {path}')
        if path.is_dir():
            directories.setdefault(path.name.casefold(), []).append(path)
    return directories


def collect_notices(checkout: Path, *, missing_license_notice: str | None = None) -> list[Notice]:
    notices: list[Notice] = []
    primary_count = 0
    for path in sorted(checkout.iterdir(), key=lambda item: (item.name.casefold(), item.name)):
        name = path.name.casefold()
        primary = name.startswith(('license', 'licence', 'copying'))
        if not primary and not name.startswith('notice'):
            continue
        if path.is_symlink():
            raise ValueError(f'Unsafe notice symlink: {path}')
        if not path.is_file():
            continue
        content = path.read_bytes()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError as error:
            raise ValueError(f'Notice must be UTF-8 plain text: {path}') from error
        if '\x00' in text:
            raise ValueError(f'Notice must be plain text: {path}')
        if primary:
            if not text.strip():
                raise ValueError(f'Empty primary license: {path}')
            primary_count += 1
        notices.append(Notice(path.name, text, content))
    if primary_count == 0:
        if missing_license_notice is None:
            raise ValueError(f'Missing nonempty primary license in checkout: {checkout.name}')
        # This disclosure records missing upstream metadata, never a license grant.
        text = missing_license_notice + '\n'
        notices.append(Notice('LICENSE-NOT-PROVIDED.txt', text, text.encode('utf-8')))
    return sorted(notices, key=lambda notice: (notice.name.casefold(), notice.name))


def validate_output(path: Path, *, directory: bool) -> None:
    if path.is_symlink():
        raise ValueError(f'Unsafe output symlink: {path}')
    if path.exists() and (path.is_dir() != directory or (not directory and not path.is_file())):
        raise ValueError(f'Unexpected output file type: {path}')


def prepare_notices(resolved: Path, checkouts: Path, app: Path, *,
                    allow_missing_license: list[str] | None = None) -> None:
    """Validate all input/output paths before writing deterministic acknowledgement data.

    Input roots must be real files/directories. Checkout and notice symlinks are
    rejected, and every output component is checked without following symlinks.
    Unrelated checkout source files are not copied or changed.
    """
    pins = read_pins(resolved)
    allowed: set[str] = set()
    identities = {pin.identity for pin in pins}
    for raw_identity in allow_missing_license or []:
        identity = safe_identity(raw_identity)
        if identity in allowed:
            raise ValueError(f'duplicate missing-license allowlist identity: {identity}')
        if identity not in identities:
            raise ValueError(f'Unknown missing-license allowlist identity: {identity}')
        allowed.add(identity)
    checkouts = regular_directory(checkouts)
    app = regular_directory(app)
    if app == checkouts or app.is_relative_to(checkouts) or checkouts.is_relative_to(app):
        raise ValueError('App output and checkout paths must not overlap')
    directories = checkout_directories(checkouts)
    notice_root = app / 'ThirdPartyNotices'
    package_list = app / 'package-list.json'
    validate_output(notice_root, directory=True)
    validate_output(package_list, directory=False)
    prepared: list[tuple[Pin, Path, list[Notice]]] = []
    for pin in pins:
        matches = directories.get(pin.identity, [])
        if len(matches) != 1:
            reason = 'missing' if not matches else 'ambiguous'
            raise ValueError(f'{reason} checkout for package: {pin.identity}')
        checkout = matches[0]
        if checkout.is_symlink() or not checkout.is_dir() or checkout.resolve().parent != checkouts:
            raise ValueError(f'Unsafe checkout path or symlink: {checkout}')
        disclosure = None
        if pin.identity in allowed:
            disclosure = ('No license notice is supplied in this pinned upstream checkout. '
                          'This is not a license grant. '
                          f'Source: {pin.location} at {pin.revision}.')
        notices = collect_notices(checkout, missing_license_notice=disclosure)
        destination = notice_root / pin.identity
        validate_output(destination, directory=True)
        for notice in notices:
            validate_output(destination / notice.name, directory=False)
        prepared.append((pin, checkout, notices))

    items: list[dict[str, str]] = []
    for pin, checkout, notices in prepared:
        # A single primary notice remains verbatim. Label combined files so that
        # supplemental NOTICE attribution appears in the existing legal UI too.
        license_text = notices[0].text if len(notices) == 1 else '\n\n'.join(
            f'--- {notice.name} ---\n{notice.text}' for notice in notices
        )
        item = {'identity': pin.identity, 'name': checkout.name,
                'license': license_text, 'revision': pin.revision}
        if pin.version is not None:
            item['version'] = pin.version
        items.append(item)
        destination = notice_root / pin.identity
        destination.mkdir(parents=True, exist_ok=True)
        for notice in notices:
            (destination / notice.name).write_bytes(notice.content)
    package_list.write_text(json.dumps(items, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resolved', type=Path, help='Recipe Package.resolved')
    parser.add_argument('checkouts', type=Path, help='Resolved Swift package checkouts directory')
    parser.add_argument('app', type=Path, help='Built app directory')
    parser.add_argument('--allow-missing-license', action='append', default=[], metavar='ID',
                        help='Explicitly disclose a pinned package missing its primary license notice; repeatable')
    arguments = parser.parse_args()
    try:
        prepare_notices(arguments.resolved, arguments.checkouts, arguments.app,
                        allow_missing_license=arguments.allow_missing_license)
    except (OSError, ValueError) as error:
        print(f'Cannot prepare WordPress notices: {error}', file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == '__main__':
    main()
