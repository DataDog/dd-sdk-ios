# Frozen multi-scene documentation through EXP-142

These files are byte-identical snapshots of the hot multi-scene documents at
signed baseline commit `5fc2099e9fbc18b02df35395de6298c781ed472e`.
They preserve every experiment narrative, run ID, RUM session ID, view UUID,
scenario, commit reference, failed attempt, warning, hardware queue entry, and
historical conclusion recorded through `EXP-142`.

Do not edit these snapshots. Correct or extend the hot documents and active
experiment shard instead. Links inside a frozen snapshot resolve as they did at
the original file location and may therefore be broken from `Archive/`; this is
intentional so the archive remains byte-identical. Use the current document map
for live links.

## Integrity manifest

| Snapshot | SHA-256 | Lines | Words | Bytes |
| --- | --- | ---: | ---: | ---: |
| `EXPERIMENTS_THROUGH_EXP-142.md` | `7d409086c5a8e98a7b7d097d381da2ba5595f5d49edbe802fd79e7bfeddaccef` | 5,064 | 53,954 | 430,231 |
| `PLAN_THROUGH_EXP-142.md` | `ce2594dba22d07e3a1f351070506ef3198944e22d47ccb90ef31b73ed2a26805` | 1,295 | 12,052 | 90,808 |
| `ASSESSMENT_THROUGH_EXP-142.md` | `a018e59710cec69c2cfda2bd39a45027b22af1132ad2462748be1684994ca4eb` | 1,170 | 14,640 | 106,591 |

The experiment snapshot contains exactly 142 unique, contiguous IDs from
`EXP-001` through `EXP-142` and exactly 142 consolidated-ledger rows. It has 45
Markdown headings and 107 bullets under `Attempts not to repeat`. Its
real-device/human queue has 12 rows covering 16 experiment IDs.

## Historical lookup

- Search the experiment snapshot by exact `EXP-NNN` for `EXP-030` and later.
- For `EXP-001` through `EXP-029`, use the exact run/session locator retained in
  the snapshot's consolidated ledger because those early chronological records
  use broad date headings rather than individual experiment headings.
- `EXP-137` through `EXP-140` share a historical heading; their ledger rows and
  run IDs are the deterministic locators.
- Do not infer experiment dates from enclosing headings. The authoritative date
  ranges are `EXP-001`-`012` on 2026-09-11, `EXP-013`-`040` on 2026-09-12,
  `EXP-041`-`119` on 2026-09-13, `EXP-120`-`134` on 2026-09-14, and
  `EXP-135`-`142` on 2026-09-15.

To recheck integrity from `DatadogRUM/MultiSceneSupport`:

```sh
shasum -a 256 Archive/*_THROUGH_EXP-142.md
```
