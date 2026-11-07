"""Read a single YAML document with string keys and no aliases or duplicate keys."""
from __future__ import annotations

from collections.abc import Hashable
from pathlib import Path
from typing import cast

import yaml
from schema import ValidationError


class DataLoader(yaml.SafeLoader):
    def compose_node(self, parent: yaml.Node | None, index: int | yaml.Node | None) -> yaml.Node | None:
        if self.check_event(yaml.AliasEvent):
            raise ValidationError('YAML aliases are not allowed')
        # PyYAML also passes mapping key nodes and None; its stubs only accept int.
        return super().compose_node(parent, index)  # type: ignore[arg-type]

    def construct_mapping(self, node: yaml.Node, deep: bool = False) -> dict[Hashable, object]:
        if not isinstance(node, yaml.MappingNode):
            raise ValidationError('YAML mappings must contain key/value pairs')
        result: dict[Hashable, object] = {}
        for key_node, value_node in node.value:
            if key_node.tag != 'tag:yaml.org,2002:str':
                raise ValidationError('YAML mapping keys must be strings')
            key = cast(str, self.construct_object(key_node, deep=deep))
            if key in result:
                raise ValidationError('Duplicate YAML mapping key')
            result[key] = self.construct_object(value_node, deep=deep)
        return result


def load_yaml(path: str | Path) -> object:
    try:
        documents = list(yaml.load_all(Path(path).read_text(), Loader=DataLoader))
    except yaml.YAMLError as error:
        raise ValidationError(str(error)) from error
    if len(documents) != 1:
        raise ValidationError('Expected exactly one YAML document')
    return documents[0]
