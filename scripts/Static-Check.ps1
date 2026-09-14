[CmdletBinding()]
param(
    [switch]$PublicMetadata
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Assert-Contains {
    param([string]$Path, [string]$Pattern, [string]$Description)
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -notmatch $Pattern) {
        throw "Missing requirement: $Description ($Path)"
    }
}

function Assert-NotContains {
    param([string]$Path, [string]$Pattern, [string]$Description)
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -match $Pattern) {
        throw "Unexpected content: $Description ($Path)"
    }
}

$projectFile = Join-Path $projectRoot 'project.yml'
$uaFile = Join-Path $projectRoot 'MiniBrowser\Models\BrowserUserAgent.swift'
$viewModelFile = Join-Path $projectRoot 'MiniBrowser\ViewModels\BrowserViewModel.swift'
$webViewFile = Join-Path $projectRoot 'MiniBrowser\Web\BrowserWebView.swift'
$contentViewFile = Join-Path $projectRoot 'MiniBrowser\Views\ContentView.swift'
$sitePostStatusViewFile = Join-Path $projectRoot 'MiniBrowser\Views\SitePostStatusView.swift'
$dialogPolicyFile = Join-Path $projectRoot 'MiniBrowser\Support\WebDialogPolicy.swift'
$automaticFlowFile = Join-Path $projectRoot 'MiniBrowser\Support\AutomaticPostFlow.swift'
$idleTimerPolicyFile = Join-Path $projectRoot 'MiniBrowser\Support\IdleTimerPolicy.swift'
$runtimeUserAgentFile = Join-Path $projectRoot 'MiniBrowser\Support\RuntimeUserAgentGenerator.swift'
$uaRestrictionFile = Join-Path $projectRoot 'MiniBrowser\Support\UserAgentRestrictionStore.swift'
$sitePostStatusFile = Join-Path $projectRoot 'MiniBrowser\Models\SitePostStatus.swift'
$inputZoomFile = Join-Path $projectRoot 'MiniBrowser\Services\InputAutoZoomPreventionService.swift'
$markerNamespaceFile = Join-Path $projectRoot 'MiniBrowser\Support\PageMarkerNamespace.swift'
$focusModeFile = Join-Path $projectRoot 'MiniBrowser\Services\CompactPageModeService.swift'
$handwritingServiceFile = Join-Path $projectRoot 'MiniBrowser\Services\CanvasImageSessionService.swift'
$listServiceFile = Join-Path $projectRoot 'MiniBrowser\Services\ThreadListService.swift'
$listViewFile = Join-Path $projectRoot 'MiniBrowser\Views\ThreadListView.swift'
$listViewModelFile = Join-Path $projectRoot 'MiniBrowser\ViewModels\ThreadListViewModel.swift'
$multiThreadSessionFile = Join-Path $projectRoot 'MiniBrowser\Support\MultiThreadPostSession.swift'
$infoFile = Join-Path $projectRoot 'MiniBrowser\Info.plist'
$workflowFile = Join-Path $projectRoot '.github\workflows\reusable-ios-unsigned-build-deliver.yml'
$deliveryScriptFile = Join-Path $projectRoot 'scripts\Deliver-Ipa.ps1'
$javaScriptValidationFile = Join-Path $projectRoot 'scripts\Validate-InjectedJavaScript.mjs'
$specFile = Join-Path $projectRoot 'MiniBrowser_Codex_Spec.md'
$agentsFile = Join-Path $projectRoot 'AGENTS.md'

