# MiniBrowser

MiniBrowser is a lightweight iPhone browser built with SwiftUI and `WKWebView`. It targets iOS 26 and is designed to be built unsigned on GitHub Actions, then re-signed and installed with SideStore.

## Canonical repository

[quietarc-lab/ios-web-shell](https://github.com/quietarc-lab/ios-web-shell) is the single source of truth for MiniBrowser. Application code, XcodeGen configuration, GitHub Actions workflows, documentation, and issue tracking are maintained here on the `main` branch. Local copies and delivered IPA files are build products or working copies, not independent sources of truth.

- Product baseline: [MiniBrowser_Codex_Spec.md](MiniBrowser_Codex_Spec.md)
- Permanent implementation rules: [AGENTS.md](AGENTS.md)
- Development and bug handoff: [GitHub Issues](https://github.com/quietarc-lab/ios-web-shell/issues)

## MVP features

- URL-only navigation, current URL tracking, last URL restoration, back/forward/reload, and a 30-second timeout
- One hundred persistent iOS/iPadOS-style User-Agent profiles plus one validated, launch-only generated mobile profile per cold process start; the fixed catalog is replaced as a versioned set so old selections and quarantine IDs do not carry over. A user-initiated UA change refreshes only the current host's related cookies, launches the AP shortcut, returns automatically, then reloads for cookie verification
- Current-host and parent-domain Cookie deletion followed by reload and verified reacquisition
- `セルラー再接続` through Apple's Shortcuts x-callback URL, automatic return, and public IPv4 comparison without reloading the page when started manually
- Local bookmarks and unlimited-length multiline bookmarklets with edit/delete/drag reorder and exact-domain automatic execution
- Conservative always-on `WKContentRuleList` ad/tracker blocking
- A focused `configured target host` thread layout that keeps the reply form, a four-line opener summary with its image, and locally tracked own replies while hiding surrounding site chrome
- While MiniBrowser remains launched, an image selected through the existing TargetPage handwriting bookmarklet is held only in memory and redrawn after a supported thread reload/navigation with one random pixel added; it is never written to browser storage or logs
- A UA-button-only TargetPage automatic post flow waits for AP, reload, Cookie, compact-form, and handwriting readiness, skips UA profiles quarantined for seven days after an access restriction, starts the next eligible generation, and permits one terminal continuous-post retry (four attempts maximum per generation)
- A collapsible native two-column official TargetPage list with momentum/catalog sorting, up to 60 active threads, thumbnail retry on refresh, reply counts, and high-contrast visited state
- An exact `このスレッドには書けません` TargetPage alert removes that thread from the native list for six hours; expired exclusions are purged on load and the normal site alert remains visible
- Input-focus auto zoom prevention for small form fields while preserving manual pinch zoom
- A 500-entry redacted debug log; long-press the bottom toolbar and choose `ログをコピー` to copy the latest 50 entries
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
- Browser-family UA tokens are representative hardcoded profiles. The fixed catalog keeps the OS portion at the final iOS 18 value for compatibility; the launch generator uses only curated iOS 17/18 mobile tokens, and changing a UA does not change the underlying WebKit engine.
- Access-restricted UA IDs are persisted locally for seven days and skipped by automatic rotation. UA rotation diversifies the presented profile but does not by itself anonymize the IP, Cookie, or WebKit fingerprint.
- The cold-start generated profile is assembled only from the curated mobile templates, held in memory for that process, and propagated to the WebView, thread-list requests, and IP checks. Generated restriction keys use a per-install salted digest; raw generated values and digest keys are not logged.
- Automatic bookmarklets run only when the configured domain exactly matches the current host. Their stored source is unchanged; execution forces a bridgeable Boolean completion value.
- Page-world helper scripts rewrite app-branded bridge, page-token, DOM, and input-helper markers to neutral names before injection. The product display name and bundle identifier remain unchanged; existing TargetPage storage keys remain compatible for rollback, so this is marker obfuscation rather than complete anti-fingerprinting.
- Automatic-post diagnostics include generation/event ordering, elapsed time, branch/AP/Cookie outcomes, JavaScript callback results, and a separate own-response DOM confirmation or timeout. Comment text, Cookie values, image data, alert text, and raw page tokens are not recorded.
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
