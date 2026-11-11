#!/usr/bin/env python3
"""Select independent recipe jobs from changed paths or an explicit project id."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def select_projects(root: Path, paths: list[str], project_id: str = '', directory: str = 'apps') -> list[str]:
    available = {path.parent.name for path in (root / directory).glob('*/manifest.yaml')}
    if project_id:
        if project_id not in available:
            raise ValueError(f'Unknown project: {project_id}')
        return [project_id]
    # Also exclude the removed filename so the metadata migration does not rebuild apps.
    return sorted({parts[1] for path in paths if len(parts := path.split('/')) >= 3
                   and parts[0] == directory and parts[1] in available
                   and parts[2:] not in (['meta.yaml'], ['description.yaml'])})


def changed_paths(root: Path, base: str, head: str, event: str, directory: str = 'apps') -> list[str]:
    if not base or set(base) == {'0'}:
        command = ['git', '-C', str(root), 'ls-tree', '-r', '--name-only', '-z', head, '--', directory + '/']
    else:
        comparison = f'{base}...{head}' if event == 'pull_request' else f'{base}..{head}'
        command = ['git', '-C', str(root), 'diff', '--name-only', '--no-renames', '-z', comparison, '--', directory + '/']
    output = subprocess.check_output(command)
    return [path.decode() for path in output.split(b'\0') if path]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--id', default='')
    parser.add_argument('--base', default='')
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--event', required=True)
    parser.add_argument('--directory', choices=('apps', 'components'), default='apps')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        paths = [] if args.id else changed_paths(root, args.base, args.head, args.event, args.directory)
        projects = select_projects(root, paths, args.id, args.directory)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Project selection FAILED: {error}', file=sys.stderr)
        return 1
    print('projects=' + json.dumps(projects, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