Assert-Contains $projectFile 'iOS:\s*"26\.0"' 'iOS 26 deployment target'
Assert-Contains $webViewFile 'WKWebViewConfiguration' 'WKWebView configuration'
Assert-Contains $webViewFile 'websiteDataStore\s*=\s*\.default\(\)' 'persistent website data store'
Assert-Contains $webViewFile 'InputAutoZoomPreventionService\.install' 'input focus auto-zoom prevention'
Assert-Contains $inputZoomFile 'fontSize\s*<\s*16' 'small input font-size guard'
Assert-Contains $inputZoomFile 'forMainFrameOnly:\s*false' 'input auto-zoom prevention in subframes'
Assert-Contains $markerNamespaceFile 'static let bridgeName = "contentBridge"' 'neutral page bridge name'
Assert-Contains $markerNamespaceFile 'static let pageTokenName = "__pageSessionToken"' 'neutral page token name'
Assert-Contains $markerNamespaceFile 'static func neutralize' 'central page marker rewrite'
Assert-Contains $focusModeFile 'PageMarkerNamespace\.neutralize' 'neutral compact-page markers'
Assert-Contains $handwritingServiceFile 'PageMarkerNamespace\.neutralize' 'neutral handwriting markers'
Assert-Contains $inputZoomFile 'PageMarkerNamespace\.neutralize' 'neutral input markers'
Assert-Contains $focusModeFile 'MiniBrowser\.TargetPageDraftEnabled' 'global TargetPage draft setting'
Assert-Contains $focusModeFile 'clearEmail' 'empty TargetPage email guard'
Assert-Contains $focusModeFile 'preserveDeleteKey' 'preserved TargetPage deletion key'
Assert-NotContains $focusModeFile 'fixedDeleteKey' 'no forced TargetPage deletion key'
Assert-NotContains $focusModeFile 'deleteInput\.readOnly\s*=\s*true' 'editable TargetPage deletion key'
Assert-Contains $focusModeFile 'textarea\.rows\s*=\s*2' 'compact TargetPage comment field'
Assert-Contains $focusModeFile 'disableFormPositionToggle' 'disabled TargetPage form position switch'
Assert-Contains $focusModeFile 'localStorage\.removeItem\("MiniBrowser\.TargetPageFormPlacement"\)' 'cleared legacy TargetPage form placement setting'
Assert-NotContains $focusModeFile 'minibrowser-targetpage-form-placement' 'no MiniBrowser form placement control'
Assert-NotContains $focusModeFile 'latestOwnResponse\.table\.after\(form\)' 'no bottom placement after own response'
Assert-NotContains $focusModeFile 'minibrowser-targetpage-submit-status' 'no MiniBrowser submit status slot'
Assert-Contains $focusModeFile '#retmestip' 'hidden TargetPage submit status'
Assert-Contains $focusModeFile 'capturePostState' 'TargetPage draft capture on posting'
Assert-Contains $focusModeFile 'postCompleted' 'TargetPage post completion handwriting bridge'
Assert-Contains $focusModeFile 'type: "postStatus"' 'TargetPage post status bridge'
Assert-Contains $focusModeFile 'type: "ownPostVisible"' 'TargetPage own-response visibility bridge'
Assert-Contains $focusModeFile 'type: "ownPostObservation"' 'TargetPage own-response observation bridge'
Assert-Contains $focusModeFile 'type: "compactReady"' 'TargetPage compact-ready bridge'
Assert-Contains $focusModeFile 'type: "submitReadiness"' 'TargetPage submit-readiness bridge'
Assert-Contains $focusModeFile 'type: "submitObserved"' 'TargetPage native submit-observed bridge'
Assert-Contains $focusModeFile '__pageSessionPendingSubmissionID' 'automatic submit correlation marker'
Assert-Contains $focusModeFile '__pageSessionActiveSubmissionID' 'automatic completion correlation marker'
Assert-Contains $focusModeFile 'document.readyState' 'TargetPage document readiness check'
Assert-Contains $focusModeFile 'POST_IN_FLIGHT' 'TargetPage in-flight submit guard'
Assert-Contains $focusModeFile '__miniBrowserPageToken' 'TargetPage page token'
Assert-Contains $focusModeFile 'submitButton\.click\(\)' 'existing TargetPage submit button click'
Assert-NotContains $focusModeFile 'form\.submit\(\)' 'no direct TargetPage form.submit'
Assert-Contains $focusModeFile 'currentPostStateScript' 'read-only TargetPage post-state script'
Assert-Contains $focusModeFile 'autoSubmitScript' 'automatic TargetPage submit script'
Assert-Contains $focusModeFile 'restoreAutomaticDraftScript' 'same-thread draft restoration script'
Assert-Contains $focusModeFile 'repeatCanvasUpdateScript' 'same-thread canvas update script'
Assert-Contains $focusModeFile 'status: normalized' 'normalized TargetPage post status bridge'
Assert-Contains $focusModeFile 'observePostCompletionStatus' 'TargetPage post completion status observer'
Assert-Contains $focusModeFile 'initializeCompactPage' 'retryable TargetPage compact-page initialization'
Assert-Contains $listServiceFile 'bytes=0-32767' 'bounded TargetPage opener request'
Assert-Contains $listServiceFile 'limit:\s*Int\s*=\s*60' 'sixty-item TargetPage list limit'
Assert-Contains $listServiceFile 'replyCount\s*<\s*1_000' 'completed TargetPage thread exclusion'
Assert-Contains $listViewModelFile 'listItemLimit\s*=\s*60' 'sixty-item TargetPage list request'
Assert-Contains $listViewModelFile 'mergingDisplayState' 'list thumbnail state preservation across refresh'
Assert-Contains $listViewFile 'LazyVGrid' 'native two-column TargetPage list'
Assert-Contains $listViewFile 'model\.recordOpen\(item\)' 'persistent TargetPage list open counter'
Assert-Contains $listViewFile 'thumbnailData' 'explicit TargetPage thumbnail rendering'
Assert-Contains $listServiceFile 'makeThumbnailRequest' 'explicit TargetPage thumbnail request'
Assert-Contains $listServiceFile 'updateUserAgent' 'selected UA propagation to TargetPage list requests'
Assert-Contains $listViewModelFile 'setNetworkActivityAllowed' 'TargetPage list pause during identity refresh'
Assert-Contains $listServiceFile 'excludingIDs' 'temporary unavailable-thread filtering'
Assert-Contains $listViewModelFile 'excludedThreadExpirations' 'expiring unavailable-thread storage'
Assert-Contains $listViewModelFile 'excludedThreadRetention' 'six-hour unavailable-thread retention'
Assert-Contains $multiThreadSessionFile 'MultiThreadPostSession' 'multi-thread posting session model'
Assert-Contains $multiThreadSessionFile 'CatalogPostSnapshot' 'catalog posting snapshot model'
Assert-Contains $multiThreadSessionFile 'processedThreadIDs' 'multi-thread processed target tracking'
Assert-Contains $listViewModelFile 'refreshPostSnapshot' 'one-shot catalog refresh provider'
Assert-Contains $viewModelFile 'multiThreadSessionActive' 'multi-thread session lifecycle state'
Assert-Contains $viewModelFile 'finishMultiThreadSession' 'multi-thread session completion'
Assert-Contains $viewModelFile 'NEXT_THREAD_NAVIGATION_STARTED' 'multi-thread navigation diagnostics'
Assert-Contains $viewModelFile 'CATALOG_REFRESH_STARTED' 'multi-thread catalog refresh diagnostics'
Assert-Contains $listViewFile '複数スレ' 'multi-thread toggle label'
Assert-Contains $dialogPolicyFile 'このスレッドには書けません' 'thread posting unavailable classification'
Assert-Contains $webViewFile 'onThreadPostingUnavailable' 'unavailable-thread bridge callback'
Assert-Contains $contentViewFile 'excludeThread' 'unavailable-thread list wiring'
Assert-Contains $focusModeFile 'modeHeader\.classList\.add' 'hidden TargetPage response-mode header'
Assert-Contains $webViewFile 'CanvasImageSessionService\.install' 'TargetPage handwriting session bridge installation'
Assert-Contains $webViewFile 'WKScriptMessageHandler' 'TargetPage handwriting native message receiver'
Assert-Contains $handwritingServiceFile 'miniBrowserHandwriting' 'TargetPage handwriting message handler'
Assert-Contains $handwritingServiceFile 'input\.id !== "itgkfile"' 'existing handwriting input-only image capture'
Assert-Contains $handwritingServiceFile 'canvas#oejs' 'existing handwriting canvas-only restoration'
Assert-Contains $handwritingServiceFile 'pageReady' 'TargetPage handwriting page-ready signal'
Assert-Contains $handwritingServiceFile 'tegakiJs\.oeUpdate' 'TargetPage handwriting tegaki update'
Assert-Contains $handwritingServiceFile 'canvas\.toDataURL' 'TargetPage handwriting fallback payload'
Assert-Contains $handwritingServiceFile 'handwritingReady' 'TargetPage handwriting readiness signal'
Assert-Contains $handwritingServiceFile 'openExistingCanvasScript' 'existing handwriting control opener'
Assert-Contains $webViewFile 'case "postCompleted"' 'TargetPage post-completion handwriting receiver'
Assert-Contains $webViewFile 'case "postStatus"' 'TargetPage post-status receiver'
Assert-Contains $webViewFile 'case "ownPostVisible"' 'TargetPage own-response visibility receiver'
Assert-Contains $webViewFile 'case "ownPostObservation"' 'TargetPage own-response observation receiver'
Assert-Contains $webViewFile 'case "compactReady"' 'TargetPage compact-ready receiver'
Assert-Contains $webViewFile 'case "submitReadiness"' 'TargetPage submit-readiness receiver'
Assert-Contains $webViewFile 'case "submitObserved"' 'TargetPage submit-observed receiver'
Assert-Contains $webViewFile 'case "handwritingReady"' 'TargetPage handwriting-ready receiver'
Assert-Contains $contentViewFile 'SitePostStatusView' 'fixed site post status overlay'
Assert-Contains $sitePostStatusViewFile 'frame\(width: 240, height: 28\)' 'fixed site post status dimensions'
Assert-Contains $sitePostStatusFile 'UA準備中' 'automatic UA preparation status'
Assert-Contains $sitePostStatusFile '受付済み・反映確認中' 'automatic accepted-pending status'
Assert-Contains $sitePostStatusFile '完了（反映未確認）' 'automatic unconfirmed-completion status'
Assert-Contains $sitePostStatusFile '連続制限 → AP再接続中' 'automatic continuous-limit AP status'
Assert-Contains $sitePostStatusFile '自動投稿停止' 'automatic stop status'
Assert-Contains $automaticFlowFile 'maximumAttempts = 4' 'automatic post attempt limit'
Assert-Contains $automaticFlowFile 'startNextAutomaticFlow' 'automatic access-restriction handoff'
Assert-Contains $automaticFlowFile 'continuousRetryUsed' 'continuous-post retry guard'
Assert-Contains $automaticFlowFile 'waitingForSubmitReadiness' 'submit readiness state'
Assert-Contains $automaticFlowFile 'waitingForContinuousAPRetry' 'continuous-limit AP retry state'
Assert-Contains $automaticFlowFile 'startContinuousAPReconnect' 'continuous-limit AP retry effect'
Assert-Contains $automaticFlowFile 'submitResponseTimedOut' 'automatic submit response timeout event'
Assert-Contains $automaticFlowFile 'submitResponseRetry' 'automatic submit conditional retry reason'
Assert-Contains $automaticFlowFile 'generationID' 'automatic post generation guard'
Assert-Contains $automaticFlowFile 'stalePageToken' 'automatic post page token guard'
Assert-Contains $runtimeUserAgentFile 'maximumAttempts = 32' 'bounded launch user-agent generation'
Assert-Contains $runtimeUserAgentFile 'static func isValid' 'validated launch user-agent generation'
Assert-Contains $runtimeUserAgentFile 'iPhone' 'iPhone launch user-agent candidates'
Assert-Contains $runtimeUserAgentFile 'iPad' 'iPad launch user-agent candidates'
Assert-Contains $dialogPolicyFile 'return false' 'site alerts are not auto-dismissed'
Assert-Contains $dialogPolicyFile 'TargetPageAlertClassifier' 'known target-page alert classification'
Assert-Contains $dialogPolicyFile 'アクセス規制中です' 'access restriction alert classification'
Assert-Contains $dialogPolicyFile '連続投稿はもうしばらく時間を置いてからお願い致します' 'continuous-post alert classification'
Assert-Contains $viewModelFile 'recordTargetPageAlert' 'target-page alert observation'
Assert-Contains $viewModelFile 'ALERT_MESSAGE' 'target-page alert message diagnostics'
Assert-Contains $viewModelFile 'handleUnknownJavaScriptAlert\(message:' 'unknown alert message diagnostics'
Assert-Contains $viewModelFile 'OWN_RESPONSE_CONFIRMED' 'automatic own-response confirmation logging'
Assert-Contains $viewModelFile 'OWN_RESPONSE_TIMEOUT' 'automatic own-response timeout logging'
Assert-Contains $viewModelFile 'EVENT_SEQ' 'automatic event ordering metadata'
Assert-Contains $viewModelFile 'ELAPSED_MS' 'automatic elapsed-time metadata'
Assert-Contains $viewModelFile 'AP_PURPOSE' 'AP purpose logging'
Assert-Contains $viewModelFile 'COOKIE_SAMPLE_PHASE' 'Cookie sample phase logging'
Assert-Contains $viewModelFile 'nextEligibleUserAgentIndex' 'restricted-UA rotation'
Assert-Contains $uaRestrictionFile '7 \* 24 \* 60 \* 60' 'seven-day UA restriction duration'
Assert-Contains $uaRestrictionFile 'generatedRestrictionKey' 'salted generated-UA restriction key'
Assert-Contains $viewModelFile 'effectiveUserAgent' 'effective launch-UA propagation'
Assert-Contains $viewModelFile 'User Agent Launch Selection' 'anonymous launch-UA selection log'
Assert-Contains $viewModelFile 'RELOADED_POST_COOKIE_UNVERIFIED' 'cookie reload is not treated as posting-cookie proof'
Assert-Contains $viewModelFile 'sameThreadRepeatEnabled' 'same-thread repeat toggle state'
Assert-Contains $viewModelFile 'setAppSceneActive' 'foreground scene activity wiring'
Assert-Contains $viewModelFile 'isIdleTimerDisabled' 'automatic processing idle-timer control'
Assert-Contains $contentViewFile 'setAppSceneActive' 'foreground scene idle-timer wiring'
Assert-Contains $idleTimerPolicyFile 'shouldDisableIdleTimer' 'idle-timer activity policy'
Assert-Contains $viewModelFile 'REPEAT_SCHEDULED' 'same-thread repeat scheduling log'
Assert-Contains $viewModelFile 'sameThreadRepeatMinimumDelayNanoseconds: UInt64 = 250_000_000' 'short same-thread repeat delay'
Assert-Contains $viewModelFile 'sameThreadRepeatSubmitDelayNanoseconds: UInt64 = 0' 'no extra same-thread submit delay'
Assert-Contains $viewModelFile 'SUBMIT_DELAY_SCHEDULED' 'same-thread submit delay logging'
Assert-Contains $viewModelFile 'REPEAT_PREPARATION_READY' 'same-thread repeat preparation log'
Assert-Contains $viewModelFile 'REPEAT_STOPPED' 'same-thread repeat stop log'
Assert-Contains $viewModelFile 'PREPARATION_TIMEOUT' 'preparation timeout diagnostics'
Assert-Contains $viewModelFile 'EVALUATION_FALSE' 'JavaScript false-result diagnostics'
Assert-Contains $viewModelFile 'BRIDGE_PAYLOAD_INVALID' 'invalid bridge payload diagnostics'
Assert-Contains $viewModelFile 'REPEAT_IMAGE_PREPARATION_FAILED' 'repeat image preparation diagnostics'
Assert-Contains $viewModelFile 'POST_COMPLETED_IGNORED' 'late completion diagnostics'
Assert-Contains $viewModelFile 'SUBMIT_RESPONSE_TIMEOUT' 'automatic submit response timeout diagnostics'
Assert-Contains $viewModelFile 'SUBMIT_EVENT_OBSERVED' 'automatic native submit diagnostics'
Assert-Contains $viewModelFile 'preparationDiagnosticFields' 'preparation stage diagnostics'
Assert-Contains $viewModelFile 'handwritingPreparationGenerationID' 'generation-tagged handwriting preparation'
Assert-Contains $listViewFile '同スレ連続' 'same-thread repeat toggle label'
Assert-Contains $automaticFlowFile 'beginSameThreadRepeat' 'same-thread repeat preparation state'
Assert-Contains $automaticFlowFile 'sameThreadRepeat' 'same-thread repeat readiness reason'
Assert-Contains $handwritingServiceFile 'context\.fillRect\(x, y, 1, 1\)' 'single-pixel handwriting image variation'
Assert-Contains $handwritingServiceFile 'canvasVisibilityScript' 'same-thread canvas visibility check'
Assert-Contains $handwritingServiceFile 'maximumImageDataByteCount = 3_000_000' 'bounded in-memory handwriting image size'
Assert-Contains $projectFile 'ASSETCATALOG_COMPILER_APPICON_NAME:\s*AppIcon' 'AppIcon asset compiler setting'

