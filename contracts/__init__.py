"""Shared contract validation. Swift must consume the JSON schemas and fixtures."""
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
ROOT = Path(__file__).parent
SCHEMA = json.loads((ROOT / 'v1.schema.json').read_text())
ACTIONS = json.loads((ROOT / 'actions.json').read_text())
def validate(model, value):
    if model not in SCHEMA['$defs']:
        raise ValueError('Unknown contract model')
    Draft202012Validator({**SCHEMA, '$ref':f'#/$defs/{model}'}, format_checker=FormatChecker()).validate(value)
    return value
