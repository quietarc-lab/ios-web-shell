import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const projectRoot = process.argv[2];
if (!projectRoot) {
  throw new Error("Usage: node Validate-InjectedJavaScript.mjs <project-root>");
}

const sources = [
  ["MiniBrowser/Services/CompactPageModeService.swift", "scriptSource"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "currentPostStateScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "threadAvailabilityScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "submitReadinessScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "autoSubmitScript"],
  ["MiniBrowser/Services/CanvasImageSessionService.swift", "scriptSource"],
  ["MiniBrowser/Services/CanvasImageSessionService.swift", "openExistingCanvasScript"],
  ["MiniBrowser/Services/InputAutoZoomPreventionService.swift", "scriptSource"],
  ["MiniBrowser/Services/IsolationThreadMonitor.swift", "sourceThreadMonitorScript"],
  ["MiniBrowser/Services/IsolationThreadMonitor.swift", "replacementStarterImageCaptureScript"]
];

const generatedSources = [
  ["MiniBrowser/Services/CompactPageModeService.swift", "restoreAutomaticDraftScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "repeatCanvasUpdateScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "makeAutoSubmitScript"],
  ["MiniBrowser/Services/CanvasImageSessionService.swift", "restorationScript"]
];

function rawSwiftScript(filePath, property) {
  const source = fs.readFileSync(filePath, "utf8");
  const declaration = source.indexOf(`static let ${property}`);
  if (declaration < 0) {
    throw new Error(`Raw JavaScript property not found: ${filePath} (${property})`);
  }

  const scriptStartMarker = '#"""';
  const scriptStart = source.indexOf(scriptStartMarker, declaration);
  if (scriptStart < 0) {
    throw new Error(`Raw JavaScript literal not found: ${filePath} (${property})`);
  }
  const scriptContentStart = scriptStart + scriptStartMarker.length;
  const scriptEnd = source.indexOf('\"\"\"#', scriptContentStart);
  if (scriptEnd < 0) {
    throw new Error(`Raw JavaScript terminator not found: ${filePath} (${property})`);
  }
  return source.slice(scriptContentStart, scriptEnd);
}

function rawSwiftGeneratedScript(filePath, functionName) {
  const source = fs.readFileSync(filePath, "utf8");
  const declaration = source.indexOf(`static func ${functionName}`) >= 0
    ? source.indexOf(`static func ${functionName}`)
    : source.indexOf(`func ${functionName}`);
  if (declaration < 0) {
    throw new Error(`Generated JavaScript function not found: ${filePath} (${functionName})`);
  }
  const scriptStartMarker = '#"""';
  const scriptStart = source.indexOf(scriptStartMarker, declaration);
  if (scriptStart < 0) {
    throw new Error(`Generated JavaScript literal not found: ${filePath} (${functionName})`);
  }
  const scriptContentStart = scriptStart + scriptStartMarker.length;
  const scriptEnd = source.indexOf('\"\"\"#', scriptContentStart);
  if (scriptEnd < 0) {
    throw new Error(`Generated JavaScript terminator not found: ${filePath} (${functionName})`);
  }
  // Replace Swift extended-string interpolation with harmless JavaScript
  // literals before parsing. Runtime values are covered by the Swift tests.
  return source.slice(scriptContentStart, scriptEnd)
    .replace(/\\#\([^)]*\)/g, '"placeholder"');
}

for (const [relativePath, property] of sources) {
  const filePath = path.join(projectRoot, relativePath);
  const script = rawSwiftScript(filePath, property);
  try {
    new Function(script);
  } catch (error) {
    throw new Error(`${relativePath} (${property}) has invalid JavaScript: ${error.message}`);
  }
}

for (const [relativePath, functionName] of generatedSources) {
  const filePath = path.join(projectRoot, relativePath);
  const script = rawSwiftGeneratedScript(filePath, functionName);
  try {
    new Function(script);
  } catch (error) {
    throw new Error(`${relativePath} (${functionName}) has invalid JavaScript: ${error.message}`);
  }
}

function runNextLinkFixture(projectRoot, renderedText, href, options = {}) {
  const monitorFile = path.join(projectRoot, "MiniBrowser/Services/IsolationThreadMonitor.swift");
  const monitor = rawSwiftScript(monitorFile, "sourceThreadMonitorScript")
    .replaceAll("miniBrowserHandwriting", "contentBridge")
    .replaceAll("__miniBrowserPageToken", "__pageSessionToken")
    .replaceAll("__miniBrowserInputAutoZoomPreventionInstalled", "__inputAutoZoomInstalled")
    .replaceAll("minibrowser", "pagehelper");
  const messages = [];
  let mutationCallback = null;
  let timeoutCallback = null;
  const container = {
    innerText: renderedText,
    textContent: options.textContent ?? renderedText,
    parentElement: null
  };
  const anchor = {
    href,
    innerText: href,
    textContent: href,
    parentElement: container
  };
  const previousGlobals = new Map();
  for (const name of ["window", "document", "location", "MutationObserver", "setTimeout", "clearTimeout"]) {
    previousGlobals.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
  }
  globalThis.window = {
    __pageSessionToken: "fixture-page-token",
    webkit: { messageHandlers: { contentBridge: { postMessage: message => messages.push(message) } } }
  };
  globalThis.location = { href: "https://img.2chan.net/b/res/1234567890.htm" };
  globalThis.document = {
    querySelectorAll: selector => selector === "a[href]" ? [anchor] : [],
    documentElement: {},
    body: { innerText: renderedText }
  };
  globalThis.MutationObserver = class {
    constructor(callback) { mutationCallback = callback; }
    observe() {}
    disconnect() {}
  };
  globalThis.setTimeout = callback => { timeoutCallback = callback; return 1; };
  globalThis.clearTimeout = () => {};

  try {
    new Function(monitor)();
    if (options.updatedRenderedText !== undefined) {
      container.innerText = options.updatedRenderedText;
      container.textContent = options.updatedTextContent ?? options.updatedRenderedText;
      mutationCallback?.();
    }
    if (options.fireTimeout) timeoutCallback?.();
    return messages;
  } finally {
    for (const [name, descriptor] of previousGlobals) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete globalThis[name];
    }
  }
}

const nextURL = "https://img.2chan.net/b/res/1471234519.htm";
assert.equal(
  runNextLinkFixture(projectRoot, `次\n${nextURL}`, nextURL)[0]?.threadURL,
  nextURL,
  "a URL on the line immediately after 次 should be detected"
);
for (const marker of ["つぎ", "next", "NEXT", "NeXt"]) {
  assert.equal(
    runNextLinkFixture(projectRoot, `${marker}\n${nextURL}`, nextURL)[0]?.threadURL,
    nextURL,
    `${marker} should be accepted as a next marker`
  );
}
assert.equal(
  runNextLinkFixture(projectRoot, `> 次\n${nextURL}`, nextURL)[0]?.threadURL,
  nextURL,
  "the same two-line link inside a quoted reply should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `隔離されたから次\n${nextURL}`, nextURL)[0]?.threadURL,
  nextURL,
  "a two-line link after an explanatory next marker should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `隔離されたから次 ${nextURL}`, nextURL)[0]?.threadURL,
  nextURL,
  "a same-line explanatory next marker should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `${nextURL}\n隔離されたから次`, nextURL)[0]?.threadURL,
  nextURL,
  "a URL immediately before an explanatory next marker should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, "", nextURL, {
    textContent: `隔離されたから次\n${nextURL}`
  })[0]?.threadURL,
  nextURL,
  "hidden reply text should be inspected through textContent"
);
assert.equal(
  runNextLinkFixture(projectRoot, `説明\n次のスレ\n${nextURL}`, nextURL).length,
  1,
  "any line containing 次 immediately before the URL should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `次\n説明\n${nextURL}`, nextURL).length,
  0,
  "a non-adjacent URL must not be treated as a next link"
);
assert.equal(
  runNextLinkFixture(projectRoot, `次\n${nextURL}`, "https://img.2chan.net/c/res/1471234519.htm")
    .length,
  0,
  "a URL without /b/res/ must not be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `本文\n${nextURL}`, nextURL, {
    updatedRenderedText: `次\n${nextURL}`
  })[0]?.threadURL,
  nextURL,
  "a next link inserted after initial page load should be detected"
);
assert.equal(
  runNextLinkFixture(projectRoot, `本文\n${nextURL}`, nextURL)[0]?.type,
  undefined,
  "a page without a next marker should not emit a candidate"
);
assert.equal(
  runNextLinkFixture(projectRoot, `本文\n${nextURL}`, nextURL, { fireTimeout: true })[0]?.type,
  "isolationRecoveryNoCandidate",
  "a loaded page without a next link should report a diagnostic no-candidate result"
);

console.log(`Injected JavaScript syntax and next-link fixture checks passed (${sources.length + generatedSources.length} scripts).`);
