"""Catalog types, validation, and deterministic merging of release fragments."""
from __future__ import annotations

import re
from typing import TypedDict

from schema import (
    METADATA_FIELDS,
    Metadata,
    ValidationError,
    app_id,
    git_revision,
    mapping,
    nonempty_string,
    os_version,
    release_version,
    repository,
    string,
    unix_timestamp,
    validate_metadata,
    version_key,
)

CatalogError = ValidationError


class VersionMetadata(TypedDict, total=False):
    time: int


class AppVersion(VersionMetadata):
    version: str
    minSimulatorOS: str
    sha256: str
    size: int
    revision: str
    recipeRevision: str


class AppMetadata(TypedDict, total=False):
    description: dict[str, str]
    categories: list[str]


class App(AppMetadata):
    id: str
    name: str
    bundleID: str
    repository: str
    license: str
    versions: list[AppVersion]


class Index(TypedDict):
    schemaVersion: int
    apps: list[App]


def validate_index(value: object, *, require_complete: bool = False) -> Index:
    data = mapping(value, 'index', ('schemaVersion', 'apps'))
    if type(data.get('schemaVersion')) is not int or data['schemaVersion'] != 1:
        raise CatalogError('Expected schemaVersion 1')
    raw_apps = data.get('apps')
    if not isinstance(raw_apps, list):
        raise CatalogError('index.apps must be an array')
    apps: list[App] = []
    for raw_app in raw_apps:
        app = mapping(raw_app, 'app', ('id', 'name', 'bundleID', 'repository', 'license', 'versions'),
                      METADATA_FIELDS)
        identifier = app_id(app.get('id'), 'app.id')
        name = string(app.get('name'), f'{identifier}.name')
        source_repository = repository(app.get('repository'), f'{identifier}.repository')
        license_name = nonempty_string(app.get('license'), f'{identifier}.license')
        bundle = string(app.get('bundleID'), f'{identifier}.bundleID')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
            raise CatalogError(f'{identifier}: invalid Bundle ID')
        raw_versions = app.get('versions')
        if not isinstance(raw_versions, list) or not raw_versions:
            raise CatalogError(f'{identifier}.versions must be a nonempty array')
        versions: list[AppVersion] = []
        for raw_version in raw_versions:
            record = mapping(raw_version, f'{identifier} version',
                             ('version', 'minSimulatorOS', 'sha256', 'size', 'revision', 'recipeRevision'), ('time',))
            version = release_version(record.get('version'), 'version')
            minimum = string(record.get('minSimulatorOS'), 'minSimulatorOS')
            os_version(minimum, 'minSimulatorOS')
            digest = string(record.get('sha256'), 'sha256')
            if not re.fullmatch(r'[0-9a-f]{64}', digest):
                raise CatalogError('Expected a SHA-256 digest')
            size = record.get('size')
            if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
                raise CatalogError('Archive size must be a positive integer')
            revision = git_revision(record.get('revision'), 'revision')
            recipe = git_revision(record.get('recipeRevision'), 'recipeRevision')
            versions.append({'version': version, 'minSimulatorOS': minimum, 'sha256': digest,
                             'size': size, 'revision': revision,
                             'recipeRevision': recipe})
            if 'time' in record:
                versions[-1]['time'] = unix_timestamp(record['time'], f'{identifier}/{version}.time')
        normalized: App = {'id': identifier, 'name': name, 'bundleID': bundle,
                           'repository': source_repository, 'license': license_name, 'versions': versions}
        if require_complete or any(field in app for field in METADATA_FIELDS):
            details = validate_metadata({field: app[field] for field in METADATA_FIELDS if field in app}, identifier)
            normalized['description'] = details['description']
            normalized['categories'] = details['categories']
        if require_complete and any('time' not in record for record in versions):
            raise CatalogError(f'{identifier}: every version.time is required')
        apps.append(normalized)
    return {'schemaVersion': 1, 'apps': apps}


def merge_indexes(indexes: list[Index]) -> Index:
    entries: dict[str, dict[str, AppVersion]] = {}
    metadata: dict[str, tuple[tuple[int, int, int], set[tuple[str, str, str]]]] = {}
    bundles: dict[str, str] = {}
    app_metadata: dict[str, Metadata] = {}
    for index in indexes:
        for app in index['apps']:
            app_id = app['id']
            if app_id in bundles and bundles[app_id] != app['bundleID']:
                raise CatalogError(f'{app_id}: conflicting Bundle IDs')
            bundles[app_id] = app['bundleID']
            if 'description' in app:
                details_metadata: Metadata = {'description': app['description'], 'categories': app['categories']}
                if app_id in app_metadata and app_metadata[app_id] != details_metadata:
                    raise CatalogError(f'{app_id}: conflicting app metadata')
                app_metadata[app_id] = details_metadata
            newest = max(version_key(record['version']) for record in app['versions'])
            details = (app['name'], app['repository'], app['license'])
            previous_metadata = metadata.get(app_id)
            if previous_metadata is None or newest > previous_metadata[0]:
                metadata[app_id] = (newest, {details})
            elif newest == previous_metadata[0]:
                previous_metadata[1].add(details)
            versions = entries.setdefault(app_id, {})
            for record in app['versions']:
                previous = versions.get(record['version'])
                if previous is not None and previous != record:
                    raise CatalogError(f'{app_id}/{record["version"]}: conflicting version records')
                versions[record['version']] = record
    apps: list[App] = []
    for app_id, records in sorted(entries.items()):
        ordered = sorted(records, key=version_key, reverse=True)
        candidates = metadata[app_id][1]
        if len(candidates) != 1:
            raise CatalogError(f'{app_id}: conflicting metadata for the newest version')
        name, source_repository, license_name = next(iter(candidates))
        merged_app: App = {'id': app_id, 'name': name, 'bundleID': bundles[app_id],
                           'repository': source_repository, 'license': license_name,
                           'versions': [records[release] for release in ordered]}
        if app_id in app_metadata:
            merged_app['description'] = app_metadata[app_id]['description']
            merged_app['categories'] = app_metadata[app_id]['categories']
        apps.append(merged_app)
    return {'schemaVersion': 1, 'apps': apps}