$listViewModelText = Get-Content -LiteralPath $listViewModelFile -Raw -Encoding UTF8
if ($listViewModelText -match 'withTaskGroup|withThrowingTaskGroup') {
    throw 'TargetPage opener loading must avoid the task-group completion crash seen on iOS 26.5.2.'
}
Assert-Contains $viewModelFile 'CookieDomainMatcher' 'site-related cookie filter'
Assert-Contains $viewModelFile 'minibrowser://return' 'MiniBrowser callback URL'
Assert-Contains $viewModelFile 'isIdentityRefreshInProgress' 'UA identity refresh state'
Assert-Contains $viewModelFile 'deleteRelatedCookiesForRefresh' 'UA cookie deletion before AP reconnect'
Assert-Contains $viewModelFile 'evaluateJavaScript' 'bookmarklet execution'
Assert-Contains $workflowFile 'CODE_SIGNING_ALLOWED=NO' 'unsigned build'
Assert-Contains $workflowFile 'actions/download-artifact@v8' 'artifact download on Windows'
Assert-Contains $deliveryScriptFile 'MINIBROWSER_DELIVERY_DIRECTORY' 'runner-local delivery directory'
Assert-Contains $specFile '# MiniBrowser 実装仕様書' 'canonical product specification'
Assert-Contains $agentsFile 'quietarc-lab/ios-web-shell' 'canonical repository rule'
Assert-Contains $agentsFile 'GitHub Issues' 'issue handoff rule'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw 'Node.js is required to validate injected JavaScript.'
}
& $node.Source $javaScriptValidationFile $projectRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Injected JavaScript syntax validation failed.'
}

