# Review / Luna MAX handoff — 2026-09-15

## 0. Baseline and authority

- Repository: `quietarc-lab/ios-web-shell` (canonical; keep private).
- Reviewed local HEAD and GitHub `main`: `cebb2b25334b94d8a547e7b48e7d971dd1f23ae0`. Both were checked twice during this review.
- Review emphasis: the latest multi-thread integration, its interaction with the existing page machine/bridge, cancellation, completion attribution, diagnostics and tests. This is not an exhaustive audit of all services.
- Application source was NOT changed. No posting, AP invocation, remote issue creation, commit, push, workflow dispatch or IPA replacement was performed during review.
- This file is a proposed work order, not evidence that the defects have been fixed and not authorization to start another task.
- Findings below distinguish code-established paths from timing-dependent device symptoms. No finding is claimed to have been reproduced on the reporting iPhone.
- Implementation scope for a future authorized task: reliable stopping, prevention of unintended/duplicate submissions, correct diagnostics, and isolated regression tests. Do not increase posting throughput, extend automated bulk distribution, or strengthen UA/IP restriction evasion. Do not test by posting to the public board. Use mocks/local fixtures.

## 1. Findings

### R1 — P1 — New-page readiness can be discarded after it has already arrived

Locations:

- `MiniBrowser/ViewModels/BrowserViewModel.swift:1359-1412`, especially `1382`, `1389-1395`.
- Same file: `824-830`, `816-821`, `1008-1034`.
- `MiniBrowser/Web/BrowserWebView.swift:127-188`, `370-373`.
- `MiniBrowser/Services/CompactPageModeService.swift:856-875`, `879-882`.

Code-established sequence:

1. The old target has reached `.succeeded`; navigation to the next target starts.
2. The new document's `.atDocumentEnd` script emits `compactReady`. The model is not active yet, so it only saves `latestCompactReady`.
3. Image restoration may also start before `didFinish`. `handwritingPreparationGenerationID` returns nil while the previous generation is inactive; a resulting ready notification is either ignored while inactive or rejected for its nil generation after the new generation starts.
4. `navigationFinished` starts the new page generation. `startMultiThreadGenerationAfterNavigation` sets `latestCompactReady = nil`, resets the machine, and creates fresh false compact/image preparation flags.
5. It marks only reload completion; it does not replay validated readiness or request a new preparation snapshot. Normal `compactReady` is sent at initialization and on input, not continuously.

Impact: if readiness arrives before `didFinish`, the new page can wait until the 30-second preparation timeout despite an already-rendered form/image. Delivery timing on a specific iPhone remains unverified; the dependency on event ordering exists in the code.

Apple documents `.atDocumentEnd` separately from subresource completion. Do not assume bridge readiness follows `didFinish`.

Required defensive acceptance:

- Local fixture tests must permute compact/image readiness before and after `didFinish`, and include an old page's late readiness.
- Never promote unowned/pre-navigation readiness to the active target merely because its token differs from the old token.
- A cancelled or mismatched navigation must settle as stopped, unlock controls, and issue zero clicks.
- Do not "fix" this by increasing the timeout, accepting nil generation IDs, or globally replaying the last ready event.

### R2 — P1 — The captured multi-thread comment is not applied or verified on the destination page

Locations:

- `BrowserViewModel.swift:389-425`, `581-590`, `1359-1412`.
- The only production call to `restoreAutomaticDraftScript` is in the same-thread path at `2855-2903`.
- `CompactPageModeService.swift:347-361` restores the ordinary localStorage draft only when the existing keep-draft toggle is enabled.
- `AutomaticPostFlow.swift` handles `markCompactReady` by checking comment presence, not equality with the session comment.

Code-established issue: assigning `automaticPostDraft` / `MultiThreadPostSession.comment` does not assign a textarea. No multi-thread call site applies the captured comment. With keep-draft OFF, destination pages may have no comment; with keep-draft ON, behavior depends on a separate persisted draft, not the promised immutable session snapshot.

