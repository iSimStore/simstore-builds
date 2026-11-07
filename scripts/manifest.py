#!/usr/bin/env python3
"""Read and validate an app recipe without evaluating YAML objects or aliases."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import TypedDict, cast

from schema import (
    SOURCE_FIELDS,
    ValidationError,
    app_id,
    mapping,
    os_version,
    release_version,
    string,
    validate_source,
)
from schema import Source as SourceMetadata
from yaml_reader import load_yaml

ManifestError = ValidationError


class Source(SourceMetadata):
    version: str


class Build(TypedDict):
    script: str
    deploymentTarget: str
    stripSymbols: bool


class Compatibility(TypedDict):
    minSimulatorOS: str


class RequiredManifest(TypedDict):
    id: str
    name: str
    source: Source
    build: Build


class Manifest(RequiredManifest, total=False):
    compatibility: Compatibility


def load_manifest(path: str | Path) -> Manifest:
    path = Path(path).absolute()
    data = mapping(load_yaml(path), 'manifest', ('id', 'name', 'source', 'build'), ('compatibility',))
    if app_id(data['id'], 'id') != path.parent.name:
        raise ManifestError('id must match the application directory')
    string(data['name'], 'name')

    source = mapping(data['source'], 'source', SOURCE_FIELDS + ('version',))
    validate_source(source)
    release_version(source['version'], 'source.version', allow_v=True)

    build = mapping(data['build'], 'build', ('script', 'deploymentTarget'), ('stripSymbols',))
    build.setdefault('stripSymbols', True)
    if not isinstance(build['stripSymbols'], bool):
        raise ManifestError('build.stripSymbols must be a boolean')
    script = string(build['script'], 'build.script')
    if Path(script).is_absolute() or any(part in ('.', '..') for part in script.split('/')):
        raise ManifestError('build.script must stay inside the application directory')
    directory = path.parent.resolve(strict=True)
    target = (directory / script).resolve(strict=True)
    if not target.is_relative_to(directory) or not target.is_file():
        raise ManifestError('build.script must be a file inside the application directory')
    deployment = os_version(build['deploymentTarget'], 'build.deploymentTarget')

    if 'compatibility' in data:
        compatibility = mapping(data['compatibility'], 'compatibility', ('minSimulatorOS',))
        minimum = os_version(compatibility['minSimulatorOS'], 'compatibility.minSimulatorOS')
        if minimum < deployment:
            raise ManifestError('minSimulatorOS must not be below build.deploymentTarget')
    return cast(Manifest, data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--field', help='Print one string or boolean field without shell evaluation')
    args = parser.parse_args()
    try:
        data = load_manifest(args.manifest)
        if args.field:
            value: object = data
            for key in args.field.split('.'):
                if not isinstance(value, dict) or key not in value:
                    raise ManifestError(f'Unknown field: {args.field}')
                value = value[key]
            if not isinstance(value, (str, bool)):
                raise ManifestError('--field requires a string or boolean scalar')
            print(json.dumps(value) if isinstance(value, bool) else value)
        else:
            print(json.dumps(data, indent=2))
    except (ManifestError, OSError) as e:
        print(f'Manifest FAILED: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
