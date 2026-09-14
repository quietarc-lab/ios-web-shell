import XCTest
@testable import MiniBrowser

final class CanvasImageSessionServiceTests: XCTestCase {
    func testThreadScopeAcceptsOnlyTargetPageThreadPages() {
        XCTAssertTrue(CanvasImageSessionService.isTargetPageThreadURL(
            URL(string: "https://img.2chan.net/b/res/1465000000.htm")
        ))
        XCTAssertFalse(CanvasImageSessionService.isTargetPageThreadURL(
            URL(string: "https://img.2chan.net/b/futaba.php?mode=cat")
        ))
        XCTAssertFalse(CanvasImageSessionService.isTargetPageThreadURL(
            URL(string: "https://example.com/b/res/1465000000.htm")
        ))
    }

    func testBridgeCapturesOnlyExistingHandwritingInputAndRestoresOnePixel() throws {
        let script = CanvasImageSessionService.scriptSource
        XCTAssertTrue(script.contains("input.id !== \"itgkfile\""))
        XCTAssertTrue(script.contains("canvas#oejs"))
        XCTAssertTrue(script.contains("selectedImage"))
        XCTAssertTrue(script.contains("canvasReady"))
        XCTAssertTrue(script.contains("pageReady"))
        XCTAssertTrue(script.contains("contentBridge"))
        XCTAssertTrue(script.contains("__pageSessionToken"))
        XCTAssertFalse(script.contains("miniBrowserHandwriting"))
        XCTAssertFalse(script.contains("__miniBrowserPageToken"))
        XCTAssertFalse(script.contains("localStorage"))
        XCTAssertFalse(script.contains("sessionStorage"))

        let store = TargetPageHandwritingImageStore()
        XCTAssertTrue(store.replace(withDataURL: "data:image/png;base64,AAECAwQ="))
        let restoration = try XCTUnwrap(store.restorationScript())
        XCTAssertTrue(restoration.contains("context.fillRect(x, y, 1, 1)"))
        XCTAssertTrue(restoration.contains("canvas#oejs"))
        XCTAssertTrue(restoration.contains("tegakiJs.oeUpdate"))
        XCTAssertTrue(restoration.contains("baseform"))
        XCTAssertTrue(restoration.contains("canvas.toDataURL"))
        XCTAssertTrue(restoration.contains("handwritingReady"))
        XCTAssertTrue(restoration.contains("contentBridge"))
        XCTAssertTrue(restoration.contains("__pageSessionToken"))
        XCTAssertFalse(restoration.contains("miniBrowserHandwriting"))
        XCTAssertFalse(restoration.contains("__miniBrowserPageToken"))
        XCTAssertFalse(restoration.contains("itgkfile"))
        XCTAssertFalse(restoration.contains("javascript:"))
        let generationRestoration = try XCTUnwrap(store.restorationScript(generationID: 12))
        XCTAssertTrue(generationRestoration.contains("generationID: 12"))
        XCTAssertTrue(CanvasImageSessionService.canvasVisibilityScript.contains("exists"))
        XCTAssertTrue(CanvasImageSessionService.canvasVisibilityScript.contains("visible"))
        XCTAssertTrue(CanvasImageSessionService.openExistingCanvasScript.contains("手書きjs"))
        XCTAssertTrue(CanvasImageSessionService.openExistingCanvasScript.contains("trigger.click()"))
        XCTAssertTrue(CanvasImageSessionService.openExistingCanvasScript.contains("#oebtnj"))
        XCTAssertTrue(CanvasImageSessionService.openExistingCanvasScript.contains("getComputedStyle"))
        XCTAssertTrue(CanvasImageSessionService.openExistingCanvasScript.contains("attempts < 50"))
    }

    func testStoreRejectsUnsupportedAndCreatesNoCrossLaunchState() {
        let store = TargetPageHandwritingImageStore()
        XCTAssertFalse(store.replace(withDataURL: "data:text/plain;base64,SGVsbG8="))
        XCTAssertFalse(store.hasImage)
        XCTAssertFalse(TargetPageHandwritingImageStore().hasImage)
    }
}