Impact: comment-only preparation can stop as empty; image-containing preparation can accept an empty or different comment. A nonempty textarea is not proof that it contains the intended draft.

Required defensive acceptance:

- Fixture cases: keep-draft OFF + empty destination; keep-draft ON + different destination draft; comment-only; image with optional comment.
- Until intended content is explicitly verified, block submission rather than silently relying on localStorage.
- The safe work order does not add cross-thread draft distribution. Preserve the original manual keep-draft setting and stored value; do not turn it on or rewrite persistence policy as a workaround.
- Do not include the captured or observed comment in logs/assertion failure messages produced by production code.

### R3 — P1 — Session finish is not necessarily a terminal state-machine transition

Locations:

- `BrowserViewModel.swift:2430-2458` (`finishMultiThreadSession`).
- `3417-3481` (`finishAutomaticPost`).
- `1415-1466` (navigation failure/timeout direct finish callers).
- `2624-2651` (unstructured JS-completion Task guards).
- `3497-3504` (idle timer still depends on `automaticPostMachine.isActive`).

Code-established issue: `finishMultiThreadSession` clears session/UI state and calls `finishAutomaticPost`, but neither function moves an active machine into `.stopped` nor invalidates its generation. Existing callers sometimes first stop the machine, but the direct finish paths do not consistently do so. Cancelling a stored Task does not cancel a separately created `Task` inside a later JavaScript completion callback.

Impact: under direct termination from an active generation, the UI can say stopped while the machine remains preparing/submitting/waiting. Late callbacks that guard only generation/state can still be accepted. Idle-timer suppression may remain enabled. Which downstream effect occurs depends on the callback order; actual extra submission is not asserted as observed.

Required fix contract:

- One idempotent terminal operation must invalidate active automatic work before clearing its session owner.
- Retain final diagnostic IDs separately; do not reset IDs before capturing the final log context.
- Cancel owned timers/tasks and clear owned pending navigation/bootstrap/identity work without interfering with unrelated manual work.
- Make terminal completion exactly once. Avoid recursive `stop -> effect -> finish -> stop` loops.
- Late readiness, JS result/error, AP/cookie callback, navigation completion and completion markers after stop must not produce a click, new task, success rewrite or duplicated final log.
- Assert inactive machine, nil active session, unlocked controls and released automatic idle-timer hold after terminal stop.

### R4 — P2 — Bootstrap exits can strand the active-session UI, and OFF does not cancel unsent preparation

Locations:

- `BrowserViewModel.swift:322-334`, `389-425`, `354-375`.
- `556-573`: no WebView / no available UA early return.
- `2439-2449`: no matching generation returns before setting/clearing final status.
- `1300-1342`: first-target navigation completion.

Code-established issue:

- A session is made active before the initial generation is guaranteed to exist. The initial UA-unavailable path only clears `isUAChanging`, emits a toast and returns; it does not finish the multi-thread session.
- Finishing a bootstrap with no matching generation clears session flags but can leave `navigatingToNextThread` displayed indefinitely, because the final status/5-second cleanup is below the generation guard.
- OFF handles idle/succeeded/stopped immediately but not preparing/readiness/waiting-to-submit. An unsent target can still progress to its first click after OFF. That is broader than finishing a request already in flight.

Required fix contract:

- Bootstrap must own a cancellation identity even before a page generation exists.
- Every bootstrap exit must settle flags, pending work, status and idle timer; no stranded `multiThreadSessionActive`.
- OFF before dispatch prevents dispatch. OFF during an already dispatched request may await only that request's result; it cannot authorize another retry, target or identity change.
- Do not add new UA-selection or restriction-recovery behavior. Failure is a terminal outcome, not a reason to expand recovery.
- Add tests for no candidates, missing WebView, cancelled first navigation, OFF during initial read, OFF during navigation, OFF during readiness, OFF during in-flight result wait.

### R5 — P2 — Catalog CancellationError can leave the session indefinitely in refreshing state

Locations:

