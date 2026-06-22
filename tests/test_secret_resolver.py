"""Tests for ${env:VAR} secret resolution (framework/secret_resolver.py).

The properties that matter: a valid reference resolves from the runner's env, and
an unset/empty reference fails LOUDLY (never silently injects an empty
credential). The last test characterizes the known silent-passthrough gap so a
future hardening changes it on purpose.
"""

from __future__ import annotations

import pytest

from framework.secret_resolver import SecretResolutionError, resolve, resolve_dict


def test_resolves_valid_reference_from_env(monkeypatch):
    monkeypatch.setenv("MY_TOKEN", "abc123")
    assert resolve("${env:MY_TOKEN}") == "abc123"


def test_unset_env_var_raises_loudly(monkeypatch):
    monkeypatch.delenv("NOPE_TOKEN", raising=False)
    with pytest.raises(SecretResolutionError, match="NOPE_TOKEN"):
        resolve("${env:NOPE_TOKEN}")


def test_empty_env_value_raises_not_silently_empty(monkeypatch):
    # A var explicitly set to "" must be treated as unresolved, not as a
    # silently-empty secret that the fetcher would authenticate with.
    monkeypatch.setenv("EMPTY_TOKEN", "")
    with pytest.raises(SecretResolutionError):
        resolve("${env:EMPTY_TOKEN}")


def test_plain_string_passes_through_unchanged():
    assert resolve("a-literal-non-reference-value") == "a-literal-non-reference-value"


def test_surrounding_whitespace_is_tolerated(monkeypatch):
    monkeypatch.setenv("T", "v")
    assert resolve("  ${env:T}  ") == "v"


def test_non_string_value_passes_through():
    assert resolve(123) == 123


def test_resolve_dict_resolves_each_value(monkeypatch):
    monkeypatch.setenv("A", "1")
    monkeypatch.setenv("B", "2")
    assert resolve_dict({"a": "${env:A}", "b": "${env:B}"}) == {"a": "1", "b": "2"}


def test_characterizes_silent_passthrough_of_malformed_refs(monkeypatch):
    """CHARACTERIZATION (not an endorsement). A value that LOOKS like a reference
    but doesn't match the strict ^${env:UPPER_SNAKE}$ form is passed through
    verbatim — a lowercase var name, or an embedded reference. This is the known
    hardening gap from the audit; pinning it here means a future fix flips this
    deliberately instead of silently."""
    monkeypatch.setenv("my_token", "secret")
    assert resolve("${env:my_token}") == "${env:my_token}"   # lowercase: NOT resolved to "secret"
    assert resolve("prefix-${env:T}") == "prefix-${env:T}"    # embedded: NOT substituted
