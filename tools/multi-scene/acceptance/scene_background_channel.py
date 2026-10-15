"""Relocate the reviewed arm/stop transport into an isolated H10 namespace."""
from pathlib import Path
import hashlib

from acceptance_common import require

HERE = Path(__file__).resolve().parent
BASE = HERE / 'focus_activation_channel.swift'
BASE_SHA256 = '017fbd541e1f4fae8f5bb9cf5b67db30ba9940d6e5e57092dcdbcce474b6dcba'
RENAMES = {
    'ProbeFocusControl': 'ProbeSceneBackgroundControl',
    'windows.focus-activation-only': 'windows.isolated-background-foreground',
    'physical-focus-activation-only': 'physical-isolated-background-foreground',
    'focus channel is not armed': 'background channel is not armed',
    'focus command or evidence publication failed': 'background command or evidence publication failed',
}


def source():
    raw = BASE.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == BASE_SHA256, 'unreviewed base arm/stop transport')
    result = raw.decode()
    for old, new in RENAMES.items():
        require(old in result, 'missing H10 namespace relocation anchor')
        result = result.replace(old, new)
    # Same-file extension reuses the exact guarded I/O and stop implementation.
    return result + '''
extension ProbeSceneBackgroundControl {
    func readPhaseFile(_ name: String, limit: Int = maximumBytes) throws -> Data? {
        try read(name, limit: limit)
    }
    func writePhaseFile(_ bytes: Data, name: String) throws { try write(bytes, name: name) }
    func stopForPhaseFailure(_ reason: String) { stopDriver(reason) }
}
'''
