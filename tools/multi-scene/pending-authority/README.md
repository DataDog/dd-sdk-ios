# Pending semantic authority acceptance

EXP-169 closes D07 with four failing authority-registry controls, 119 affected
tests, and this mounted comparison of explicit and optional-capability hosts.

```sh
python3 -B tools/multi-scene/pending-authority/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner reuses baseline package/extraction helpers and the restoration harness
contract. It copies seven explicit SDK source/resource directories, builds frozen
control/candidate apps, discovers an iOS 27 iPhone simulator and proves clean
installation, unique run IDs and matching installed executable hashes. Source,
fixture and binary hashes must remain unchanged. The main project/local xcconfig
are not read; dummy credentials and a loopback endpoint keep this local.

Both variants mount the actual RUMNavigationHost with automatic SwiftUI tracking
and a real authority registry. Before the first destination arrives, automatic
tracking must remain eligible and own its marker. A cancelled proposal changes
neither authority nor owner. The first accepted input must establish a fresh
semantic view synchronously: an action is submitted immediately after input,
without waiting for another render or lifecycle callback, and its mapper view/
session must match. Duplicate initial input cannot create another occurrence;
final host removal releases local suppression. The complete 29-check inventory
is mandatory. Both control variants must fail pending automatic eligibility;
the candidate must pass all29. Missing native mount/registry is inconclusive.

This covers input readiness, not disconnected-publication acceptance (D08),
multiple-observer reentrancy (R05), registry retirement (P03), physical lifecycle,
backend or minimum-runtime acceptance. The focused tests separately cover absent
handler and attachment, late prerequisite arrival, source pinning and unrelated
subtree eligibility. A fixture change requires new frozen builds and both arms.
