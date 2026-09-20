import json
from pathlib import Path
import unittest
from jsonschema import ValidationError
from contracts import validate
class SharedFixtures(unittest.TestCase):
    def test_shared_conformance(self):
        for fixture in json.loads((Path(__file__).resolve().parents[1]/'contracts/fixtures.json').read_text()):
            with self.subTest(name=fixture['name']):
                try:
                    validate(fixture['model'],fixture['value'])
                    valid=True
                except ValidationError: valid=False
                self.assertEqual(valid,fixture['valid'])