- `ThreadListViewModel.swift:126-130`, `147-148`.
- `BrowserViewModel.swift:2291-2300`, `2330-2335`.
- `ContentView.swift:39-43` updates scene activity; the model can become inactive independently of user OFF.

Code-established issue: the provider itself throws `CancellationError` when scene/network availability is false. The consumer treats every `CancellationError` as cancellation already owned by a disabled/newer session and does nothing. In the same still-active session, no success, stop or retry owner remains to settle the refresh state.

Required fix contract:

- Distinguish stale/cancelled-owner callbacks from a failure belonging to the current session.
- For the current session, unavailable provider / independently thrown cancellation must terminate cleanly with a bounded reason code; do not add automatic retry or background resume.
- For a stale owner, do nothing to the new session.
- Tests: current provider throws cancellation immediately; cancellation after suspension; OFF while fetch suspended; stale success/error delivered after a new owner is installed.
- Assert controls unlocked and no retained transition task for current-session failure.

### R6 — P1 — Submission identity is reused across generations; completion attribution is not end-to-end

Locations:

- `AutomaticPostFlow.swift:301`, `571`, `623-625`: IDs reset and restart from 1.
- `CompactPageModeService.swift:370-382`, `419-427`, `1090-1111`: status/completion reads a mutable current ID at notification time.
- `BrowserViewModel.swift:1079-1083`, `1170-1174`: nil submissionID skips the comparison.
- `BrowserViewModel.swift:3248-3262`: JS click callback checks generation/attempt/page but not the captured submission ID; response retry can reuse the same attempt number.

Code-established issue: same-page generations share a page token and reuse numeric submission IDs. A delayed notification from generation A with `(pageToken=P, submissionID=1)` is indistinguishable from generation B's `(P,1)` at the native handler. Missing submission ID is also permitted. Separately, mutable-global tagging at notification time can label an old marker with a new active ID, so merely changing the counter is insufficient.

Impact: stale completion can be attributed to the wrong request; a delayed JS error from the earlier click can terminate a later click at the same attempt. These are correctness hazards, not evidence that a duplicate post has been reproduced on-device.

Required defensive fix contract:

- Define a unique operation identity across the entire active WebView lifetime. Never reuse a successful operation identity for another request on the same document.
- Require a complete, validated ownership tuple for automatic result handling. Missing identity must not silently fall back to accepting an automatic result. Preserve normal manual display separately.
- Include captured operation identity in JS-completion guards, not only attempt number.
- Do not claim that MutationObserver events prove which request produced a marker. When source ownership cannot be established, record ambiguous completion and stop further automatic dispatch instead of guessing/retrying.
- Tests must inject A's completion while B is active on the same page, missing identity, stale click errors at equal attempt number, duplicate completion and current valid completion.
- Use local fake results only; do not validate by accelerating repeated public posts.

### R7 — P2 — DOM confirmation after acceptance is unreachable in multi-thread diagnostics

Locations:

- `BrowserViewModel.swift:1197-1212`: `.succeeded` requires `automaticPostVerificationTask != nil`.
- `1237-1247`: the intended multi-thread diagnostic-only branch is downstream of that guard.
- `2545-2549`, `3706-3707`: multi-thread cancels/never schedules the verification Task.

Code-established issue: for multi-thread acceptance followed by an own-response notification, the guard rejects it before the diagnostic-only branch. Confirmation arriving before acceptance can still be recorded. Therefore diagnostics depend on event order and can misleadingly remain unobserved even when a matching response appears before navigation.

Required fix contract:

- Diagnostic acceptance must be independent of the existence of a timer Task.
- Restrict diagnostic observation to the accepted operation and its document; stale observations must not attach to another target.
- Do not allow a diagnostic observation to start a target, retry, identity change or override a stopped session.
- Test both `accepted -> visible` and `visible -> accepted`, plus late observation after navigation/stop. Zero new clicks in all diagnostic-only cases.

## 2. Additional risks, not elevated to proven device defects

