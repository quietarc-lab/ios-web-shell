# MiniBrowser

MiniBrowser is a lightweight iPhone browser built with SwiftUI and `WKWebView`. It targets iOS 26 and is designed to be built unsigned on GitHub Actions, then re-signed and installed with SideStore.

## Canonical repository

[quietarc-lab/ios-web-shell](https://github.com/quietarc-lab/ios-web-shell) is the single source of truth for MiniBrowser. Application code, XcodeGen configuration, GitHub Actions workflows, documentation, and issue tracking are maintained here on the `main` branch. Local copies and delivered IPA files are build products or working copies, not independent sources of truth.

- Product baseline: [MiniBrowser_Codex_Spec.md](MiniBrowser_Codex_Spec.md)
- Permanent implementation rules: [AGENTS.md](AGENTS.md)
- Development and bug handoff: [GitHub Issues](https://github.com/quietarc-lab/ios-web-shell/issues)

## MVP features

- URL-only navigation, current URL tracking, last URL restoration, back/forward/reload, and a 30-second timeout
- A persistent static catalog of up to 300 iOS/iPadOS-style User-Agent profiles. IDs 1–100 remain stable; append-only profiles use only documented frozen iOS 18.6/18.6.2 OS forms. Seven-day restricted profiles are skipped, and automatic sessions use a constrained shuffled order without reusing a tried profile. A user-initiated UA change refreshes only the current host's related cookies, launches the AP shortcut, returns automatically, then reloads for cookie verification
- Current-host and parent-domain Cookie deletion followed by reload and verified reacquisition
- `セルラー再接続` through Apple's Shortcuts x-callback URL, automatic return, and public IPv4 comparison without reloading the page when started manually
- Local bookmarks and unlimited-length multiline bookmarklets with edit/delete/drag reorder and exact-domain automatic execution
- Conservative always-on `WKContentRuleList` ad/tracker blocking
- A focused `configured target host` thread layout that keeps the reply form, a four-line opener summary with its image, and locally tracked own replies while hiding surrounding site chrome
- While MiniBrowser remains launched, an image selected through the existing TargetPage handwriting bookmarklet is held only in memory and redrawn after a supported thread reload/navigation with one random pixel added; it is never written to browser storage or logs
- A UA-button-only TargetPage automatic post flow waits for AP, reload, Cookie, compact-form, and handwriting readiness, skips UA profiles quarantined for seven days after an access restriction, starts the next eligible generation, and permits one terminal continuous-post retry (four attempts maximum per generation). If continuous-limit recovery reports an unchanged IP, the AP shortcut is retried up to three times with one-second spacing; AP or IP-check failures still stop the generation
- AP-bracketed IPv4 checks wait briefly for an iOS `NWPathMonitor` satisfied path before starting a request, and the IP/catalog/moderation URL sessions use `waitsForConnectivity`; bounded `NETWORK_PRECHECK` and `NETWORK_POST_AP_GATE` diagnostics distinguish a local cellular transition from a remote request failure. This cannot suppress an iOS or Shortcuts-owned system alert, but avoids starting app-owned requests during the known path transition
- A transient TargetPage proxy/gateway failure (HTTP 502/503/504 or the known `Proxy Error` page) is handled separately from a site posting restriction: multi-thread mode skips that target and continues, while same-thread mode waits one second and reloads once before using the normal communication-failure stop path. The retry is generation- and URL-scoped and does not rotate UA, delete Cookies, or reconnect AP
- The catalog header's non-persistent `同スレ連続` toggle reuses the in-memory comment and handwriting image for repeated posts to the currently open thread after the site's completion marker; each cycle restores the form, adds one image pixel, and passes the existing readiness gate without changing UA, Cookie, page, or AP state. Exact `画像連続投稿はもうしばらく時間を置いてからお願い致します` variants are handed off to the next eligible UA like the image-count restriction
- The catalog header's non-persistent `複数スレ` toggle alternates fresh history-free batches: `勢い順` takes 20 targets at a time up to 60 processed targets, then `カタログ順` takes 10 at a time up to 30, repeating until both sorts have no new target. Threads whose IDs appear in a retained post-body URL are excluded from every batch. It waits one second between successful targets, rotates to a fresh UA generation after every two accepted threads, reuses the UA within each two-thread batch unless a known image/access restriction requires a handoff, gives a short continuous-post restriction one UA handoff per target and then skips only that target if it recurs, and skips only 1,000-reply or unavailable threads for six hours
- In `複数スレ` mode, the exact TargetPage alert `スレッドがありません` (with or without the final Japanese full stop) is treated as a per-target unavailable-thread result: the alert is dismissed, that target is excluded, and posting continues with the next target. Same-thread mode keeps the existing terminal unknown-alert behavior
- The catalog header's small non-persistent `隔離・削除時に自動停止` checkbox is on by default. While either automatic continuous mode is active, MiniBrowser polls Futapo's native `img_b_isolation.txt` feed in the foreground; state `2` is isolation and state `1` is deletion. Same-thread mode watches the displayed thread, and multi-thread mode watches every valid TargetPage thread URL in the captured post body. An exact match stops the whole automatic session, keeps a native reason-specific alert until OK, and repeats a short in-app tone and error haptic every two seconds; feed failures keep the last valid state and retry, and turning the checkbox off disables both stops without changing posting behavior
- If a multi-thread post body references an isolated thread, the posting session stops without showing the moderation alert or starting its alarm while recovery is possible. The same WebView watches the isolated source for up to five active minutes, reloading every ten seconds, for a valid board-B replacement URL immediately before or after a line containing `次`, including explanatory forms such as `隔離されたから次`, quoted markers, and same-line marker/URL forms. Temporary reload/proxy failures retry on the next cycle. When found, every matching source URL in the in-memory comment is replaced, the replacement starter image is captured into the existing handwriting store, open/read history is cleared, the catalog is refreshed from momentum order, and a fresh multi-thread session starts. Recovery success is non-modal; only recovery failure shows `隔離スレの次スレ復旧に失敗したため自動投稿を停止しました` with the existing confirmation-required alarm. Device confirmation remains pending
- Unexpected terminal automatic-post failures now use the same confirmation alert and repeating tone/error haptic path. Manual stops, normal completion, ordinary multi-thread skips, and a normal scene pause/resume do not trigger the alarm; a failed scene resume remains an alertable failure.
- While an automatic post generation, same-thread repeat cycle, or accepted-post verification is active, the foreground scene disables iOS's idle timer and restores it on completion, stop, or background transition; this does not extend iOS background execution
- Switching to another app temporarily pauses an active automatic-post generation instead of terminating it. The in-memory generation, target, draft, image, submission monitor, Cookie/AP state, and multi-thread transition are resumed once after the same target URL is confirmed; background time is excluded from watchdogs, a missing AP callback is retried once, and manual navigation while away safely stops the session. The Shortcuts scene transition caused by an automatic cellular reconnect is treated as expected AP work and does not enter the pause state; if AP finishes while the app remains inactive, normal pause handling begins then. If Shortcuts shows a data-communication failure without returning an x-callback, an automatic AP callback watchdog records the failure and stops the generation instead of leaving it waiting indefinitely. App-process termination does not resume the session.
- A collapsible native two-column official TargetPage list with momentum/catalog sorting, up to 60 active threads, thumbnail retry on refresh, reply counts, and high-contrast visited state
- An exact `このスレッドには書けません` TargetPage alert removes that thread from the native list for six hours; expired exclusions are purged on load and the normal site alert remains visible
- Input-focus auto zoom prevention for small form fields while preserving manual pinch zoom
- A 500-entry redacted debug log; long-press the bottom toolbar and choose `ログをコピー` to copy the latest 50 entries together with a bounded, copy-time UA catalog snapshot (available/restricted IDs and names, restriction expiries, and the selected profile; raw UA values are never included)
- Reusable GitHub Actions unsigned IPA build and Windows/iCloud Drive delivery

To conserve the private repository's GitHub-hosted macOS allowance, the IPA workflow is started manually after a verified change set instead of on every push. Windows static checks should be run before dispatching it.

## Build flow

1. Push the project to a GitHub repository whose default branch is `main`.
2. The caller workflow generates `MiniBrowser.xcodeproj` with XcodeGen on `macos-26` and builds with code signing disabled.
3. It packages and validates `MiniBrowser.ipa`, uploads the IPA without an extra ZIP wrapper, and writes a SHA-256 artifact.
4. A Windows self-hosted runner with the `ios-ipa-delivery` label downloads and validates the IPA.
5. The runner overwrites only `%MINIBROWSER_DELIVERY_DIRECTORY%\MiniBrowser.ipa` and verifies its SHA-256.
6. Open that IPA from the iPhone and let SideStore sign/install it.

No Apple credentials, certificates, provisioning profiles, pairing files, or device identifiers belong in GitHub.

## Local checks on Windows

```powershell
.\scripts\Static-Check.ps1
```

Windows cannot compile this iOS target. The authoritative compile/test check is the GitHub Actions macOS job. See [Windows runner setup](docs/WINDOWS_RUNNER_SETUP.md) for the one-time runner registration.

## Implementation notes

- Cookie matching accepts an exact host or a cookie parent domain only; it does not clear unrelated WebKit data or LocalStorage.
- AP callback uses `shortcuts://x-callback-url/run-shortcut` with success/cancel/error callbacks to `minibrowser://return`. A manually started AP reconnect never reloads the page; the UA-change privacy flow intentionally reloads only after the callback so it can reacquire the current host's cookies.
- Public IPv4 comes from the replaceable `IPAddressService` endpoint (`https://api.ipify.org?format=json`) with an 8-second request timeout.
- Browser-family UA tokens are representative hardcoded profiles. The catalog uses only the frozen iOS 18.6/18.6.2 OS forms documented by WebKit; changing a UA does not change the underlying WebKit engine. See [UA catalog sources](docs/UA_CATALOG_SOURCES.md) for the ID-level provenance record.
- Access-restricted UA IDs are persisted locally for seven days and skipped by automatic rotation. UA rotation diversifies the presented profile but does not by itself anonymize the IP, Cookie, or WebKit fingerprint.
- Legacy generated-UA restriction hashes remain readable for migration compatibility, but no generated UA is selected or created at launch. The selected fixed value is propagated to the WebView, thread-list requests, and IP checks.
- Automatic bookmarklets run only when the configured domain exactly matches the current host. Their stored source is unchanged; execution forces a bridgeable Boolean completion value.
- Page-world helper scripts rewrite app-branded bridge, page-token, DOM, and input-helper markers to neutral names before injection. The product display name and bundle identifier remain unchanged; existing TargetPage storage keys remain compatible for rollback, so this is marker obfuscation rather than complete anti-fingerprinting.
- Automatic-post diagnostics include generation/event ordering, elapsed time, branch/AP/Cookie outcomes, JavaScript callback results, and a separate own-response DOM confirmation or timeout. Comment text, Cookie values, image data, alert text, and raw page tokens are not recorded.
- Automatic multi-thread posting uses generation-scoped terminal ownership and monotonic submission IDs. Preparation signals are bound to their destination URL, captured drafts are restored and verified for exact destination-content equality, unsent work is revoked when the mode is turned off, alternating catalog batches restore the saved sort after completion, and independently cancelled catalog fetches settle the session instead of leaving it active.
- Moderation monitoring uses a native conditional-GET feed reader rather than the Futapo JavaScript page. It stores only normalized isolated/deleted thread IDs in memory, scopes every result to the automatic session, cancels polling and in-flight posting work on an exact match, and never records the post body, feed contents, or Cookie values.
- TargetPage focus mode runs only on `configured target host/*/res/*.htm`. The opener image and four-line text summary sit beside the form; page headers, reload/footer controls, navigation-only bracket text, and other users' replies are hidden. Pending reply text stays in per-tab session storage until matched or expired; persistent history contains response numbers only.
- Input-focus zoom prevention raises only editable controls rendered below 16 px to 16 px. It does not restrict the viewport scale or disable the WKWebView pinch gesture.

Primary references:

- [Apple WKWebView customUserAgent](https://developer.apple.com/documentation/webkit/wkwebview/customuseragent)
- [Apple WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
- [Apple WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
- [Apple Shortcuts x-callback-url](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios)
- [WebKit: Safari 26 UA string change](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/#update-to-ua-string)
- [WebKit bug: iOS input focus auto zoom and pinch zoom](https://bugs.webkit.org/show_bug.cgi?id=285380)
- [GitHub-hosted runner images](https://github.com/actions/runner-images)
- [GitHub self-hosted runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [ipify API](https://www.ipify.org/)
