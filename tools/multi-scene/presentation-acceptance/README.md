# Accepted presentation and occurrence acceptance

EXP-173 runs the real `RUMNavigationStack` presentation adapter in an iOS27
SwiftUI host. Its three scenarios reject a dismissal, canonicalize a proposed
item into a same-ID cover, and return through sheet→cover→sheet with the same
customer ID. It checks actual native dismissal callbacks, delayed old occurrence
callbacks, content rematerialization, exactly-once transaction forwarding and
Resource/Log view/session ownership before the next render.

```sh
python3 tools/multi-scene/presentation-acceptance/run.py \
  --control a0eed5c9259d6c3763bad1871210b08cf6b39aa6 \
  --candidate 7619eb8a20eb20edceef84d59706e1cf7b7b838a \
  --output /tmp/new-presentation-attempt.json
python3 -m unittest discover -s tools/multi-scene/presentation-acceptance -p 'test_*.py'
```

The runner discovers a simulator, archives explicit SDK paths into new isolated
projects, builds both arms, proves clean uninstall, freezes source/build identity,
checks the installed executable, and requires a fresh run ID and all77 checks.
It never accesses the workspace project or local configuration. Existing output
paths are rejected. Results retain raw mapper events and native lifecycle details.
The original control must fail all four selected ownership discriminators; a
candidate pass alone cannot establish a repair. An absent setup or a late
critical-boundary assertion is inconclusive. No real credentials are used.

`hooks.py` installs observation-only Debug hooks in both copied SDKs: it exposes
the existing production Binding and already-created boundary callbacks. It does
not implement routing or state transitions. Archive and compiled-source hashes
are distinct. Late callback injection is deterministic adapter acceptance, not
physical OS-ordering evidence. The peer is logical; the presentation host is a
real native scene. Native sheet and cover mounting and dismissal are required.

The first valid candidate failed because SwiftUI rematerialized still-accepted
content. The pre-injection occurrence-stability assertion preserves this
regression discriminator. All attempts, including the invalid hook build, remain
in the EXP-173 durable result. A subsequent pure oracle extraction was replayed
against those artifacts without rerunning accepted native execution.

Opaque custom setters cannot expose their interior accepted mutation implicitly.
The supported immediate boundaries are rejecting-setter work, accepted return,
and actual onDismiss; an earlier interior boundary needs an observed/explicit
transition source. Physical ordering, API sign-off and minimum-runtime acceptance
remain separate release gates.