- `DebugLogStore.append` serializes up to 500 entries and writes UserDefaults on every event on the main actor. Resource overhead is plausible but unmeasured. Do not claim this caused a timing failure and do not redesign persistence in this batch. Benchmark with synthetic events if separately authorized.
- `automaticLogMetadata` reads the current mutable target index/ID even after `scheduleNextMultiThread` advances the session while the old generation is still receiving diagnostic events. Review whether old-generation logs become labelled with the next target; use immutable operation context for any touched logging paths.
- Navigation delegate callbacks do not carry an explicit navigation identity into the model. A separate review should exercise superseded navigation cancellation/failure, especially because `handleFailure` cancels the shared timeout before returning for `NSURLErrorCancelled`.
- A syntax checker or a substring test cannot establish event ordering, cancellation ownership, intended-content correctness or request/response causality.

## 3. Luna MAX execution instructions

Work only after a separate implementation instruction. Follow applicable AGENTS.md. Do not create parallel agents or a separate authoritative repository. Do not change models/tasks behind the user's back. If the local environment cannot change models, report that limitation when a high-risk step requires escalation.

### Work boundaries

1. Recheck `git status`, HEAD, remote `main`, applicable AGENTS.md. If HEAD differs from this review, revalidate each finding before editing. Preserve unrelated changes.
2. Treat R1/R2 as blockers against unattended dispatch. This work order authorizes their reproduction and fail-closed/content-consistency safeguards, not expanding the existing bulk-post/restriction-bypass behavior.
3. Do not modify UA pools, restriction classification/recovery, IP/AP retry selection, rate limits, target-count limits or posting delays. Do not relax readiness/identity checks to make tests pass.
4. Do not change cookies, localStorage, bookmarks, image storage, persistent user preferences, application identity or delivery destination.
5. Keep production content out of logs. Tests use explicit synthetic text/images, with no imported user logs or screenshots committed.

### Ordered, bounded patches

**Patch A: terminal ownership and OFF safety — R3/R4.**

- First write failing local coordinator/model tests for direct termination while active and OFF before a pending click.
- Add the smallest injectable boundaries needed: clock/scheduler, WebView side effects, pending operation identity. Prefer protocols or closures over making all private state public.
- Consolidate terminal cleanup with an exactly-once guard and test terminal invariants.
- Cover bootstrap failure without any machine generation, not only a normal generation stop.
- Do not proceed while a cancelled owner can still dispatch.

**Patch B: cancellation classification — R5.**

- Use a controllable fake catalog provider; suspend and resume success/error/cancellation explicitly.
- Settle current-owner cancellation and ignore old-owner callbacks. Keep refresh one-shot semantics and do not introduce background resumption.

**Patch C: result attribution — R6.**

- This couples Swift state, JavaScript and WebKit callback ownership; AGENTS.md requires higher-level review for this risk. Luna should first provide the failing fixture tests and a concise identity contract. Stop for that review if causality cannot be established with the current site marker; do not improvise another automatic retry.
- Any resulting patch must make ambiguity stop automatic work, not treat ambiguity as success or permission to click again.
- Do not widen this patch into a rewrite of the posting pipeline.

**Patch D: preparation/content safeguards and diagnostic attribution — R1/R2/R7.**

- Add a local page fixture that can emit readiness before/after document completion, contain a different synthetic draft, and delay an observation.
- Verify that incomplete ownership or content mismatch blocks dispatch and releases the session through the same terminal path.
- Diagnostic visibility should be recorded without driving any posting effect.
- Do not add live catalog traversal or automatic draft-distribution code as part of this defensive batch.

### Required test matrix

The outcome columns to assert are not just returned enums: dispatched-click count, navigation count, pending-task count, active generation/session, terminal-log count, fixed status, UI lock and idle-timer hold.

