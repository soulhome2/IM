#!/usr/bin/env python3
"""Тесты переводчика контракта из OpenAPI 3.1 в 3.0 (tools/openapi30.py)."""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_workflow  # noqa: E402
import openapi30  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTRACT = os.path.join(ROOT, "Specification", "Workflow_machine", "openapi.json")


def wrap(schema):
    """Контракт из одной схемы — чтобы проверять перевод на малом примере."""
    return {"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, "paths": {},
            "components": {"schemas": {"S": schema}}}


def one(schema):
    return openapi30.convert(wrap(schema))["components"]["schemas"]["S"]


class Openapi30Test(unittest.TestCase):
    def test_type_array_to_nullable(self):
        self.assertEqual(one({"type": ["string", "null"]}), {"type": "string", "nullable": True})

    def test_anyof_null_ref(self):
        self.assertEqual(one({"anyOf": [{"$ref": "#/x"}, {"type": "null"}]}),
                         {"allOf": [{"$ref": "#/x"}], "nullable": True})

    def test_anyof_null_plain_variant(self):
        self.assertEqual(one({"anyOf": [{"type": "string"}, {"type": "null"}]}),
                         {"type": "string", "nullable": True})

    def test_anyof_null_several_variants(self):
        self.assertEqual(one({"oneOf": [{"type": "string"}, {"type": "integer"}, {"type": "null"}]}),
                         {"oneOf": [{"type": "string"}, {"type": "integer"}], "nullable": True})

    def test_examples_to_example(self):
        self.assertEqual(one({"type": "integer", "examples": [1, 2]}), {"type": "integer", "example": 1})

    def test_examples_of_media_type_kept(self):
        spec = wrap({"type": "string"})
        spec["paths"] = {"/p": {"get": {"responses": {"200": {"description": "ok", "content": {
            "application/json": {"schema": {"type": "string"}, "examples": {"a": {"value": "x"}}}}}}}}}
        out = openapi30.convert(spec)
        media = out["paths"]["/p"]["get"]["responses"]["200"]["content"]["application/json"]
        self.assertEqual(media["examples"], {"a": {"value": "x"}})

    def test_property_named_examples_kept(self):
        s = one({"type": "object", "properties": {"examples": {"type": "array", "items": {"type": "string"}}}})
        self.assertEqual(s["properties"]["examples"], {"type": "array", "items": {"type": "string"}})

    def test_if_then_const_dropped(self):
        s = one({"type": "object", "required": ["m"],
                 "properties": {"m": {"type": "string", "const": "a"}},
                 "if": {"properties": {"m": {"const": "a"}}}, "then": {"required": ["x"]}})
        self.assertEqual(s, {"type": "object", "required": ["m"], "properties": {"m": {"type": "string"}}})

    def test_ref_with_siblings(self):
        self.assertEqual(one({"$ref": "#/x", "description": "d"}),
                         {"allOf": [{"$ref": "#/x"}], "description": "d"})

    def test_source_not_changed(self):
        spec = wrap({"type": ["string", "null"]})
        before = json.dumps(spec)
        openapi30.convert(spec)
        self.assertEqual(json.dumps(spec), before)

    def test_info_summary_dropped(self):
        spec = wrap({"type": "string"})
        spec["info"]["summary"] = "кратко"
        out = openapi30.convert(spec)
        self.assertNotIn("summary", out["info"])
        self.assertEqual(openapi30.leftovers(spec), ["/info/summary"])
        self.assertEqual(openapi30.leftovers(out), [])

    def test_standalone_null_reported(self):
        spec = wrap({"type": "object", "properties": {"x": {"type": "null", "description": "d"}}})
        self.assertEqual(openapi30.leftovers(spec), ["/components/schemas/S/properties/x/type"])

    def test_build_fails_on_leftovers(self):
        """Сборка копии падает, если в ней остались конструкции 3.1 (переводчик чего-то не знает)"""
        with mock.patch.object(build_workflow.openapi30, "convert", lambda spec: spec):
            with self.assertRaises(SystemExit) as caught:
                build_workflow.build_openapi30()
        self.assertIn("openapi.v30.json", str(caught.exception))

    def test_whole_contract(self):
        with open(CONTRACT, encoding="utf-8") as f:
            original = json.load(f)
        out = openapi30.convert(original)
        self.assertEqual(out["openapi"], "3.0.3")
        self.assertEqual(openapi30.leftovers(out), [])
        self.assertNotEqual(openapi30.leftovers(original), [])
        self.assertEqual(len(out["paths"]), len(original["paths"]))
        self.assertEqual(len(out["components"]["schemas"]), len(original["components"]["schemas"]))


if __name__ == "__main__":
    unittest.main()
