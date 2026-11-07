#!/usr/bin/env python3
"""Generate a catalog from published releases or publish it to the latest tag."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import TypedDict, cast
from urllib.parse import quote
from uuid import uuid4

from catalog import CatalogError, Index, merge_indexes, validate_index
from schema import Metadata, mapping, string, unix_timestamp, validate_metadata


class Asset(TypedDict):
    id: int
    name: str
    state: str
    size: int
    digest: str | None


class Release(TypedDict):
    id: int
    tag_name: str
    draft: bool
    prerelease: bool
    immutable: bool
    assets: list[Asset]


def gh(*args: str) -> str:
    return subprocess.check_output(['gh', *args], text=True, stderr=subprocess.PIPE)


def api_json(endpoint: str, *args: str) -> object:
    return json.loads(gh('api', endpoint, *args))


def api_pages(endpoint: str) -> list[object]:
    pages = api_json(endpoint, '--paginate', '--slurp')
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise CatalogError('Expected paginated GitHub arrays')
    return [item for page in pages for item in page]


def list_releases() -> list[Release]:
    return cast('list[Release]', api_pages('repos/{owner}/{repo}/releases?per_page=100'))


def named_asset(assets: list[Asset], name: str) -> Asset | None:
    matches = [asset for asset in assets if asset['name'] == name]
    if len(matches) > 1:
        raise CatalogError(f'Duplicate release asset: {name}')
    return matches[0] if matches else None


def verify_asset(asset: Asset, size: int, digest: str) -> None:
    if asset['state'] != 'uploaded' or asset['size'] != size:
        raise CatalogError(f'{asset["name"]}: incomplete upload or size mismatch')
    if asset.get('digest') and asset['digest'] != f'sha256:{digest}':
        raise CatalogError(f'{asset["name"]}: SHA-256 mismatch')


def parse_release_index(value: object, app_id: str, version: str) -> Index:
    data = validate_index(value)
    apps = data['apps']
    if len(apps) != 1 or len(apps[0]['versions']) != 1:
        raise CatalogError(f'{app_id}/{version}: expected exactly one app and one version')
    app = apps[0]
    record = app['versions'][0]
    if app['id'] != app_id or record['version'] != version:
        raise CatalogError(f'{app_id}/{version}: index identity does not match the release tag')
    return data


def load_metadata(path: Path) -> Metadata:
    from yaml_reader import load_yaml

    return validate_metadata(load_yaml(path), str(path))


def tag_commit_time(tag: str) -> int:
    data = mapping(api_json(f'repos/{{owner}}/{{repo}}/commits/{quote(tag, safe="")}'), tag)
    commit = mapping(data.get('commit'), f'{tag} commit')
    committer = mapping(commit.get('committer'), f'{tag} committer')
    date = datetime.fromisoformat(string(committer.get('date'), f'{tag} commit date').replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise CatalogError(f'{tag}: commit date must include a timezone')
    return unix_timestamp(int(date.timestamp()), f'{tag}.time')


def collect_index(releases: list[Release]) -> Index:
    fragments: list[Index] = []
    for release in releases:
        tag = release['tag_name']
        if tag == 'latest' or release['draft'] or release['prerelease']:
            continue
        match = re.fullmatch(r'([a-z][a-z0-9-]*)/((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))', tag)
        if not match:
            continue
        app_id, version = match.groups()
        metadata = named_asset(release['assets'], 'index.json')
        archive = named_asset(release['assets'], f'{app_id}.app.tar.bz2')
        if metadata is None or metadata['state'] != 'uploaded' or archive is None:
            raise CatalogError(f'{tag}: missing index.json or app archive')
        print(f'Reading {tag}', flush=True)
        fragment = parse_release_index(api_json(f'repos/{{owner}}/{{repo}}/releases/assets/{metadata["id"]}',
                                               '-H', 'Accept: application/octet-stream'), app_id, version)
        app = fragment['apps'][0]
        record = app['versions'][0]
        verify_asset(archive, record['size'], record['sha256'])
        record['time'] = tag_commit_time(tag)
        fragments.append(fragment)
    index = merge_indexes(fragments)
    for app in index['apps']:
        details = load_metadata(Path(__file__).resolve().parents[1] / 'apps' / app['id'] / 'meta.yaml')
        app['description'] = details['description']
        app['categories'] = details['categories']
    return index


def index_bytes(index: Index) -> bytes:
    return (json.dumps(index, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def generate_index(output: Path) -> Index:
    index = collect_index(list_releases())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(index_bytes(index))
    count = sum(len(app['versions']) for app in index['apps'])
    print(f'Merged {len(index["apps"])} apps and {count} versions into {output}')
    return index


def rename_asset(asset_id: int, name: str) -> None:
    gh('api', f'repos/{{owner}}/{{repo}}/releases/assets/{asset_id}', '--method', 'PATCH', '-f', f'name={name}')


def delete_asset(asset_id: int) -> None:
    gh('api', f'repos/{{owner}}/{{repo}}/releases/assets/{asset_id}', '--method', 'DELETE')


def publish_index(path: Path) -> None:
    payload = index_bytes(merge_indexes([validate_index(json.loads(path.read_bytes()), require_complete=True)]))
    latest = next((release for release in list_releases() if release['tag_name'] == 'latest'), None)
    if latest is not None and latest.get('immutable'):
        raise CatalogError('The latest Release must allow asset updates')
    with tempfile.TemporaryDirectory(prefix='simstore-catalog-') as temporary:
        directory = Path(temporary)
        if latest is None:
            asset_path = directory / 'index.json'
            asset_path.write_bytes(payload)
            gh('release', 'create', 'latest', str(asset_path), '--title', 'App catalog',
               '--notes', 'Merged application release index.', '--latest')
            return
        previous = named_asset(latest['assets'], 'index.json')
        digest = hashlib.sha256(payload).hexdigest()
        if previous and previous['state'] == 'uploaded' and previous.get('digest') == f'sha256:{digest}' and previous['size'] == len(payload):
            gh('release', 'edit', 'latest', '--draft=false', '--latest')
            return
        staging_name = f'index-{uuid4().hex}.json'
        staging = directory / staging_name
        staging.write_bytes(payload)
        gh('release', 'upload', 'latest', str(staging))
        assets = cast('list[Asset]', api_pages(f'repos/{{owner}}/{{repo}}/releases/{latest["id"]}/assets?per_page=100'))
        uploaded = named_asset(assets, staging_name)
        if uploaded is None:
            raise CatalogError('Uploaded catalog asset was not found; previous catalog was retained')
        verify_asset(uploaded, len(payload), digest)
        renamed_previous = False
        try:
            if previous:
                rename_asset(previous['id'], f'index-{previous["id"]}.previous.json')
                renamed_previous = True
            rename_asset(uploaded['id'], 'index.json')
        except (OSError, subprocess.CalledProcessError):
            if previous and renamed_previous:
                rename_asset(previous['id'], 'index.json')
            delete_asset(uploaded['id'])
            raise
        if previous:
            delete_asset(previous['id'])
        gh('release', 'edit', 'latest', '--draft=false', '--latest')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    generate = commands.add_parser('generate', help='Read published app releases without modifying GitHub')
    generate.add_argument('--output', type=Path, default=Path('build/catalog/index.json'))
    publish = commands.add_parser('publish', help='Create or update the latest Release catalog asset')
    publish.add_argument('index', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'generate':
            generate_index(args.output)
        else:
            publish_index(args.index)
            print('Published latest/index.json')
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        detail = (error.stderr or str(error)) if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f'Catalog FAILED: {detail}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