| Test | Required invariant |
| --- | --- |
| Stop during preparing/readiness/delay | No subsequent click; inactive machine; controls unlocked |
| Stop during in-flight request; late result | No new request; terminal output not replaced; final log once |
| OFF before initial capture/navigation/readiness completes | No new dispatch |
| Initial setup fails without a generation | Session cleared; no endless moving/preparing display |
| Current catalog provider independently cancels | Bounded terminal outcome; no refresh hang |
| Old provider result arrives after stop/new owner | No mutation of the current owner |
| Readiness precedes didFinish | No unowned readiness accepted; no accidental click |
| Wrong destination draft or absent draft | No unintended-content dispatch; persistence unchanged |
| Same document, distinct generations, equal legacy attempt | Stale result rejected by operation ownership |
| Automatic completion with missing identity | Not treated as confirmed current completion |
| Old JS callback at same attempt | Cannot stop or complete current operation |
| Accepted then DOM visible | Diagnostic recorded only for accepted operation |
| DOM visible then accepted | No duplicate final handling |
| Observation after stop/navigation | No subsequent dispatch or cross-target attribution |
| Manual post/dialog without automatic owner | Ordinary dialog/display semantics unchanged |

Use a fake monotonic clock; avoid tests with real 3/12/15/30-second sleeps. Pure state-machine tests alone are insufficient. Add model/coordinator integration tests and executable DOM fixture tests where a bridge change is made. If a required integration test cannot run on Windows, keep it as a required Simulator gate, not a claimed pass.

### Verification and delivery boundary

- Before any later push: `./scripts/Static-Check.ps1`, `node scripts/Validate-InjectedJavaScript.mjs .`, `git diff --check`, plus new locally runnable behavioral tests.
- Do not replace failing behavioral assertions with source-string checks or remove guards to satisfy tests.
- Report exact commands, exit codes, test counts and unexecuted checks. Do not say "all verified" based on syntax/static checks.
- This review request does not authorize commits, GitHub issue writes, Actions or delivery. A later implementation/delivery instruction must supply that authority.
- If later authorized: retain the manual-only coherent-batch workflow, Simulator XCTest gate, unsigned IPA validation and existing fixed delivery path. Do not dispatch intermediate macOS builds to discover Windows-detectable mistakes.
- Update README/IMPLEMENTATION_STATUS only with actually implemented/verified changes. Leave device-only criteria open; no automated public-board posting test.

### Stop / escalate criteria for Luna

- Same failure survives two attempts.
- A proposed change weakens operation ownership, alters retry behavior or needs uncertain WebKit event-order guarantees.
- Swift actor isolation/lifetime behavior remains uncertain.
- A fix requires coordinated redesign of three or more subsystems.
- Any test would need live repeated posting or restriction evasion to establish correctness.

At those points, preserve the small diff and failing test, report evidence and request review. Do not silently broaden the task, create an independent task, or burn repeated hosted builds.

## 4. Checks actually performed in this review

- Live local HEAD / GitHub main equality: verified.
- Working tree before this document: clean.
- `./scripts/Static-Check.ps1`: passed, including 100 distinct catalog UA strings and deployment target 26.0 checks.
- `node scripts/Validate-InjectedJavaScript.mjs .`: passed, 11 script cases.
- `git diff --check`: passed before the document; rerun after creation.
- Existing tests inspected: multi-thread session tests cover dedup/order/append, model test covers toggle defaults/exclusivity, machine tests cover selected pure transitions. The adverse integration sequences above are not covered by those tests.
- XCTest / iPhone runtime tests: NOT run during this review (Windows host).
- No remote workflow dispatched; no IPA built or delivered by this review.

## 5. Primary references checked

- [Apple — WKUserScriptInjectionTime.atDocumentEnd](https://developer.apple.com/documentation/webkit/wkuserscriptinjectiontime/atdocumentend): injection is not a guarantee that every resource/navigation callback has already completed. The conclusion about discarded readiness is derived from local call order, not a claim that every device uses the same callback order.
- [Apple — Task.cancel()](https://developer.apple.com/documentation/swift/task/cancel%28%29): cancellation is cooperative. Cancelling a stored Task is not a substitute for ownership checks on independently created callback work.

The official Markdown representations were read during review. The references explain API semantics; they do not establish on-device reproduction of these app-specific defects.
