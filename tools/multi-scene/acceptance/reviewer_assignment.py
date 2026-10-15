"""Bind replacement reviewers to a plan without rewriting historical reviews."""
import hashlib
import json
from pathlib import Path

from acceptance_common import require

ROLE = 'rum-runtime-reviewer'
LEGACY_REVIEWER = '/root/c06_runtime_plan'


def require_reviewer(review, plan_sha256, runtime):
    """Legacy receipts retain their identity; new identities need a frozen assignment.

    This is a provenance check, not authentication or a substitute for review.
    Callers still validate the verdict, exact plan, controls and helper closure.
    """
    reference = review.get('reviewer_assignment')
    if reference is None:
        require(review.get('reviewer') == LEGACY_REVIEWER and 'reviewer_role' not in review,
                'replacement reviewer requires a bound assignment')
        return
    require(isinstance(reference, dict) and set(reference) == {'path', 'sha256'},
            'malformed reviewer assignment reference')
    require(reference['path'] == 'reviewer-assignment.json', 'assignment must be local to this runtime')
    runtime = Path(runtime).resolve()
    path = runtime / reference['path']
    require(path.is_file() and not path.is_symlink(), 'reviewer assignment missing or redirected')
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == reference['sha256'], 'reviewer assignment changed')
    assignment = json.loads(raw)
    require(type(assignment.get('schema_version')) is int and assignment['schema_version'] == 1 and assignment.get('role') == ROLE
            and review.get('reviewer_role') == ROLE, 'unknown reviewer role')
    require(assignment.get('plan_sha256') == plan_sha256, 'reviewer assignment is for another plan')
    for key in ('reviewer', 'implementer', 'coordinator', 'assigned_at', 'reason'):
        require(isinstance(assignment.get(key), str) and assignment[key].strip(), 'assignment missing ' + key)
    require(assignment['reviewer'] == review.get('reviewer')
            and assignment['reviewer'] != assignment['implementer'], 'reviewer identity or independence mismatch')
    require(assignment.get('previous_reviewer_available') is False
            and isinstance(assignment.get('availability_evidence'), str)
            and assignment['availability_evidence'].strip(), 'replacement lacks an availability observation')
    require(assignment.get('scope') == 'REVIEW_ONLY_NO_NATIVE_OWNERSHIP', 'review assignment grants unrelated authority')