$uaText = Get-Content -LiteralPath $uaFile -Raw -Encoding UTF8
$expectedUserAgentCount = 100
$uaCount = ([regex]::Matches($uaText, '\.init\(id:\s*\d+')).Count
if ($uaCount -ne $expectedUserAgentCount) {
    throw "Expected exactly $expectedUserAgentCount user agents, found $uaCount."
}
$uaValues = [regex]::Matches($uaText, 'value:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
$distinctUaCount = ($uaValues | Select-Object -Unique).Count
if ($distinctUaCount -ne $expectedUserAgentCount) {
    throw "Expected $expectedUserAgentCount distinct user-agent strings."
}
if ($uaValues -match 'CPU (iPhone )?OS 26_') {
    throw 'iOS 26 UA profiles must use the frozen iOS 18 OS token.'
}

[xml]$plist = Get-Content -LiteralPath $infoFile -Raw -Encoding UTF8
if ($plist.plist.dict.key -notcontains 'CFBundleURLTypes') {
    throw 'CFBundleURLTypes is missing from Info.plist.'
}
if ($plist.plist.dict.key -notcontains 'UISupportedInterfaceOrientations') {
    throw 'Portrait orientation declaration is missing from Info.plist.'
}

if ($plist.plist.dict.key -notcontains 'CFBundleIconName') {
    throw 'CFBundleIconName is missing from Info.plist.'
}

$appIconContents = Join-Path $projectRoot 'MiniBrowser\Assets.xcassets\AppIcon.appiconset\Contents.json'
if (-not (Test-Path -LiteralPath $appIconContents)) {
    throw 'AppIcon asset list is missing.'
}
$marketingIcon = Join-Path $projectRoot 'MiniBrowser\Assets.xcassets\AppIcon.appiconset\Icon-1024.png'
if (-not (Test-Path -LiteralPath $marketingIcon)) {
    throw '1024px App Store icon is missing.'
}

$inputZoomText = Get-Content -LiteralPath $inputZoomFile -Raw -Encoding UTF8
if ($inputZoomText -match 'maximum-scale|user-scalable|pinchGestureRecognizer') {
    throw 'Manual pinch zoom must remain enabled.'
}

$cookieValueLeaks = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'MiniBrowser') -Filter '*.swift' -Recurse |
    Select-String -Pattern 'cookie\.value' -CaseSensitive:$false
