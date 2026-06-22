"""Tests for the evidence-envelope WRITE path (framework/envelope.py).

The load-bearing property: every file wrap_outputs writes must conform to
framework/schemas/envelope_schema.json. We assert that with the SCHEMA itself as
the oracle (Draft202012Validator) — not a hand-copied key list — so a dropped or
renamed metadata field, or a status value outside the enum, fails the test
rather than passing because the test mirrors the same mistake.
"""

from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

from framework.contract import EvidenceSet, Fetcher, InvocationResult
from framework.envelope import is_enveloped, wrap_outputs

REPO_ROOT = Path(__file__).resolve().parent.parent
ENVELOPE_SCHEMA = json.loads((REPO_ROOT / "framework/schemas/envelope_schema.json").read_text())
_VALIDATOR = Draft202012Validator(ENVELOPE_SCHEMA)


def make_fetcher(path, **ov) -> Fetcher:
    d = dict(
        name="f", version="0.1.0", description="d", category="cat",
        runtime_type="python", runtime_entry="fetcher.py", runtime_timeout=None,
        output_type="json", output_path="out.json", output_aggregation=None,
        secrets=[], supports_targets=False, target_schema={}, path=path,
        config_schema={}, evidence_set=None,
    )
    d.update(ov)
    return Fetcher(**d)


def make_result(**ov) -> InvocationResult:
    d = dict(
        fetcher_name="f", fetcher_version="0.1.0", target=None,
        started_at="2026-01-01T00:00:00Z", completed_at="2026-01-01T00:00:01Z",
        duration_sec=1.0, exit_code=0, stdout="", stderr="", outputs=["ev.json"],
    )
    d.update(ov)
    return InvocationResult(**d)


def _wrap_one(tmp_path, raw, *, result=None, fetcher=None) -> dict:
    """Write `raw` as ev.json, wrap it, return the file's new content."""
    (tmp_path / "ev.json").write_text(json.dumps(raw))
    wrap_outputs(result or make_result(), fetcher or make_fetcher(tmp_path),
                 run_id="2026-01-01T00-00-00Z", run_dir=tmp_path)
    return json.loads((tmp_path / "ev.json").read_text())


def test_wrapped_output_conforms_to_envelope_schema(tmp_path):
    es = EvidenceSet(reference_id="EVD-1", name="Test Set", instructions="how", description="desc")
    fetcher = make_fetcher(tmp_path, evidence_set=es)
    env = _wrap_one(tmp_path, {"finding": "x"}, fetcher=fetcher,
                    result=make_result(target={"region": "us-east-1"}))

    errors = [e.message for e in _VALIDATOR.iter_errors(env)]   # oracle = the schema file
    assert not errors, errors
    assert env["payload"] == {"finding": "x"}                   # payload preserved verbatim
    assert env["metadata"]["evidence_set"]["reference_id"] == "EVD-1"
    assert env["metadata"]["target"] == {"region": "us-east-1"}


def test_failed_status_carries_bounded_error_tail(tmp_path):
    env = _wrap_one(tmp_path, {"k": 1},
                    result=make_result(exit_code=2, stderr="boom\ntraceback here"))
    assert env["metadata"]["status"] == "failed"
    assert env["metadata"]["error"].endswith("traceback here")
    assert not list(_VALIDATOR.iter_errors(env))   # still schema-valid


def test_error_tail_is_truncated(tmp_path):
    env = _wrap_one(tmp_path, {"k": 1}, result=make_result(exit_code=1, stderr="x" * 10_000))
    assert len(env["metadata"]["error"]) <= 4000


def test_success_has_no_error_field(tmp_path):
    env = _wrap_one(tmp_path, {"k": 1}, result=make_result(exit_code=0, stderr="non-fatal warning"))
    assert env["metadata"]["status"] == "success"
    assert "error" not in env["metadata"]   # error only attached on failure


def test_already_enveloped_file_is_not_double_wrapped(tmp_path):
    pre = {"schema_version": "1.0", "metadata": {"run_id": "r"}, "payload": {"already": True}}
    out = _wrap_one(tmp_path, pre)
    assert out == pre                          # untouched
    assert not is_enveloped(out["payload"])    # payload was not itself an envelope


def test_non_json_output_left_untouched(tmp_path):
    (tmp_path / "note.txt").write_text("not json")
    wrap_outputs(make_result(outputs=["note.txt"]), make_fetcher(tmp_path), "rid", tmp_path)
    assert (tmp_path / "note.txt").read_text() == "not json"


def test_unreadable_json_is_skipped_without_raising(tmp_path):
    (tmp_path / "ev.json").write_text("{ not valid json")
    # A single unreadable file must never abort the run.
    wrap_outputs(make_result(), make_fetcher(tmp_path), "rid", tmp_path)
    assert (tmp_path / "ev.json").read_text() == "{ not valid json"   # left as-is


def test_no_evidence_set_block_when_fetcher_declares_none(tmp_path):
    env = _wrap_one(tmp_path, {"k": 1})   # default fetcher has evidence_set=None
    assert "evidence_set" not in env["metadata"]
    assert not list(_VALIDATOR.iter_errors(env))   # still valid (evidence_set is optional)
