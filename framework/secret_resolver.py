"""Resolve ${env:VAR_NAME} references from manifest values.

v0.x supports a single reference form: ${env:VAR_NAME} — read VAR_NAME from the
runner's own environment. The shape leaves room for future backends like
${aws-secret:...}, ${vault:...}, but v0.x doesn't implement them.

Customers populate the runner's env via any mechanism (.env, shell export,
secret manager → env, K8s secret env mounts, CI provider secret blocks, etc.).
The framework is secret-source-agnostic; .env is one path among many.
"""

import os
import re
from typing import Dict

_ENV_REF_PATTERN = re.compile(r"^\$\{env:([A-Z_][A-Z0-9_]*)\}$")


class SecretResolutionError(RuntimeError):
    pass


def resolve(value: str) -> str:
    """Resolve a ${env:VAR_NAME} reference. Plain strings pass through unchanged.

    Raises SecretResolutionError if the referenced env var is unset or empty.
    """
    if not isinstance(value, str):
        return value
    m = _ENV_REF_PATTERN.match(value.strip())
    if not m:
        return value
    env_var = m.group(1)
    resolved = os.environ.get(env_var, "")
    if not resolved:
        raise SecretResolutionError(
            f"Secret reference ${{env:{env_var}}} could not be resolved: "
            f"env var '{env_var}' is unset or empty in the runner's environment"
        )
    return resolved


def resolve_dict(d: Dict[str, str]) -> Dict[str, str]:
    return {k: resolve(v) for k, v in d.items()}