if ($cookieValueLeaks) {
    throw 'Cookie values must not be accessed or logged.'
}

if ($PublicMetadata) {
    # Construct audit needles without retaining legacy identifiers as searchable text.
    $legacySiteTerm = -join [char[]](102, 117, 116, 97, 98, 97)
    $legacyJapaneseTerm = -join [char[]](0x3075, 0x305f, 0x3070)
    $legacyBoardTerm = -join [char[]](0x4e8c, 0x6b21, 0x5143, 0x88cf)
    $legacyCompanionTerm = -join [char[]](102, 117, 116, 97, 107, 117, 114, 111)
    $legacyAccountTerm = -join [char[]](115, 116, 97, 107, 97, 110, 111, 49, 50, 51, 45, 97, 49, 49, 121)
    $legacyHostToken = -join [char[]](50, 99, 104, 97, 110)
    $legacyLocalUser = -join [char[]](115, 116, 97, 107, 97)
    $legacyPathTerm = "C:\Users\$legacyLocalUser"
    $forbiddenTerms = @($legacySiteTerm, $legacyJapaneseTerm, $legacyBoardTerm, $legacyCompanionTerm, $legacyAccountTerm, $legacyPathTerm)
    $forbiddenPattern = '(?i)' + (($forbiddenTerms | ForEach-Object { [regex]::Escape($_) }) -join '|')
    $allowedHostPattern = '(?i)(?:[a-z0-9-]+\.)*' + [regex]::Escape("$legacyHostToken.net")
    $allowedEndpoint = "$legacySiteTerm.php"
    $textFiles = @(git -C $projectRoot ls-files | Where-Object { $_ -notmatch '\.(png|jpe?g|gif|webp|ipa|zip)$' })
    foreach ($relativePath in $textFiles) {
        $path = Join-Path $projectRoot $relativePath
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $content = $content -replace $allowedHostPattern, ''
        $content = $content.Replace($allowedEndpoint, '')
        if ($content -match $forbiddenPattern) {
            throw "Public metadata check found a forbidden term in $relativePath."
        }
    }

    $historyMetadata = git -C $projectRoot log --all --format='%an%n%ae%n%s'
    if ($historyMetadata -match $forbiddenPattern) {
        throw 'Public metadata check found a forbidden term in reachable Git history.'
    }
}

Write-Host 'Static checks passed.'
Write-Host "User agents: $uaCount"
Write-Host "Distinct user-agent strings: $distinctUaCount"
Write-Host 'Cookie value access: none'
Write-Host 'Deployment target: iOS 26.0'
if ($PublicMetadata) {
    Write-Host 'Public metadata audit: passed'
}
