import XCTest
@testable import MiniBrowser

final class CompactPageModeServiceTests: XCTestCase {
    func testScriptIsRestrictedToImgThreadPages() {
        let script = CompactPageModeService.scriptSource
        XCTAssertTrue(script.contains("location.hostname !== \"img.2chan.net\""))
        XCTAssertTrue(script.contains(#"\/res\/"#))
    }

    func testScriptIncludesRequestedFocusModeBehavior() {
        let script = CompactPageModeService.scriptSource
        XCTAssertTrue(script.contains("width=device-width, initial-scale=1"))
        XCTAssertTrue(script.contains(".pagehelper-targetpage-form .ftb2"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-starter"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-context"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-opener"))
        XCTAssertTrue(script.contains("-webkit-line-clamp: 4"))
        XCTAssertTrue(script.contains("本文なし"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-page-extra"))
        XCTAssertTrue(script.contains("#contres"))
        XCTAssertTrue(script.contains("#ufm"))
        XCTAssertTrue(script.contains("pagehelper-own-response"))
        XCTAssertTrue(script.contains("thread.querySelectorAll(\"table\")"),
                      "Responses may be wrapped in a container during asynchronous posting.")
        XCTAssertTrue(script.contains("markThreadExtras"))
        XCTAssertTrue(script.contains("comparableText"))
        XCTAssertTrue(script.contains("compactText"))
        XCTAssertTrue(script.contains("hasAttachment"))
        XCTAssertTrue(script.contains("MiniBrowser.TargetPageOwnPosts:"))
        XCTAssertTrue(script.contains("10 * 60 * 1000"),
                      "Unmatched post bodies must expire instead of remaining indefinitely.")
        XCTAssertTrue(script.contains("pagehelper-targetpage-email-row"))
        XCTAssertTrue(script.contains("clearEmail"))
        XCTAssertTrue(script.contains("textarea.rows = 2"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-delete-help"))
        XCTAssertTrue(script.contains("disableFormPositionToggle"))
        XCTAssertTrue(script.contains("preserveDeleteKey"))
        XCTAssertFalse(script.contains("deleteInput.readOnly = true"))
        XCTAssertFalse(script.contains("fixedDeleteKey"))
        XCTAssertTrue(script.contains("pagehelper-targetpage-comment-actions"))
        XCTAssertTrue(script.contains("modeHeader.classList.add(\"pagehelper-targetpage-page-extra\")"))
        XCTAssertTrue(script.contains("clearStandaloneBracketText"))
        XCTAssertTrue(script.contains("previous.nodeType === Node.TEXT_NODE"))
        XCTAssertTrue(script.contains("next.nodeType === Node.TEXT_NODE"))
        XCTAssertTrue(script.contains("form.insertBefore(actions, formTable || form.firstChild)"))
        XCTAssertTrue(script.contains("#retmestip"))
        XCTAssertFalse(script.contains("pagehelper-targetpage-submit-status"))
        XCTAssertTrue(script.contains("localStorage.removeItem(\"MiniBrowser.TargetPageFormPlacement\")"))
        XCTAssertFalse(script.contains("latestOwnResponse.table.after(form)"))
        XCTAssertTrue(script.contains("initializeCompactPage"))
        XCTAssertTrue(script.contains("pagehelperCompactInitialized"))
        XCTAssertTrue(script.contains("retryCount >= 20"))
        XCTAssertTrue(script.contains("type: \"threadUnavailable\""))
        XCTAssertTrue(script.contains("THREAD_NOT_POSTABLE"))
        XCTAssertTrue(script.contains("notifyThreadUnavailable"))
    }

    func testScriptIncludesGlobalDraftRetentionControls() {
        let script = CompactPageModeService.scriptSource
        XCTAssertTrue(script.contains("MiniBrowser.TargetPageDraftEnabled"))
        XCTAssertTrue(script.contains("MiniBrowser.TargetPageDraftText"))
        XCTAssertTrue(script.contains("保持 ON"))
        XCTAssertTrue(script.contains("保持 OFF"))
        XCTAssertTrue(script.contains("localStorage.removeItem(draftTextKey)"))
        XCTAssertTrue(script.contains("capturePostState"))
        XCTAssertTrue(script.contains("submitButton.addEventListener(\"click\", capturePostState, true)"))
        XCTAssertTrue(script.contains("restoreSubmittedDraft"))
        XCTAssertTrue(script.contains("userEditedAfterSubmission"))
        XCTAssertTrue(script.contains("type: \"postCompleted\""))
        XCTAssertTrue(script.contains("type: \"postStatus\""))
        XCTAssertTrue(script.contains("type: \"submitObserved\""))
        XCTAssertTrue(script.contains("notifyNativeSubmitObserved"))
        XCTAssertTrue(script.contains("consumeAutomaticSubmissionID"))
        XCTAssertTrue(script.contains("__pageSessionActiveSubmissionID"))
        XCTAssertTrue(script.contains("withAutomaticSubmissionID"))
        XCTAssertTrue(script.contains("capturedSubmissionID"))
        XCTAssertTrue(script.contains("captureAwaitingSubmit"))
        XCTAssertTrue(script.contains("comment: String(textarea && textarea.value || \"\")"))
        XCTAssertTrue(script.contains("form.addEventListener(\"submit\", notifyNativeSubmitObserved, true)"))
        XCTAssertTrue(script.contains("type: \"ownPostVisible\""))
        XCTAssertTrue(script.contains("type: \"ownPostObservation\""))
        XCTAssertTrue(script.contains("notifyOwnPostObservation"))
        XCTAssertTrue(script.contains("matchedCount"))
        XCTAssertTrue(script.contains("responseCount"))
        XCTAssertTrue(script.contains("matchMethod"))
        XCTAssertTrue(script.contains("status: normalized"))
        XCTAssertTrue(script.contains("lastNativePostStatus"))
        XCTAssertTrue(script.contains("observePostCompletionStatus"))
        XCTAssertTrue(script.contains("completionObserver.observe(status"))
        XCTAssertTrue(script.contains("check the current value immediately"))
        XCTAssertTrue(script.contains("completionDiscoveryObserver.observe(doc.body"))
    }

    func testAutomaticBridgeUsesPageTokenAndExistingButtonClick() throws {
        let script = CompactPageModeService.scriptSource
        XCTAssertTrue(script.contains("__pageSessionToken"))
        XCTAssertTrue(script.contains("contentBridge"))
        XCTAssertTrue(script.contains("type: \"compactReady\""))
        XCTAssertTrue(script.contains("notifyCompactReady()"))
        XCTAssertTrue(script.contains("type: \"postCompleted\""))
        XCTAssertTrue(script.contains("type: \"postStatus\""))

        let stateScript = CompactPageModeService.currentPostStateScript
        XCTAssertTrue(stateScript.contains("hasComment"))
        XCTAssertTrue(stateScript.contains("comment:"))
        XCTAssertTrue(stateScript.contains("canSubmit"))

        let availabilityScript = CompactPageModeService.threadAvailabilityScript
        XCTAssertTrue(availabilityScript.contains("hasThread"))
        XCTAssertTrue(availabilityScript.contains("hasForm"))
        XCTAssertTrue(availabilityScript.contains("textarea[name=\"com\"]"))
        XCTAssertTrue(availabilityScript.contains("eligible"))
        XCTAssertFalse(availabilityScript.contains("form.submit"))

        let restoreScript = try XCTUnwrap(
            CompactPageModeService.restoreAutomaticDraftScript(comment: "保存本文")
        )
        XCTAssertTrue(restoreScript.contains("textarea.value"))
        XCTAssertTrue(restoreScript.contains("dispatchEvent(new Event(\"input\""))
        XCTAssertTrue(restoreScript.contains("dispatchEvent(new Event(\"change\""))
        XCTAssertTrue(restoreScript.contains("textarea.value !=="))
        XCTAssertTrue(restoreScript.contains("comment: String(textarea.value || \"\")"))
        XCTAssertFalse(restoreScript.contains("form.submit"))
        XCTAssertFalse(restoreScript.contains("localStorage"))

        let repeatImageScript = CompactPageModeService.repeatCanvasUpdateScript(generationID: 7)
        XCTAssertTrue(repeatImageScript.contains("generationID"))
        XCTAssertTrue(repeatImageScript.contains("fillRect(x, y, 1, 1)"))
        XCTAssertTrue(repeatImageScript.contains("tegakiJs.oeUpdate"))
        XCTAssertTrue(repeatImageScript.contains("canvas.toDataURL"))
        XCTAssertTrue(repeatImageScript.contains("baseform"))
        XCTAssertTrue(repeatImageScript.contains("handwritingReady"))
        XCTAssertFalse(repeatImageScript.contains("form.submit"))
        XCTAssertFalse(repeatImageScript.contains("itgkfile"))
        XCTAssertFalse(repeatImageScript.contains("javascript:"))

        let submitScript = CompactPageModeService.autoSubmitScript
        XCTAssertTrue(submitScript.contains("submitButton.click()"))
        XCTAssertFalse(submitScript.contains("form.submit"))
        XCTAssertFalse(submitScript.contains("itgkfile"))

        let identifiedSubmitScript = CompactPageModeService.autoSubmitScript(for: 17)
        XCTAssertTrue(identifiedSubmitScript.contains(
            "window.__pageSessionPendingSubmissionID = 17; window.__pageSessionActiveSubmissionID = 17;"
        ))
        XCTAssertTrue(identifiedSubmitScript.contains("submitButton.click()"))
        XCTAssertFalse(identifiedSubmitScript.contains("form.submit"))
    }

    func testSubmitReadinessScriptReportsStablePageConditions() {
        let script = CompactPageModeService.submitReadinessScript
        XCTAssertTrue(script.contains("type: \"submitReadiness\""))
        XCTAssertTrue(script.contains("document.readyState"))
        XCTAssertTrue(script.contains("form.isConnected"))
        XCTAssertTrue(script.contains("submitButton.isConnected"))
        XCTAssertTrue(script.contains("submitButton.disabled"))
        XCTAssertTrue(script.contains("aria-disabled"))
        XCTAssertTrue(script.contains("retmestip"))
        XCTAssertTrue(script.contains("POST_IN_FLIGHT"))
        XCTAssertTrue(script.contains("reason: \"READY\""))
        XCTAssertTrue(script.contains("__pageSessionToken"))
        XCTAssertFalse(script.contains("form.submit"))
    }
}
