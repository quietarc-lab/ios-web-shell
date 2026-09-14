import Foundation
import WebKit

/// Bridges the existing TargetPage handwriting bookmarklet to an in-memory native store.
/// The selected source image is deliberately never persisted, logged, or shared.
enum CanvasImageSessionService {
    static let messageHandlerName = PageMarkerNamespace.bridgeName
    static let maximumImageDataByteCount = 3_000_000

    static let scriptSource = PageMarkerNamespace.neutralize(#"""
    (() => {
      "use strict";

      if (location.hostname !== "img.2chan.net" ||
          !/^\/[^/]+\/res\/\d+\.htm$/.test(location.pathname)) {
        return;
      }

      const handler = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.miniBrowserHandwriting;
      if (!handler) return;

      const pageToken = (() => {
        if (typeof window.__miniBrowserPageToken === "string" &&
            window.__miniBrowserPageToken.length > 0) {
          return window.__miniBrowserPageToken;
        }
        const token = String(Date.now()) + "-" + String(Math.random());
        window.__miniBrowserPageToken = token;
        return token;
      })();

      function sendNative(payload) {
        handler.postMessage(Object.assign({ pageToken }, payload));
      }

      const maximumBytes = 3000000;

      function captureSelectedImage(input) {
        if (!(input instanceof HTMLInputElement) || input.id !== "itgkfile") return;
        const file = input.files && input.files[0];
        if (!file || file.size > maximumBytes || !/^image\/(gif|jpe?g|png|webp)$/i.test(file.type)) {
          return;
        }
        const reader = new FileReader();
        reader.addEventListener("load", () => {
          if (typeof reader.result !== "string") return;
          sendNative({ type: "selectedImage", dataURL: reader.result });
        }, { once: true });
        reader.readAsDataURL(file);
      }

      document.addEventListener("change", event => {
        captureSelectedImage(event.target);
      }, true);

      function notifyCanvasReady() {
        const canvas = document.querySelector("canvas#oejs");
        if (!canvas || canvas.dataset.minibrowserHandwritingRestoreRequested === "true") return;
        canvas.dataset.minibrowserHandwritingRestoreRequested = "true";
        sendNative({ type: "canvasReady" });
      }

      const observer = new MutationObserver(notifyCanvasReady);
      observer.observe(document.documentElement, { childList: true, subtree: true });
      notifyCanvasReady();

      function notifyPageReady() {
        sendNative({ type: "pageReady" });
      }
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", notifyPageReady, { once: true });
      } else {
        notifyPageReady();
      }
    })();
    """#)

    static func install(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: scriptSource,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
    }

    static func isTargetPageThreadURL(_ url: URL?) -> Bool {
        guard let url,
              url.host?.lowercased() == "img.2chan.net" else {
            return false
        }
        return url.path.range(of: #"^/[^/]+/res/\d+\.htm$"#,
                              options: .regularExpression) != nil
    }

    static let canvasVisibilityScript = PageMarkerNamespace.neutralize(#"""
    (() => {
      "use strict";
      const isVisible = element => {
        if (!(element instanceof Element)) return false;
        const style = window.getComputedStyle(element);
        return style.display !== "none" &&
          style.visibility !== "hidden" &&
          element.getClientRects().length > 0;
      };
      const canvas = document.querySelector("canvas#oejs");
      const host = document.getElementById("oe3");
      return {
        exists: Boolean(canvas),
        visible: Boolean(canvas && isVisible(host || canvas))
      };
    })();
    """#)

    static let openExistingCanvasScript = PageMarkerNamespace.neutralize(#"""
    (() => {
      "use strict";

      const isVisible = element => {
        if (!(element instanceof Element)) return false;
        const style = window.getComputedStyle(element);
        return style.display !== "none" &&
          style.visibility !== "hidden" &&
          element.getClientRects().length > 0;
      };

      const canvasHost = document.getElementById("oe3");
      const canvas = document.querySelector("canvas#oejs");
      if (canvas && isVisible(canvasHost || canvas)) return;

      let clicked = false;
      let attempts = 0;
      const openExistingField = () => {
        const currentCanvas = document.querySelector("canvas#oejs");
        const currentHost = document.getElementById("oe3");
        if (currentCanvas && isVisible(currentHost || currentCanvas)) return;
        attempts += 1;
        if (!clicked) {
          const trigger = Array.from(document.querySelectorAll(
            "#oebtnj, [onclick*='ChangeDraw'], a, button, input[type='button'], input[type='submit']"
          )).find(element => {
            if (!isVisible(element)) return false;
            const text = String(element.value || element.textContent || "").replace(/\s+/g, "");
            const onclick = String(element.getAttribute("onclick") || "");
            return element.id === "oebtnj" ||
              /ChangeDraw\s*\(\s*['\"]j['\"]\s*\)/i.test(onclick) ||
              /手書きjs/.test(text);
          });
          if (trigger instanceof HTMLElement) {
            clicked = true;
            trigger.click();
          }
        }
        if (attempts < 50) {
          setTimeout(openExistingField, 120);
        }
      };
      openExistingField();
    })();
    """#)
}

final class TargetPageHandwritingImageStore {
    private struct SessionImage {
        let mimeType: String
        let data: Data

        var dataURL: String {
            "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
    }

    private static let supportedMimeTypes: Set<String> = [
        "image/gif", "image/jpeg", "image/png", "image/webp"
    ]

    private var image: SessionImage?

    var hasImage: Bool {
        image != nil
    }

    @discardableResult
    func replace(withDataURL dataURL: String) -> Bool {
        guard let parsed = Self.parseDataURL(dataURL),
              parsed.data.count <= CanvasImageSessionService.maximumImageDataByteCount else {
            return false
        }
        image = SessionImage(mimeType: parsed.mimeType, data: parsed.data)
        return true
    }

    func restorationScript(generationID: UInt64? = nil) -> String? {
        guard let image,
              let dataURLLiteral = javaScriptStringLiteral(image.dataURL) else {
            return nil
        }
        let generationLiteral = generationID.map(String.init) ?? "null"

        return PageMarkerNamespace.neutralize(#"""
        (() => {
          const canvas = document.querySelector("canvas#oejs");
          const handler = window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.miniBrowserHandwriting;
          const pageToken = window.__miniBrowserPageToken || "";
          const notifyReady = ready => {
            if (!handler) return;
            handler.postMessage({
              type: "handwritingReady",
              pageToken,
              generationID: \#(generationLiteral),
              ready: Boolean(ready)
            });
          };
          if (!canvas) {
            notifyReady(false);
            return;
          }
          const source = new Image();
          source.onload = () => {
            let scale = 1;
            if (source.width > 400 || source.height > 400) {
              scale = source.width > source.height ? 400 / source.width : 400 / source.height;
            }
            canvas.width = Math.max(1, Math.round(source.width * scale));
            canvas.height = Math.max(1, Math.round(source.height * scale));
            const context = canvas.getContext("2d");
            if (!context) {
              notifyReady(false);
              return;
            }
            context.drawImage(source, 0, 0, source.width, source.height,
                              0, 0, canvas.width, canvas.height);
            const x = Math.floor(Math.random() * canvas.width);
            const y = Math.floor(Math.random() * canvas.height);
            context.fillStyle = "rgba(" + Math.floor(Math.random() * 256) + "," +
              Math.floor(Math.random() * 256) + "," + Math.floor(Math.random() * 256) + ",1)";
            context.fillRect(x, y, 1, 1);

            const updateBaseForm = () => {
              const baseForm = document.getElementById("baseform");
              if (!baseForm) return false;
              let dataURL;
              try {
                dataURL = canvas.toDataURL();
              } catch (_) {
                return false;
              }
              if ("value" in baseForm) {
                baseForm.value = dataURL;
                if ("defaultValue" in baseForm) baseForm.defaultValue = dataURL;
              } else {
                baseForm.setAttribute("value", dataURL);
              }
              baseForm.dispatchEvent(new Event("input", { bubbles: true }));
              baseForm.dispatchEvent(new Event("change", { bubbles: true }));
              return true;
            };

            const updatePayload = async () => {
              if (window.tegakiJs && typeof window.tegakiJs.oeUpdate === "function") {
                try {
                  await window.tegakiJs.oeUpdate();
                  return true;
                } catch (_) {}
              }
              return updateBaseForm();
            };

            updatePayload().then(notifyReady).catch(() => notifyReady(false));
          };
          source.onerror = () => notifyReady(false);
          source.src = \#(dataURLLiteral);
        })();
        """#)
    }

    private static func parseDataURL(_ value: String) -> (mimeType: String, data: Data)? {
        guard let separator = value.firstIndex(of: ",") else { return nil }
        let header = String(value[..<separator]).lowercased()
        guard header.hasPrefix("data:"), header.hasSuffix(";base64") else { return nil }

        let mimeType = String(header.dropFirst("data:".count).dropLast(";base64".count))
        guard supportedMimeTypes.contains(mimeType),
              let data = Data(base64Encoded: String(value[value.index(after: separator)...]),
                              options: .ignoreUnknownCharacters),
              !data.isEmpty else {
            return nil
        }
        return (mimeType, data)
    }

    private func javaScriptStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
