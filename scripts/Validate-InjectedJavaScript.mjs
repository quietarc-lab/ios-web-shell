import fs from "node:fs";
import path from "node:path";

const projectRoot = process.argv[2];
if (!projectRoot) {
  throw new Error("Usage: node Validate-InjectedJavaScript.mjs <project-root>");
}

const sources = [
  ["MiniBrowser/Services/CompactPageModeService.swift", "scriptSource"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "currentPostStateScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "submitReadinessScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "autoSubmitScript"],
  ["MiniBrowser/Services/CanvasImageSessionService.swift", "scriptSource"],
  ["MiniBrowser/Services/CanvasImageSessionService.swift", "openExistingCanvasScript"],
  ["MiniBrowser/Services/InputAutoZoomPreventionService.swift", "scriptSource"]
];

const generatedSources = [
  ["MiniBrowser/Services/CompactPageModeService.swift", "restoreAutomaticDraftScript"],
  ["MiniBrowser/Services/CompactPageModeService.swift", "repeatCanvasUpdateScript"],
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

console.log(`Injected JavaScript syntax checks passed (${sources.length + generatedSources.length} scripts).`);
