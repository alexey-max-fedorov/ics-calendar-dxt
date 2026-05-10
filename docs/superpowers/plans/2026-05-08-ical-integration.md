# iCal Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Subagent model (verbatim):** `sonnet[1m]` — every implementer, spec reviewer, and code-quality reviewer subagent dispatched while executing this plan must run on the `sonnet[1m]` model. Pass it through whatever parameter the harness exposes (Agent tool `model:`, custom config, etc.) — the key requirement is that the model identifier `sonnet[1m]` reaches the dispatched subagent. Do not silently substitute `sonnet`, `opus`, or `haiku`.

**Goal:** Build, test, and package an `.mcpb` Claude Desktop extension that exposes seven MCP tools (list/get/search/create/update/delete events + availability) backed by a Swift+EventKit CLI binary spawned by a Node MCP server.

**Architecture:** Node MCP server (TypeScript, `@modelcontextprotocol/sdk`) registers seven tools and translates each `CallToolRequest` into a `child_process.spawn` of a self-contained arm64 Swift CLI (`bin/ical-bridge`). The Swift binary uses EventKit (`EKEventStore`) directly against the local Calendar database, requesting macOS TCC calendar permission on first run. All IPC is single-shot JSON: server passes args, binary writes one JSON object to stdout and exits. No CalDAV, no credentials, no network.

**Tech Stack:**
- Node 18+ with TypeScript (strict, ES2022, ESM), `pnpm` 9, `@modelcontextprotocol/sdk` ^1, Zod ^3, Vitest ^1
- Swift 5.9+, SwiftPM, `swift-argument-parser`, EventKit, XCTest
- macOS 13+ (arm64 only), MCPB manifest v0.3
- Build orchestration via `pnpm` scripts + `@anthropic-ai/mcpb` packer

**PRD reference:** `ical-integration-prd.md` at the repo root. Every section number reference (`§5.2`, etc.) points there. The PRD is the spec of record; if any task and the PRD conflict, the PRD wins — flag the conflict and stop.

**Working directory invariants:**
- Repo root: `/Users/alexey/Projects/ical-dxt` (single git repo, branch `main`)
- All `pnpm` commands run from repo root
- All `swift` / `swift test` / `./build.sh` commands run from `swift/`
- The Swift binary output path is **always** `bin/ical-bridge` relative to repo root
- Use `pnpm`, never `npm` or `yarn`. The presence of `package-lock.json` or `yarn.lock` is a defect — delete and re-run `pnpm install`.

**Style rules (apply to every task):**
- No em dashes (—) in any committed text (manifest, README, comments, error messages, JSON descriptions). Use commas, parens, or sentence breaks.
- No comments unless a non-obvious WHY needs documenting (per repo CLAUDE.md). Names should carry intent.
- TDD: write the failing test, watch it fail, write minimal code, watch it pass, refactor, commit.
- Frequent commits — one per task minimum, more if the task contains independent units.
- Stdout in the Swift binary is sacred: only the single JSON result object goes to stdout. Logs, debug prints, errors → stderr.

---

## File Layout (target end state)

```
ical-dxt/
├── manifest.json                          # MCPB v0.3
├── package.json                           # pnpm-only
├── pnpm-lock.yaml                         # committed
├── tsconfig.json
├── vitest.config.ts
├── .mcpbignore
├── .gitignore
├── README.md
├── LICENSE
├── PRIVACY.md
├── icon.png                               # 256x256
├── ical-integration-prd.md                # already exists
├── docs/superpowers/plans/2026-05-08-ical-integration.md  # this file
│
├── scripts/
│   └── package.sh                         # builds, repacks, .mcpb
│
├── src/
│   ├── index.ts                           # MCP server entry
│   ├── bridge.ts                          # spawns Swift binary
│   ├── schemas.ts                         # Zod + JSON Schemas
│   ├── types.ts
│   └── __tests__/
│       ├── bridge.test.ts
│       └── fixtures/
│           ├── stub-calendars.sh
│           ├── stub-events.sh
│           ├── stub-create.sh
│           ├── stub-error.sh
│           └── stub-crash.sh
│
├── server/                                # tsc output (gitignored, packed)
│   └── index.js                           # plus bridge.js, schemas.js, types.js
│
├── swift/
│   ├── Package.swift
│   ├── build.sh
│   ├── Sources/ICalBridge/
│   │   ├── main.swift
│   │   ├── CalendarStore.swift
│   │   ├── EventMapper.swift
│   │   ├── OutputJSON.swift
│   │   └── BridgeError.swift
│   └── Tests/ICalBridgeTests/
│       ├── EventMapperTests.swift
│       └── SmokeTests.swift
│
├── bin/
│   └── ical-bridge                        # gitignored, packed
│
└── node_modules/                          # gitignored; prod-only flat copy is packed
```

---

## Phase 0 — Repo Scaffold

### Task 1: Root config files (package.json, tsconfig, vitest, .gitignore, .mcpbignore)

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `vitest.config.ts`
- Create: `.gitignore`
- Create: `.mcpbignore`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "ical-integration",
  "version": "1.0.0",
  "type": "module",
  "main": "server/index.js",
  "scripts": {
    "build:server": "tsc",
    "build:swift": "cd swift && ./build.sh",
    "build": "pnpm build:swift && pnpm build:server",
    "package": "pnpm build && bash scripts/package.sh",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "test:watch": "vitest",
    "clean": "rm -rf server/ bin/ swift/.build *.mcpb"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.4.0",
    "vitest": "^1.6.0"
  },
  "engines": {
    "node": ">=18",
    "pnpm": ">=8"
  },
  "packageManager": "pnpm@9.0.0"
}
```

- [ ] **Step 2: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "node",
    "outDir": "./server",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": false,
    "sourceMap": false,
    "resolveJsonModule": true,
    "types": ["node", "vitest/globals"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "server", "swift", "bin", "src/__tests__"]
}
```

Note: `src/__tests__` is excluded from the prod build. The vitest config below picks them up at test time.

- [ ] **Step 3: Write `vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/__tests__/**/*.test.ts'],
  },
});
```

- [ ] **Step 4: Write `.gitignore`**

```
node_modules/
server/
bin/
swift/.build/
swift/Package.resolved
*.mcpb
.DS_Store
*.log
.vscode/
.idea/
```

- [ ] **Step 5: Write `.mcpbignore`**

```
src/
swift/
node_modules/.cache/
*.log
.DS_Store
.git/
.github/
.vscode/
.idea/
tsconfig.json
vitest.config.ts
pnpm-lock.yaml
docs/
*.mcpb
ical-integration-prd.md
```

- [ ] **Step 6: Run `pnpm install`**

```bash
pnpm install
```

Expected: creates `node_modules/` and `pnpm-lock.yaml`. No `package-lock.json` and no `yarn.lock`. If either appears, delete it.

- [ ] **Step 7: Verify pnpm is the only lockfile**

```bash
ls | grep -E '(lock|yaml)' | sort
```

Expected output (one line): `pnpm-lock.yaml`

- [ ] **Step 8: Commit**

```bash
git add package.json tsconfig.json vitest.config.ts .gitignore .mcpbignore pnpm-lock.yaml
git commit -m "chore: scaffold pnpm + tsc + vitest config"
```

---

### Task 2: MCPB manifest

**Files:**
- Create: `manifest.json`

- [ ] **Step 1: Write `manifest.json`**

Copy verbatim from PRD §4 (`manifest.json` block). Verify after writing:
- `manifest_version` is `"0.3"`
- `server.entry_point` is `"server/index.js"`
- `server.mcp_config.env.ICAL_BRIDGE_BIN` is `"${__dirname}/bin/ical-bridge"`
- `tools` contains exactly seven entries: `list_calendars`, `get_events`, `search_events`, `create_event`, `update_event`, `delete_event`, `get_availability`
- `compatibility.platforms` is `["darwin"]`

(Tools-array entries in the manifest carry only `name` and a single-line `description`. Input schemas live in `src/schemas.ts` and are returned at runtime by `ListToolsRequestSchema` — do not duplicate them in the manifest.)

- [ ] **Step 2: Validate JSON**

```bash
node -e "JSON.parse(require('fs').readFileSync('manifest.json','utf8'))" && echo OK
```

Expected: `OK`

- [ ] **Step 3: Verify no em dashes in description fields**

```bash
grep -nP '\x{2014}' manifest.json && echo "FAIL: em dash found" || echo OK
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add manifest.json
git commit -m "feat: add MCPB v0.3 manifest with 7 tools"
```

---

### Task 3: LICENSE, PRIVACY, README skeleton, icon placeholder

**Files:**
- Create: `LICENSE`
- Create: `PRIVACY.md`
- Create: `README.md`
- Create: `icon.png` (placeholder allowed; final asset in Task 28)

- [ ] **Step 1: Fetch the deskview-mcp LICENSE for verbatim adaptation**

The PRD §9 mandates the LICENSE be identical to `deskview-mcp/LICENSE`, with "Deskview MCP" → "iCal Integration" and "Deskview MCP License" → "iCal Integration License".

```bash
# Use WebFetch to retrieve the raw LICENSE text from the deskview-mcp repo:
#   https://raw.githubusercontent.com/alexey-max-fedorov/deskview-mcp/main/LICENSE
```

If the WebFetch fails or the file is not found at that URL, escalate to the human with status `BLOCKED` — do not invent a LICENSE.

- [ ] **Step 2: Write `LICENSE`**

Apply the substitutions ("Deskview MCP" → "iCal Integration", "Deskview MCP License" → "iCal Integration License") and save the result to `LICENSE`. Preserve all other terms verbatim.

- [ ] **Step 3: Verify substitutions**

```bash
grep -c "iCal Integration" LICENSE
grep -c "Deskview" LICENSE
```

Expected: first count >= 2, second count = 0.

- [ ] **Step 4: Write `PRIVACY.md`**

```markdown
# Privacy Policy

iCal Integration is an MCP server that runs entirely on your local machine.

## Data handling

- All calendar data stays on the local machine. Nothing is transmitted to any external server.
- The bundled Swift binary reads and writes the local EventKit database, the same database that Calendar.app uses.
- iCloud, Google, and Exchange syncing is performed by the macOS Calendar service, not by this extension. This extension never sees your iCloud, Google, or Exchange credentials.
- No telemetry, analytics, or crash reports are sent.
- macOS will prompt you for calendar permission on first use. That prompt is controlled entirely by the operating system. You can revoke access in System Settings, Privacy and Security, Calendars.

## Permissions

iCal Integration requests full access to your calendars (read and write). Without that permission the extension cannot list events or create new ones. There is no "read only" mode in v1.

## Contact

Questions or concerns: alexey.max.fedorov@gmail.com
```

- [ ] **Step 5: Write `README.md` skeleton**

```markdown
# iCal Integration

A Claude Desktop Extension that gives Claude full read and write access to your macOS Calendar (including any iCloud, Google, or Exchange calendars visible in Calendar.app) via Apple's native EventKit framework.

No app-specific passwords. No CalDAV. No credential storage. The extension reads and writes the same local Calendar database that Calendar.app uses.

## Requirements

- macOS 13.0 or later (Apple Silicon)
- Claude Desktop 1.0.0 or later

## Installation

(Filled in during Task 28.)

## Tools

(Filled in during Task 28.)

## Privacy

See PRIVACY.md.

## License

See LICENSE.
```

- [ ] **Step 6: Create placeholder `icon.png`**

```bash
# 256x256 transparent PNG placeholder via base64.
# Final icon is produced in Task 28.
python3 - <<'PY'
import base64, struct, zlib
def png_chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
sig = b'\x89PNG\r\n\x1a\n'
ihdr = png_chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 6, 0, 0, 0))
raw = b''.join(b'\x00' + b'\x00\x00\x00\x00'*256 for _ in range(256))
idat = png_chunk(b'IDAT', zlib.compress(raw, 9))
iend = png_chunk(b'IEND', b'')
open('icon.png','wb').write(sig+ihdr+idat+iend)
PY
file icon.png
```

Expected: `icon.png: PNG image data, 256 x 256, 8-bit/color RGBA, non-interlaced`

- [ ] **Step 7: Commit**

```bash
git add LICENSE PRIVACY.md README.md icon.png
git commit -m "chore: add LICENSE (adapted from deskview-mcp), PRIVACY, README skeleton, icon placeholder"
```

---

## Phase 1 — Swift CLI Skeleton (stub JSON output, no EventKit yet)

### Task 4: SwiftPM package + build script

**Files:**
- Create: `swift/Package.swift`
- Create: `swift/build.sh`
- Create: `swift/Sources/ICalBridge/main.swift` (placeholder, replaced in Task 8)

- [ ] **Step 1: Write `swift/Package.swift`**

Copy verbatim from PRD §6 ("Package.swift" block).

- [ ] **Step 2: Write `swift/build.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ICalBridge for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_DIR="../bin"
mkdir -p "$OUT_DIR"
cp .build/arm64-apple-macosx/release/ICalBridge "$OUT_DIR/ical-bridge"
chmod +x "$OUT_DIR/ical-bridge"

echo "Built: $OUT_DIR/ical-bridge"
```

- [ ] **Step 3: Make build.sh executable**

```bash
chmod +x swift/build.sh
```

- [ ] **Step 4: Write throwaway `main.swift` so the package builds**

```swift
// swift/Sources/ICalBridge/main.swift (replaced in Task 8)
print("{\"status\":\"success\",\"data\":null,\"error_code\":null,\"error_message\":null}")
```

- [ ] **Step 5: Build to confirm SwiftPM and arm64 toolchain work**

```bash
cd swift && ./build.sh && cd ..
ls -la bin/ical-bridge
```

Expected: `bin/ical-bridge` exists and is executable.

- [ ] **Step 6: Smoke-run the binary**

```bash
./bin/ical-bridge | head -c 200
echo
```

Expected: a single JSON line with `"status":"success"`.

- [ ] **Step 7: Commit**

```bash
git add swift/Package.swift swift/build.sh swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): SwiftPM scaffold, arm64 build.sh, stub main"
```

---

### Task 5: BridgeError (TDD)

**Files:**
- Create: `swift/Sources/ICalBridge/BridgeError.swift`
- Create: `swift/Tests/ICalBridgeTests/SmokeTests.swift`

- [ ] **Step 1: Write the failing tests in `swift/Tests/ICalBridgeTests/SmokeTests.swift`**

```swift
import XCTest
@testable import ICalBridge

final class BridgeErrorTests: XCTestCase {
    func testErrorCodes() {
        XCTAssertEqual(BridgeError.permissionDenied.code, "permission_denied")
        XCTAssertEqual(BridgeError.notFound("x").code, "not_found")
        XCTAssertEqual(BridgeError.invalidInput("x").code, "invalid_input")
        XCTAssertEqual(BridgeError.readOnly("x").code, "read_only")
        XCTAssertEqual(BridgeError.saveFailed("x").code, "save_failed")
        XCTAssertEqual(BridgeError.internalError("x").code, "internal")
    }

    func testErrorMessageMentionsSystemSettings() {
        XCTAssertTrue(BridgeError.permissionDenied.message.contains("System Settings"))
    }

    func testErrorMessageEmbedsDetail() {
        XCTAssertTrue(BridgeError.notFound("calendar 42").message.contains("calendar 42"))
        XCTAssertTrue(BridgeError.invalidInput("bad date").message.contains("bad date"))
    }
}
```

- [ ] **Step 2: Run tests; confirm they fail to compile (BridgeError missing)**

```bash
cd swift && swift test 2>&1 | tail -30 ; cd ..
```

Expected: compile error referencing `BridgeError`.

- [ ] **Step 3: Write `swift/Sources/ICalBridge/BridgeError.swift`**

Copy verbatim from PRD §6 ("BridgeError.swift" block).

- [ ] **Step 4: Run tests; confirm pass**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/ICalBridge/BridgeError.swift swift/Tests/ICalBridgeTests/SmokeTests.swift
git commit -m "feat(swift): BridgeError typed errors with tests"
```

---

### Task 6: OutputJSON / BridgeResult (TDD)

**Files:**
- Create: `swift/Sources/ICalBridge/OutputJSON.swift`
- Modify: `swift/Tests/ICalBridgeTests/SmokeTests.swift`

- [ ] **Step 1: Append failing encoding tests to `SmokeTests.swift`**

Add after the existing class:

```swift
final class BridgeResultTests: XCTestCase {
    func testSuccessEncodingNoErrorFields() throws {
        struct Payload: Encodable { let answer: Int }
        let result = BridgeResult.success(Payload(answer: 42))
        let data = try JSONEncoder().encode(result)
        let s = String(data: data, encoding: .utf8)!
        XCTAssertTrue(s.contains("\"status\":\"success\""))
        XCTAssertTrue(s.contains("\"answer\":42"))
        XCTAssertTrue(s.contains("\"error_code\":null"))
        XCTAssertTrue(s.contains("\"error_message\":null"))
    }

    func testErrorEncoding() throws {
        let result = BridgeResult.error(.notFound("event abc"))
        let data = try JSONEncoder().encode(result)
        let s = String(data: data, encoding: .utf8)!
        XCTAssertTrue(s.contains("\"status\":\"error\""))
        XCTAssertTrue(s.contains("\"error_code\":\"not_found\""))
        XCTAssertTrue(s.contains("event abc"))
        XCTAssertTrue(s.contains("\"data\":null"))
    }

    func testEmitWritesSingleLineToStdout() {
        // Smoke check: emit() should not throw and should produce a parseable JSON string via the
        // helper used by main.swift. The actual stdout capture happens in integration tests.
        let payload = BridgeResult<EmptyPayload>.success(EmptyPayload())
        XCTAssertNoThrow(try JSONEncoder().encode(payload))
    }
}

struct EmptyPayload: Encodable {}
```

- [ ] **Step 2: Run tests; confirm fails to compile**

```bash
cd swift && swift test 2>&1 | tail -20 ; cd ..
```

Expected: compile errors about `BridgeResult` not found.

- [ ] **Step 3: Write `swift/Sources/ICalBridge/OutputJSON.swift`**

```swift
import Foundation

struct BridgeResult<T: Encodable>: Encodable {
    let status: String
    let data: T?
    let error_code: String?
    let error_message: String?

    static func success(_ payload: T) -> BridgeResult<T> {
        BridgeResult(status: "success", data: payload, error_code: nil, error_message: nil)
    }

    static func error(_ err: BridgeError) -> BridgeResult<T> {
        BridgeResult(status: "error", data: nil, error_code: err.code, error_message: err.message)
    }
}

enum OutputJSON {
    static func emit<T: Encodable>(_ result: BridgeResult<T>) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        } catch {
            let fallback = "{\"status\":\"error\",\"data\":null,\"error_code\":\"internal\",\"error_message\":\"JSON encode failed\"}\n"
            FileHandle.standardOutput.write(fallback.data(using: .utf8)!)
        }
    }

    static func logStderr(_ msg: String) {
        FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
    }
}
```

- [ ] **Step 4: Run tests; confirm pass**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/ICalBridge/OutputJSON.swift swift/Tests/ICalBridgeTests/SmokeTests.swift
git commit -m "feat(swift): BridgeResult Encodable + OutputJSON.emit/logStderr with tests"
```

---

### Task 7: EventMapper.parseISO (TDD, no EventKit yet)

**Files:**
- Create: `swift/Sources/ICalBridge/EventMapper.swift`
- Create: `swift/Tests/ICalBridgeTests/EventMapperTests.swift`

- [ ] **Step 1: Write failing tests `swift/Tests/ICalBridgeTests/EventMapperTests.swift`**

```swift
import XCTest
@testable import ICalBridge

final class EventMapperParseISOTests: XCTestCase {
    func testParseISOWithOffset() throws {
        let d = try EventMapper.parseISO("2026-05-08T09:00:00-07:00")
        // 2026-05-08 16:00:00 UTC == 1778688000
        XCTAssertEqual(d.timeIntervalSince1970, 1778688000, accuracy: 1.0)
    }

    func testParseISOWithZ() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00Z")
        XCTAssertEqual(d.timeIntervalSince1970, 1778688000, accuracy: 1.0)
    }

    func testParseISOWithFractionalSeconds() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00.123Z")
        XCTAssertEqual(d.timeIntervalSince1970, 1778688000.123, accuracy: 0.01)
    }

    func testParseISORejectsGarbage() {
        XCTAssertThrowsError(try EventMapper.parseISO("not-a-date")) { err in
            guard case BridgeError.invalidInput(let detail) = err else {
                return XCTFail("Expected invalidInput, got \(err)")
            }
            XCTAssertTrue(detail.contains("not-a-date"))
        }
    }

    func testFormatISORoundTrip() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00Z")
        let s = EventMapper.formatISO(d)
        let d2 = try EventMapper.parseISO(s)
        XCTAssertEqual(d.timeIntervalSince1970, d2.timeIntervalSince1970, accuracy: 1.0)
    }
}
```

- [ ] **Step 2: Run tests; confirm compile failure (no EventMapper)**

```bash
cd swift && swift test 2>&1 | tail -20 ; cd ..
```

Expected: compile error referencing `EventMapper`.

- [ ] **Step 3: Write `swift/Sources/ICalBridge/EventMapper.swift`**

```swift
import Foundation

enum EventMapper {
    private static let formatters: [ISO8601DateFormatter] = [
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }(),
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
    ]

    private static let outputFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) throws -> Date {
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        throw BridgeError.invalidInput("Cannot parse date: \(s)")
    }

    static func formatISO(_ d: Date) -> String {
        outputFormatter.string(from: d)
    }
}
```

- [ ] **Step 4: Run tests; confirm pass**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/ICalBridge/EventMapper.swift swift/Tests/ICalBridgeTests/EventMapperTests.swift
git commit -m "feat(swift): EventMapper.parseISO/formatISO with TDD coverage"
```

---

### Task 8: main.swift with seven stub subcommands

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace placeholder)

- [ ] **Step 1: Replace `swift/Sources/ICalBridge/main.swift` with the full ArgumentParser CLI shape**

```swift
import Foundation
import ArgumentParser

struct ICalBridge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ical-bridge",
        abstract: "iCal Integration EventKit bridge",
        subcommands: [
            ListCalendars.self,
            GetEvents.self,
            SearchEvents.self,
            CreateEvent.self,
            UpdateEvent.self,
            DeleteEvent.self,
            GetAvailability.self
        ]
    )
}

struct StubCalendar: Encodable {
    let id: String
    let title: String
    let color: String
    let type: String
    let account: String
    let is_default: Bool
}

struct StubCalendarsPayload: Encodable {
    let calendars: [StubCalendar]
    let count: Int
}

struct StubEvent: Encodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let all_day: Bool
    let calendar_id: String
    let calendar_title: String
    let location: String?
    let notes: String?
    let url: String?
    let is_recurring: Bool
    let recurrence_rule: String?
}

struct StubEventsPayload: Encodable {
    let events: [StubEvent]
    let count: Int
    let truncated: Bool
}

struct StubEventWrapper: Encodable {
    let event: StubEvent
}

struct StubDeletePayload: Encodable {
    let deleted: Bool
    let id: String
}

struct StubAvailabilityBlock: Encodable {
    let start: String
    let end: String
    let title: String?
}

struct StubAvailabilityFreeBlock: Encodable {
    let start: String
    let end: String
}

struct StubAvailabilityPayload: Encodable {
    let start: String
    let end: String
    let busy: [StubAvailabilityBlock]
    let free: [StubAvailabilityFreeBlock]
}

extension ICalBridge {
    struct ListCalendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list-calendars")
        @Option var type: String = "event"
        func run() throws {
            let payload = StubCalendarsPayload(calendars: [], count: 0)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct GetEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-events")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Flag(name: .customLong("no-all-day")) var noAllDay: Bool = false
        func run() throws {
            let payload = StubEventsPayload(events: [], count: 0, truncated: false)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct SearchEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search-events")
        @Option var query: String
        @Option var start: String?
        @Option var end: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        func run() throws {
            let payload = StubEventsPayload(events: [], count: 0, truncated: false)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct CreateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create-event")
        @Option var title: String
        @Option var start: String
        @Option var end: String
        @Flag(name: .customLong("all-day")) var allDay: Bool = false
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?
        func run() throws {
            let stub = StubEvent(
                id: "stub-id",
                title: title,
                start: start,
                end: end,
                all_day: allDay,
                calendar_id: calendarId ?? "stub-cal",
                calendar_title: "Stub",
                location: location,
                notes: notes,
                url: url,
                is_recurring: false,
                recurrence_rule: nil
            )
            OutputJSON.emit(BridgeResult.success(StubEventWrapper(event: stub)))
        }
    }

    struct UpdateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "update-event")
        @Option var id: String
        @Option var title: String?
        @Option var start: String?
        @Option var end: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        func run() throws {
            let stub = StubEvent(
                id: id,
                title: title ?? "stub",
                start: start ?? "2026-01-01T00:00:00Z",
                end: end ?? "2026-01-01T01:00:00Z",
                all_day: false,
                calendar_id: calendarId ?? "stub-cal",
                calendar_title: "Stub",
                location: location,
                notes: notes,
                url: url,
                is_recurring: false,
                recurrence_rule: nil
            )
            OutputJSON.emit(BridgeResult.success(StubEventWrapper(event: stub)))
        }
    }

    struct DeleteEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete-event")
        @Option var id: String
        @Option var span: String = "this_only"
        func run() throws {
            OutputJSON.emit(BridgeResult.success(StubDeletePayload(deleted: true, id: id)))
        }
    }

    struct GetAvailability: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-availability")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-ids")) var calendarIds: String?
        @Option var granularity: Int = 30
        func run() throws {
            let payload = StubAvailabilityPayload(start: start, end: end, busy: [], free: [])
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }
}

ICalBridge.main()
```

- [ ] **Step 2: Build**

```bash
cd swift && ./build.sh && cd ..
```

Expected: build succeeds, `bin/ical-bridge` updated.

- [ ] **Step 3: Smoke each subcommand**

```bash
./bin/ical-bridge list-calendars
./bin/ical-bridge get-events --start "2026-05-01T00:00:00Z" --end "2026-06-01T00:00:00Z"
./bin/ical-bridge search-events --query "lunch"
./bin/ical-bridge create-event --title "T" --start "2026-05-01T00:00:00Z" --end "2026-05-01T01:00:00Z"
./bin/ical-bridge update-event --id "x"
./bin/ical-bridge delete-event --id "x"
./bin/ical-bridge get-availability --start "2026-05-01T00:00:00Z" --end "2026-05-02T00:00:00Z"
```

Expected: each prints exactly one JSON line on stdout starting with `{"status":"success"`.

- [ ] **Step 4: Verify stdout is single-line JSON for one command**

```bash
./bin/ical-bridge list-calendars | wc -l
./bin/ical-bridge list-calendars | head -1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'])"
```

Expected: `1` and `success`.

- [ ] **Step 5: Run swift tests**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): ArgumentParser CLI with 7 stub subcommands emitting BridgeResult JSON"
```

---

## Phase 2 — Node MCP Server

### Task 9: src/types.ts (shared TypeScript types)

**Files:**
- Create: `src/types.ts`

- [ ] **Step 1: Write `src/types.ts`**

```ts
export type CalendarType =
  | 'local'
  | 'calDAV'
  | 'exchange'
  | 'subscription'
  | 'birthday';

export interface CalendarSummary {
  id: string;
  title: string;
  color: string;
  type: CalendarType;
  account: string;
  is_default: boolean;
}

export interface EventSummary {
  id: string;
  title: string;
  start: string;
  end: string;
  all_day: boolean;
  calendar_id: string;
  calendar_title: string;
  location: string | null;
  notes: string | null;
  url: string | null;
  is_recurring: boolean;
  recurrence_rule: string | null;
}

export interface BusyBlock {
  start: string;
  end: string;
  title?: string | null;
}

export interface FreeBlock {
  start: string;
  end: string;
}

export interface AvailabilityPayload {
  start: string;
  end: string;
  busy: BusyBlock[];
  free: FreeBlock[];
}

export type BridgeErrorCode =
  | 'permission_denied'
  | 'not_found'
  | 'invalid_input'
  | 'read_only'
  | 'save_failed'
  | 'internal';

export interface BridgeResultSuccess<T> {
  status: 'success';
  data: T;
  error_code: null;
  error_message: null;
}

export interface BridgeResultError {
  status: 'error';
  data: null;
  error_code: BridgeErrorCode;
  error_message: string;
}

export type BridgeResult<T> = BridgeResultSuccess<T> | BridgeResultError;
```

- [ ] **Step 2: Build to verify types compile**

```bash
pnpm build:server
```

Expected: clean build (no errors), `server/types.js` produced.

- [ ] **Step 3: Commit**

```bash
git add src/types.ts
git commit -m "feat(node): shared TypeScript types for bridge IPC"
```

---

### Task 10: src/schemas.ts (Zod + JSON Schemas for all 7 tools)

**Files:**
- Create: `src/schemas.ts`

- [ ] **Step 1: Write `src/schemas.ts`**

```ts
import { z } from 'zod';

const isoString = z.string().min(1, 'must be a non-empty ISO 8601 string');

export const ListCalendarsInput = z.object({
  type_filter: z.enum(['all', 'event', 'reminder']).optional(),
}).strict();

export const GetEventsInput = z.object({
  start: isoString,
  end: isoString,
  calendar_id: z.string().min(1).optional(),
  include_all_day: z.boolean().optional(),
}).strict();

export const SearchEventsInput = z.object({
  query: z.string().min(1),
  start: isoString.optional(),
  end: isoString.optional(),
  calendar_id: z.string().min(1).optional(),
}).strict();

export const CreateEventInput = z.object({
  title: z.string().min(1),
  start: isoString,
  end: isoString,
  all_day: z.boolean().optional(),
  calendar_id: z.string().min(1).optional(),
  location: z.string().optional(),
  notes: z.string().optional(),
  url: z.string().optional(),
}).strict();

export const UpdateEventInput = z.object({
  id: z.string().min(1),
  title: z.string().optional(),
  start: isoString.optional(),
  end: isoString.optional(),
  location: z.string().optional(),
  notes: z.string().optional(),
  url: z.string().optional(),
  calendar_id: z.string().min(1).optional(),
}).strict();

export const DeleteEventInput = z.object({
  id: z.string().min(1),
  span: z.enum(['this_only', 'all']).optional(),
}).strict();

export const GetAvailabilityInput = z.object({
  start: isoString,
  end: isoString,
  calendar_ids: z.array(z.string().min(1)).optional(),
  granularity_minutes: z.number().int().min(15).max(120).optional(),
}).strict();

export type ListCalendarsArgs = z.infer<typeof ListCalendarsInput>;
export type GetEventsArgs = z.infer<typeof GetEventsInput>;
export type SearchEventsArgs = z.infer<typeof SearchEventsInput>;
export type CreateEventArgs = z.infer<typeof CreateEventInput>;
export type UpdateEventArgs = z.infer<typeof UpdateEventInput>;
export type DeleteEventArgs = z.infer<typeof DeleteEventInput>;
export type GetAvailabilityArgs = z.infer<typeof GetAvailabilityInput>;

export const toolJsonSchemas = {
  list_calendars: {
    type: 'object',
    properties: {
      type_filter: {
        type: 'string',
        enum: ['all', 'event', 'reminder'],
        default: 'event',
        description: "Which calendar types to include. Use 'event' for standard calendars.",
      },
    },
    additionalProperties: false,
  },
  get_events: {
    type: 'object',
    properties: {
      start: { type: 'string', description: "ISO 8601 start datetime, e.g. '2026-05-01T00:00:00-07:00'." },
      end: { type: 'string', description: 'ISO 8601 end datetime.' },
      calendar_id: { type: 'string', description: 'Optional. Restrict to a specific calendar by its id from list_calendars.' },
      include_all_day: { type: 'boolean', default: true, description: 'Whether to include all-day events.' },
    },
    required: ['start', 'end'],
    additionalProperties: false,
  },
  search_events: {
    type: 'object',
    properties: {
      query: { type: 'string', description: 'Search term to match against event title, location, and notes.' },
      start: { type: 'string', description: 'ISO 8601 start of the search window. Defaults to 90 days ago.' },
      end: { type: 'string', description: 'ISO 8601 end of the search window. Defaults to 1 year from now.' },
      calendar_id: { type: 'string', description: 'Optional. Restrict search to one calendar.' },
    },
    required: ['query'],
    additionalProperties: false,
  },
  create_event: {
    type: 'object',
    properties: {
      title: { type: 'string', description: 'Event title.' },
      start: { type: 'string', description: 'ISO 8601 start datetime.' },
      end: { type: 'string', description: 'ISO 8601 end datetime. Must be after start.' },
      all_day: { type: 'boolean', default: false, description: 'If true, start and end are treated as dates, not datetimes.' },
      calendar_id: { type: 'string', description: "Optional. Target calendar id. Defaults to the user's default calendar." },
      location: { type: 'string', description: 'Optional. Location string.' },
      notes: { type: 'string', description: 'Optional. Free-text notes body.' },
      url: { type: 'string', description: 'Optional. URL associated with the event.' },
    },
    required: ['title', 'start', 'end'],
    additionalProperties: false,
  },
  update_event: {
    type: 'object',
    properties: {
      id: { type: 'string', description: 'Event id from get_events or create_event.' },
      title: { type: 'string' },
      start: { type: 'string', description: 'ISO 8601 datetime.' },
      end: { type: 'string', description: 'ISO 8601 datetime.' },
      location: { type: 'string' },
      notes: { type: 'string' },
      url: { type: 'string' },
      calendar_id: { type: 'string', description: 'Move the event to a different calendar.' },
    },
    required: ['id'],
    additionalProperties: false,
  },
  delete_event: {
    type: 'object',
    properties: {
      id: { type: 'string', description: 'Event id from get_events or create_event.' },
      span: {
        type: 'string',
        enum: ['this_only', 'all'],
        default: 'this_only',
        description: 'For recurring events: delete only this occurrence or the entire series.',
      },
    },
    required: ['id'],
    additionalProperties: false,
  },
  get_availability: {
    type: 'object',
    properties: {
      start: { type: 'string', description: 'ISO 8601 start of the range.' },
      end: { type: 'string', description: 'ISO 8601 end of the range.' },
      calendar_ids: {
        type: 'array',
        items: { type: 'string' },
        description: 'Optional. Restrict to specific calendar ids. Defaults to all event calendars.',
      },
      granularity_minutes: {
        type: 'number',
        default: 30,
        minimum: 15,
        maximum: 120,
        description: 'Minimum block size in minutes. Adjacent events closer than this are merged.',
      },
    },
    required: ['start', 'end'],
    additionalProperties: false,
  },
} as const;

export const toolDescriptions = {
  list_calendars: 'List all calendars visible in Calendar.app (iCloud, Google, Exchange, local).',
  get_events: 'Fetch events within a date range, optionally filtered by calendar.',
  search_events: 'Search events by keyword across a configurable time window.',
  create_event: 'Create a new calendar event.',
  update_event: 'Update fields of an existing event by its id.',
  delete_event: 'Delete an event by its id.',
  get_availability: 'Return free and busy blocks for a date range to support scheduling.',
} as const;

export type ToolName = keyof typeof toolJsonSchemas;
```

- [ ] **Step 2: Build to verify schemas compile**

```bash
pnpm build:server
```

Expected: clean build, `server/schemas.js` produced.

- [ ] **Step 3: Verify no em dashes**

```bash
grep -nP '\x{2014}' src/schemas.ts && echo FAIL || echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add src/schemas.ts
git commit -m "feat(node): Zod input validators + JSON Schemas for 7 tools"
```

---

### Task 11: Stub binary fixtures

**Files:**
- Create: `src/__tests__/fixtures/stub-calendars.sh`
- Create: `src/__tests__/fixtures/stub-events.sh`
- Create: `src/__tests__/fixtures/stub-create.sh`
- Create: `src/__tests__/fixtures/stub-error.sh`
- Create: `src/__tests__/fixtures/stub-crash.sh`

- [ ] **Step 1: Create `stub-calendars.sh`**

```bash
#!/usr/bin/env bash
cat <<'JSON'
{"status":"success","data":{"calendars":[{"id":"cal-1","title":"Personal","color":"#FF2D55","type":"calDAV","account":"iCloud","is_default":true}],"count":1},"error_code":null,"error_message":null}
JSON
```

- [ ] **Step 2: Create `stub-events.sh`**

```bash
#!/usr/bin/env bash
cat <<'JSON'
{"status":"success","data":{"events":[{"id":"ev-1","title":"Standup","start":"2026-05-08T09:00:00-07:00","end":"2026-05-08T09:30:00-07:00","all_day":false,"calendar_id":"cal-1","calendar_title":"Work","location":null,"notes":null,"url":null,"is_recurring":false,"recurrence_rule":null}],"count":1,"truncated":false},"error_code":null,"error_message":null}
JSON
```

- [ ] **Step 3: Create `stub-create.sh`**

```bash
#!/usr/bin/env bash
cat <<'JSON'
{"status":"success","data":{"event":{"id":"new-ev-1","title":"Dentist","start":"2026-05-20T14:00:00-07:00","end":"2026-05-20T15:00:00-07:00","all_day":false,"calendar_id":"cal-1","calendar_title":"Personal","location":"123 Main St","notes":null,"url":null,"is_recurring":false,"recurrence_rule":null}},"error_code":null,"error_message":null}
JSON
```

- [ ] **Step 4: Create `stub-error.sh`**

```bash
#!/usr/bin/env bash
cat <<'JSON'
{"status":"error","data":null,"error_code":"permission_denied","error_message":"Calendar access denied. Grant access in System Settings, Privacy and Security, Calendars."}
JSON
```

- [ ] **Step 5: Create `stub-crash.sh`**

```bash
#!/usr/bin/env bash
echo "this is not json"
exit 1
```

- [ ] **Step 6: chmod**

```bash
chmod +x src/__tests__/fixtures/*.sh
```

- [ ] **Step 7: Verify each stub returns the expected shape**

```bash
src/__tests__/fixtures/stub-calendars.sh | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['count'])"
src/__tests__/fixtures/stub-error.sh | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['error_code'])"
```

Expected: `1` and `permission_denied`.

- [ ] **Step 8: Commit**

```bash
git add src/__tests__/fixtures
git commit -m "test(node): stub bash fixtures for bridge tests"
```

---

### Task 12: src/bridge.ts (TDD)

**Files:**
- Create: `src/__tests__/bridge.test.ts`
- Create: `src/bridge.ts`

- [ ] **Step 1: Write the failing test file `src/__tests__/bridge.test.ts`**

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = resolve(here, 'fixtures');

import { callBridge, BridgeOutcome } from '../bridge.js';

function withBin(p: string, fn: () => Promise<void>) {
  return async () => {
    const prev = process.env.ICAL_BRIDGE_BIN;
    process.env.ICAL_BRIDGE_BIN = p;
    try {
      await fn();
    } finally {
      if (prev === undefined) delete process.env.ICAL_BRIDGE_BIN;
      else process.env.ICAL_BRIDGE_BIN = prev;
    }
  };
}

describe('callBridge', () => {
  it('returns parsed success payload from list-calendars', withBin(
    resolve(fixtures, 'stub-calendars.sh'),
    async () => {
      const out: BridgeOutcome = await callBridge(['list-calendars']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).calendars).toHaveLength(1);
      expect((out.data as any).calendars[0].title).toBe('Personal');
    }
  ));

  it('returns parsed events payload', withBin(
    resolve(fixtures, 'stub-events.sh'),
    async () => {
      const out = await callBridge(['get-events', '--start', 'a', '--end', 'b']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).events[0].id).toBe('ev-1');
    }
  ));

  it('returns parsed create payload', withBin(
    resolve(fixtures, 'stub-create.sh'),
    async () => {
      const out = await callBridge(['create-event']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).event.id).toBe('new-ev-1');
    }
  ));

  it('surfaces permission_denied as a structured error', withBin(
    resolve(fixtures, 'stub-error.sh'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_code).toBe('permission_denied');
      expect(out.error_message).toMatch(/System Settings/);
    }
  ));

  it('surfaces non-JSON stdout as an internal error', withBin(
    resolve(fixtures, 'stub-crash.sh'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_code).toBe('internal');
      expect(out.error_message.toLowerCase()).toMatch(/binary|parse|json/);
    }
  ));

  it('errors clearly when ICAL_BRIDGE_BIN is missing', withBin(
    resolve(fixtures, 'does-not-exist.sh'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_message.toLowerCase()).toMatch(/not found|missing/);
    }
  ));

  it('errors when ICAL_BRIDGE_BIN env var is unset', async () => {
    const prev = process.env.ICAL_BRIDGE_BIN;
    delete process.env.ICAL_BRIDGE_BIN;
    try {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_message.toLowerCase()).toMatch(/ical_bridge_bin/);
    } finally {
      if (prev !== undefined) process.env.ICAL_BRIDGE_BIN = prev;
    }
  });
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pnpm test 2>&1 | tail -25
```

Expected: failures referencing missing `bridge.ts` / `callBridge`.

- [ ] **Step 3: Implement `src/bridge.ts`**

```ts
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import type { BridgeResult, BridgeErrorCode } from './types.js';

export type BridgeOutcome =
  | { status: 'success'; data: unknown }
  | { status: 'error'; error_code: BridgeErrorCode | 'internal'; error_message: string };

interface CallOptions {
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 10_000;

export async function callBridge(args: string[], opts: CallOptions = {}): Promise<BridgeOutcome> {
  const bin = process.env.ICAL_BRIDGE_BIN;
  if (!bin) {
    return {
      status: 'error',
      error_code: 'internal',
      error_message: 'ICAL_BRIDGE_BIN environment variable is not set.',
    };
  }
  if (!existsSync(bin)) {
    return {
      status: 'error',
      error_code: 'internal',
      error_message: `Bridge binary not found at ${bin}.`,
    };
  }

  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  return new Promise<BridgeOutcome>((resolveResult) => {
    const child = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';
    let settled = false;

    const settle = (out: BridgeOutcome) => {
      if (settled) return;
      settled = true;
      resolveResult(out);
    };

    const killTimer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch { /* noop */ }
      settle({
        status: 'error',
        error_code: 'internal',
        error_message: `Bridge binary timed out after ${timeoutMs}ms.`,
      });
    }, timeoutMs + 5_000);

    child.stdout.on('data', (chunk) => { stdout += chunk.toString('utf8'); });
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString('utf8');
      stderr += text;
      process.stderr.write(text);
    });

    child.on('error', (err) => {
      clearTimeout(killTimer);
      settle({
        status: 'error',
        error_code: 'internal',
        error_message: `Bridge binary failed to spawn: ${err.message}`,
      });
    });

    child.on('close', (code) => {
      clearTimeout(killTimer);
      let parsed: BridgeResult<unknown> | null = null;
      try {
        parsed = JSON.parse(stdout) as BridgeResult<unknown>;
      } catch {
        settle({
          status: 'error',
          error_code: 'internal',
          error_message: `Bridge binary returned non-JSON output (exit ${code}). stderr: ${stderr.trim().slice(0, 500)}`,
        });
        return;
      }
      if (parsed && parsed.status === 'success') {
        settle({ status: 'success', data: parsed.data });
      } else if (parsed && parsed.status === 'error') {
        settle({
          status: 'error',
          error_code: parsed.error_code ?? 'internal',
          error_message: parsed.error_message ?? 'Unknown bridge error.',
        });
      } else {
        settle({
          status: 'error',
          error_code: 'internal',
          error_message: `Bridge binary returned malformed result (exit ${code}).`,
        });
      }
    });
  });
}
```

- [ ] **Step 4: Run tests until all pass**

```bash
pnpm test 2>&1 | tail -25
```

Expected: 7 passing tests.

- [ ] **Step 5: Commit**

```bash
git add src/bridge.ts src/__tests__/bridge.test.ts
git commit -m "feat(node): bridge.ts spawn+parse with TDD coverage of all error paths"
```

---

### Task 13: src/index.ts (MCP server entry, ListTools + CallTool wiring)

**Files:**
- Create: `src/index.ts`

- [ ] **Step 1: Write `src/index.ts`**

```ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';

import {
  CreateEventInput,
  DeleteEventInput,
  GetAvailabilityInput,
  GetEventsInput,
  ListCalendarsInput,
  SearchEventsInput,
  UpdateEventInput,
  toolDescriptions,
  toolJsonSchemas,
  type ToolName,
} from './schemas.js';
import { callBridge, type BridgeOutcome } from './bridge.js';

interface ToolHandler {
  name: ToolName;
  description: string;
  inputSchema: (typeof toolJsonSchemas)[ToolName];
  zod: z.ZodTypeAny;
  build: (args: Record<string, unknown>) => string[];
  timeoutMs?: number;
}

function flag(name: string, value: unknown): string[] {
  if (value === undefined || value === null) return [];
  return [`--${name}`, String(value)];
}

function bareFlag(name: string, on: unknown): string[] {
  return on === true ? [`--${name}`] : [];
}

const handlers: Record<ToolName, ToolHandler> = {
  list_calendars: {
    name: 'list_calendars',
    description: toolDescriptions.list_calendars,
    inputSchema: toolJsonSchemas.list_calendars,
    zod: ListCalendarsInput,
    build: (a) => ['list-calendars', ...flag('type', a.type_filter ?? 'event')],
  },
  get_events: {
    name: 'get_events',
    description: toolDescriptions.get_events,
    inputSchema: toolJsonSchemas.get_events,
    zod: GetEventsInput,
    build: (a) => [
      'get-events',
      ...flag('start', a.start),
      ...flag('end', a.end),
      ...flag('calendar-id', a.calendar_id),
      ...bareFlag('no-all-day', a.include_all_day === false),
    ],
  },
  search_events: {
    name: 'search_events',
    description: toolDescriptions.search_events,
    inputSchema: toolJsonSchemas.search_events,
    zod: SearchEventsInput,
    build: (a) => [
      'search-events',
      ...flag('query', a.query),
      ...flag('start', a.start),
      ...flag('end', a.end),
      ...flag('calendar-id', a.calendar_id),
    ],
  },
  create_event: {
    name: 'create_event',
    description: toolDescriptions.create_event,
    inputSchema: toolJsonSchemas.create_event,
    zod: CreateEventInput,
    build: (a) => [
      'create-event',
      ...flag('title', a.title),
      ...flag('start', a.start),
      ...flag('end', a.end),
      ...bareFlag('all-day', a.all_day === true),
      ...flag('calendar-id', a.calendar_id),
      ...flag('location', a.location),
      ...flag('notes', a.notes),
      ...flag('url', a.url),
    ],
    timeoutMs: 15_000,
  },
  update_event: {
    name: 'update_event',
    description: toolDescriptions.update_event,
    inputSchema: toolJsonSchemas.update_event,
    zod: UpdateEventInput,
    build: (a) => [
      'update-event',
      ...flag('id', a.id),
      ...flag('title', a.title),
      ...flag('start', a.start),
      ...flag('end', a.end),
      ...flag('location', a.location),
      ...flag('notes', a.notes),
      ...flag('url', a.url),
      ...flag('calendar-id', a.calendar_id),
    ],
    timeoutMs: 15_000,
  },
  delete_event: {
    name: 'delete_event',
    description: toolDescriptions.delete_event,
    inputSchema: toolJsonSchemas.delete_event,
    zod: DeleteEventInput,
    build: (a) => [
      'delete-event',
      ...flag('id', a.id),
      ...flag('span', a.span ?? 'this_only'),
    ],
    timeoutMs: 15_000,
  },
  get_availability: {
    name: 'get_availability',
    description: toolDescriptions.get_availability,
    inputSchema: toolJsonSchemas.get_availability,
    zod: GetAvailabilityInput,
    build: (a) => [
      'get-availability',
      ...flag('start', a.start),
      ...flag('end', a.end),
      ...flag('calendar-ids', Array.isArray(a.calendar_ids) ? (a.calendar_ids as string[]).join(',') : undefined),
      ...flag('granularity', a.granularity_minutes ?? 30),
    ],
  },
};

function outcomeToMcp(outcome: BridgeOutcome) {
  if (outcome.status === 'success') {
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(outcome.data) }],
    };
  }
  return {
    content: [{ type: 'text' as const, text: outcome.error_message }],
    isError: true as const,
  };
}

async function main() {
  const server = new Server(
    { name: 'ical-integration', version: '1.0.0' },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: (Object.values(handlers) as ToolHandler[]).map((h) => ({
      name: h.name,
      description: h.description,
      inputSchema: h.inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const name = req.params.name as ToolName;
    const handler = handlers[name];
    if (!handler) {
      return {
        content: [{ type: 'text' as const, text: `Unknown tool: ${String(req.params.name)}` }],
        isError: true as const,
      };
    }
    const parsed = handler.zod.safeParse(req.params.arguments ?? {});
    if (!parsed.success) {
      return {
        content: [{ type: 'text' as const, text: `Invalid arguments for ${handler.name}: ${parsed.error.message}` }],
        isError: true as const,
      };
    }
    const args = handler.build(parsed.data as Record<string, unknown>);
    const outcome = await callBridge(args, { timeoutMs: handler.timeoutMs });
    return outcomeToMcp(outcome);
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  process.stderr.write(`ical-integration server crashed: ${err?.stack ?? err}\n`);
  process.exit(1);
});
```

- [ ] **Step 2: Build**

```bash
pnpm build:server
```

Expected: clean compile, `server/index.js`, `server/bridge.js`, `server/schemas.js`, `server/types.js` all present.

- [ ] **Step 3: Run all unit tests**

```bash
pnpm test 2>&1 | tail -10
```

Expected: all bridge tests still pass.

- [ ] **Step 4: Smoke-test the compiled server end-to-end against a stub binary**

```bash
ICAL_BRIDGE_BIN="$PWD/src/__tests__/fixtures/stub-calendars.sh" \
  node -e "
    import('@modelcontextprotocol/sdk/client/index.js').then(async ({Client}) => {
      const {StdioClientTransport} = await import('@modelcontextprotocol/sdk/client/stdio.js');
      const t = new StdioClientTransport({command:'node',args:['server/index.js'],env:{...process.env}});
      const c = new Client({name:'t',version:'0'},{capabilities:{}});
      await c.connect(t);
      const tools = await c.listTools();
      console.log('TOOL_COUNT', tools.tools.length);
      const r = await c.callTool({name:'list_calendars',arguments:{}});
      console.log('RESULT', JSON.stringify(r));
      await c.close();
    }).catch(e => { console.error(e); process.exit(1); });
  "
```

Expected: `TOOL_COUNT 7`; `RESULT {"content":[{"type":"text","text":"{\"calendars\":[{\"id\":\"cal-1\",...}]}"}]}` (text payload contains the stub calendar JSON; no `isError` field set).

- [ ] **Step 5: Commit**

```bash
git add src/index.ts
git commit -m "feat(node): MCP server entry registering 7 tools and proxying to bridge"
```

---

### Task 14: Full local build verification

**Files:** none modified.

- [ ] **Step 1: Clean and rebuild**

```bash
pnpm clean
pnpm install
pnpm build
```

Expected: `bin/ical-bridge` and `server/index.js` both exist after the run.

- [ ] **Step 2: Run all unit tests**

```bash
pnpm test
cd swift && swift test ; cd ..
```

Expected: green on both.

- [ ] **Step 3: Manual stdio smoke against the real (stub-output) Swift binary**

```bash
ICAL_BRIDGE_BIN="$PWD/bin/ical-bridge" \
  node -e "
    import('@modelcontextprotocol/sdk/client/index.js').then(async ({Client}) => {
      const {StdioClientTransport} = await import('@modelcontextprotocol/sdk/client/stdio.js');
      const t = new StdioClientTransport({command:'node',args:['server/index.js'],env:{...process.env}});
      const c = new Client({name:'t',version:'0'},{capabilities:{}});
      await c.connect(t);
      const r = await c.callTool({name:'list_calendars',arguments:{}});
      console.log(JSON.stringify(r));
      await c.close();
    }).catch(e=>{console.error(e);process.exit(1);});
  "
```

Expected: a JSON line containing `"calendars":[]` (the stub returns an empty array prior to Phase 4).

- [ ] **Step 4: Commit nothing (no source changes)**

If the `pnpm-lock.yaml` updated, commit it: `git add pnpm-lock.yaml && git commit -m "chore: refresh lockfile"`.

---

## Phase 3 — First Bundle Install

### Task 15: scripts/package.sh

**Files:**
- Create: `scripts/package.sh`

- [ ] **Step 1: Write `scripts/package.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Cleaning previous .mcpb"
rm -f ./*.mcpb

echo "==> Backing up dev node_modules"
if [ -d node_modules ]; then
  rm -rf node_modules.dev
  mv node_modules node_modules.dev
fi

restore_dev_modules() {
  if [ -d node_modules.dev ]; then
    rm -rf node_modules
    mv node_modules.dev node_modules
  fi
}
trap restore_dev_modules EXIT

echo "==> Installing prod-only flat node_modules (hoisted linker)"
pnpm install --prod --shamefully-hoist --no-frozen-lockfile

echo "==> Packing .mcpb via @anthropic-ai/mcpb"
npx -y @anthropic-ai/mcpb pack

echo "==> .mcpb produced:"
ls -1 ./*.mcpb
```

- [ ] **Step 2: chmod**

```bash
chmod +x scripts/package.sh
```

- [ ] **Step 3: Run**

```bash
pnpm package
```

Expected: a single `ical-integration-1.0.0.mcpb` (or similarly named) file appears in the repo root, dev `node_modules/` is restored.

- [ ] **Step 4: Inspect the bundle**

```bash
unzip -l ./ical-integration-*.mcpb | head -40
```

Expected listing must include: `manifest.json`, `server/index.js`, `bin/ical-bridge`, `node_modules/@modelcontextprotocol/...`, `node_modules/zod/...`. It must **not** include: `src/`, `swift/`, `tsconfig.json`, `vitest.config.ts`, `pnpm-lock.yaml`, `ical-integration-prd.md`.

- [ ] **Step 5: Verify dev node_modules survived**

```bash
ls node_modules/.pnpm 2>/dev/null && echo "dev node_modules restored" || echo "FAIL: dev node_modules missing"
```

Expected: `dev node_modules restored`.

- [ ] **Step 6: Commit**

```bash
git add scripts/package.sh
git commit -m "build: scripts/package.sh produces .mcpb with flat prod node_modules"
```

---

### Task 16: Manual install in Claude Desktop (stub end-to-end)

**Files:** none.

- [ ] **Step 1: Install the produced `.mcpb`**

In Claude Desktop, open Settings → Extensions → Advanced settings → Extension Developer → "Install Extension..." and pick `./ical-integration-*.mcpb`.

- [ ] **Step 2: In a new chat, verify the seven tools appear**

Ask: "What MCP tools do you have available?" and confirm all seven names are present.

- [ ] **Step 3: Smoke-call `list_calendars`**

Ask Claude to call `list_calendars`. The response will be the stub `{"calendars":[]}` (Phase 4 has not been done yet). The point of this task is verifying the bundle wiring, not real data.

- [ ] **Step 4: If installation fails, capture logs and stop**

If anything fails (manifest rejected, server crash, binary not found), capture the Claude Desktop extension log and escalate as `BLOCKED`. Do not proceed to Phase 4 with a broken bundle.

- [ ] **Step 5: No commit** — this is a verification step.

---

## Phase 4 — Real EventKit Reads

### Task 17: CalendarStore (authorization + helpers)

**Files:**
- Create: `swift/Sources/ICalBridge/CalendarStore.swift`

- [ ] **Step 1: Write `CalendarStore.swift`**

```swift
import Foundation
import EventKit

final class CalendarStore {
    let store = EKEventStore()

    func ensureAuthorization() throws {
        let status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return
        case .authorized:
            return
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { ok, _ in
                    granted = ok
                    sem.signal()
                }
            } else {
                store.requestAccess(to: .event) { ok, _ in
                    granted = ok
                    sem.signal()
                }
            }
            sem.wait()
            if !granted {
                throw BridgeError.permissionDenied
            }
        case .denied, .restricted, .writeOnly:
            throw BridgeError.permissionDenied
        @unknown default:
            throw BridgeError.permissionDenied
        }
    }

    func eventCalendars(typeFilter: String) -> [EKCalendar] {
        let entity: EKEntityType = (typeFilter == "reminder") ? .reminder : .event
        let cals = store.calendars(for: entity)
        if typeFilter == "all" {
            return store.calendars(for: .event) + store.calendars(for: .reminder)
        }
        return cals
    }

    func calendar(byId id: String) -> EKCalendar? {
        if let c = store.calendar(withIdentifier: id) { return c }
        return store.calendars(for: .event).first(where: { $0.calendarIdentifier == id })
    }

    func event(byId id: String) -> EKEvent? {
        if let ev = store.event(withIdentifier: id) { return ev }
        if let item = store.calendarItem(withIdentifier: id) as? EKEvent { return item }
        return nil
    }

    static func typeString(_ t: EKCalendarType) -> String {
        switch t {
        case .local: return "local"
        case .calDAV: return "calDAV"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "local"
        }
    }

    static func hexColor(from cgColor: CGColor) -> String {
        guard let comps = cgColor.components, comps.count >= 3 else { return "#000000" }
        let r = Int((comps[0] * 255.0).rounded())
        let g = Int((comps[1] * 255.0).rounded())
        let b = Int((comps[2] * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

- [ ] **Step 2: Add Swift unit test for `typeString` mapping**

Append to `swift/Tests/ICalBridgeTests/SmokeTests.swift`:

```swift
import EventKit
final class CalendarStoreTypeStringTests: XCTestCase {
    func testTypeStringMappings() {
        XCTAssertEqual(CalendarStore.typeString(.local), "local")
        XCTAssertEqual(CalendarStore.typeString(.calDAV), "calDAV")
        XCTAssertEqual(CalendarStore.typeString(.exchange), "exchange")
        XCTAssertEqual(CalendarStore.typeString(.subscription), "subscription")
        XCTAssertEqual(CalendarStore.typeString(.birthday), "birthday")
    }
}
```

- [ ] **Step 3: Run swift tests**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: pass.

- [ ] **Step 4: Build the binary**

```bash
cd swift && ./build.sh && cd ..
```

Expected: success.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/ICalBridge/CalendarStore.swift swift/Tests/ICalBridgeTests/SmokeTests.swift
git commit -m "feat(swift): CalendarStore with auth flow + EKCalendarType mapping"
```

---

### Task 18: list-calendars implementation

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `ListCalendars` body)
- Modify: `swift/Sources/ICalBridge/EventMapper.swift` (add `mapCalendar`)

- [ ] **Step 1: Add `mapCalendar` to `EventMapper.swift`**

First add `import EventKit` directly after the existing `import Foundation` line at the top of the file. Then append the following at the bottom of the file:

```swift
struct CalendarPayload: Encodable {
    let id: String
    let title: String
    let color: String
    let type: String
    let account: String
    let is_default: Bool
}

struct CalendarsPayload: Encodable {
    let calendars: [CalendarPayload]
    let count: Int
}

extension EventMapper {
    static func mapCalendar(_ cal: EKCalendar, defaultId: String?) -> CalendarPayload {
        CalendarPayload(
            id: cal.calendarIdentifier,
            title: cal.title,
            color: CalendarStore.hexColor(from: cal.cgColor),
            type: CalendarStore.typeString(cal.type),
            account: cal.source.title,
            is_default: cal.calendarIdentifier == defaultId
        )
    }
}
```

- [ ] **Step 2: Replace `ListCalendars.run` in `main.swift`**

```swift
    struct ListCalendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list-calendars")
        @Option var type: String = "event"
        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let cals = store.eventCalendars(typeFilter: type)
                let defaultId = store.store.defaultCalendarForNewEvents?.calendarIdentifier
                let payload = CalendarsPayload(
                    calendars: cals.map { EventMapper.mapCalendar($0, defaultId: defaultId) },
                    count: cals.count
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<CalendarsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<CalendarsPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

Remove the now-unused `StubCalendar` and `StubCalendarsPayload` types from `main.swift`.

- [ ] **Step 3: Build**

```bash
cd swift && ./build.sh && cd ..
```

Expected: success.

- [ ] **Step 4: Run swift tests**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: pass.

- [ ] **Step 5: Hardware test (TCC)**

```bash
./bin/ical-bridge list-calendars
```

Expected: macOS calendar permission prompt appears the first time. After granting, output is real calendar JSON with at least one entry. If denied: error JSON with `"error_code":"permission_denied"`.

- [ ] **Step 6: Verify JSON validity**

```bash
./bin/ical-bridge list-calendars | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='success'; print(d['data']['count'])"
```

Expected: a positive integer (or 0 if the test machine genuinely has no event calendars, which is unusual).

- [ ] **Step 7: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift swift/Sources/ICalBridge/EventMapper.swift
git commit -m "feat(swift): list-calendars uses real EventKit"
```

---

### Task 19: get-events implementation

**Files:**
- Modify: `swift/Sources/ICalBridge/EventMapper.swift` (add `mapEvent`, payload structs)
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `GetEvents`)

- [ ] **Step 1: Append event-mapping code to `EventMapper.swift`**

```swift
struct EventPayload: Encodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let all_day: Bool
    let calendar_id: String
    let calendar_title: String
    let location: String?
    let notes: String?
    let url: String?
    let is_recurring: Bool
    let recurrence_rule: String?
}

struct EventsPayload: Encodable {
    let events: [EventPayload]
    let count: Int
    let truncated: Bool
}

struct EventWrapperPayload: Encodable {
    let event: EventPayload
}

extension EventMapper {
    static func mapEvent(_ ev: EKEvent) -> EventPayload {
        let urlStr: String? = ev.url?.absoluteString
        let recurrenceRule: String? = ev.hasRecurrenceRules ? "recurring" : nil
        return EventPayload(
            id: ev.calendarItemIdentifier,
            title: ev.title ?? "",
            start: formatISO(ev.startDate),
            end: formatISO(ev.endDate),
            all_day: ev.isAllDay,
            calendar_id: ev.calendar?.calendarIdentifier ?? "",
            calendar_title: ev.calendar?.title ?? "",
            location: (ev.location?.isEmpty == false) ? ev.location : nil,
            notes: (ev.notes?.isEmpty == false) ? ev.notes : nil,
            url: urlStr,
            is_recurring: ev.hasRecurrenceRules,
            recurrence_rule: recurrenceRule
        )
    }
}
```

- [ ] **Step 2: Replace `GetEvents.run` in `main.swift`**

```swift
    struct GetEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-events")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Flag(name: .customLong("no-all-day")) var noAllDay: Bool = false

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let twoYears: TimeInterval = 60 * 60 * 24 * 365 * 2
                if endDate.timeIntervalSince(startDate) > twoYears {
                    throw BridgeError.invalidInput("Range exceeds 2 years; use a tighter range.")
                }
                let calendars: [EKCalendar]?
                if let cid = calendarId {
                    guard let cal = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    calendars = [cal]
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate)
                let filtered = raw.filter { !(noAllDay && $0.isAllDay) }
                let limit = 500
                let truncated = filtered.count > limit
                let trimmed = Array(filtered.prefix(limit))
                let payload = EventsPayload(
                    events: trimmed.map(EventMapper.mapEvent),
                    count: trimmed.count,
                    truncated: truncated
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

Remove the now-unused `StubEvent`, `StubEventsPayload`, `StubEventWrapper` types from `main.swift`.

- [ ] **Step 3: Build and run swift tests**

```bash
cd swift && ./build.sh && swift test 2>&1 | tail -10 ; cd ..
```

Expected: success and tests pass.

- [ ] **Step 4: Hardware test**

```bash
./bin/ical-bridge get-events \
  --start "2026-05-01T00:00:00-07:00" \
  --end "2026-06-01T00:00:00-07:00" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['data']['count'])"
```

Expected: `success <int>`.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift swift/Sources/ICalBridge/EventMapper.swift
git commit -m "feat(swift): get-events queries EKEventStore predicate with range cap and limit"
```

---

### Task 20: search-events implementation

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `SearchEvents`)

- [ ] **Step 1: Replace `SearchEvents.run`**

```swift
    struct SearchEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search-events")
        @Option var query: String
        @Option var start: String?
        @Option var end: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let now = Date()
                let startDate = try start.map { try EventMapper.parseISO($0) } ?? now.addingTimeInterval(-60*60*24*90)
                let endDate = try end.map { try EventMapper.parseISO($0) } ?? now.addingTimeInterval(60*60*24*365)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let calendars: [EKCalendar]?
                if let cid = calendarId {
                    guard let cal = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    calendars = [cal]
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate)
                let needle = query.lowercased()
                let matched = raw.filter { ev in
                    let t = (ev.title ?? "").lowercased()
                    let l = (ev.location ?? "").lowercased()
                    let n = (ev.notes ?? "").lowercased()
                    return t.contains(needle) || l.contains(needle) || n.contains(needle)
                }
                let limit = 500
                let truncated = matched.count > limit
                let trimmed = Array(matched.prefix(limit))
                let payload = EventsPayload(
                    events: trimmed.map(EventMapper.mapEvent),
                    count: trimmed.count,
                    truncated: truncated
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

- [ ] **Step 2: Build, swift test, hardware test**

```bash
cd swift && ./build.sh && swift test 2>&1 | tail -5 ; cd ..
./bin/ical-bridge search-events --query "lunch" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'])"
```

Expected: build/tests succeed; smoke prints `success`.

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): search-events with in-process substring filter"
```

---

### Task 21: get-availability implementation + merge logic with TDD

**Files:**
- Create: `swift/Sources/ICalBridge/Availability.swift`
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `GetAvailability`)
- Modify: `swift/Tests/ICalBridgeTests/EventMapperTests.swift` (add merge tests)

- [ ] **Step 1: Write the failing merge test in `EventMapperTests.swift`**

Append:

```swift
final class AvailabilityMergeTests: XCTestCase {
    private func d(_ minutes: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(minutes * 60))
    }

    func testMergeNonOverlapping() {
        let busy = [
            BusyInterval(start: d(60), end: d(90), title: "A"),
            BusyInterval(start: d(120), end: d(150), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeOverlapping() {
        let busy = [
            BusyInterval(start: d(60), end: d(120), title: "A"),
            BusyInterval(start: d(90), end: d(150), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, d(60))
        XCTAssertEqual(merged[0].end, d(150))
    }

    func testMergeAdjacentWithinGranularity() {
        // Gap of 15 minutes < granularity 30 => merge
        let busy = [
            BusyInterval(start: d(60), end: d(90), title: "A"),
            BusyInterval(start: d(105), end: d(135), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 1)
    }

    func testFreeBlocksFromBusy() {
        let busy = [
            BusyInterval(start: d(120), end: d(150), title: "A")
        ]
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: busy)
        XCTAssertEqual(free.count, 2)
        XCTAssertEqual(free[0].start, d(60))
        XCTAssertEqual(free[0].end, d(120))
        XCTAssertEqual(free[1].start, d(150))
        XCTAssertEqual(free[1].end, d(180))
    }

    func testFreeBlocksNoBusy() {
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: [])
        XCTAssertEqual(free.count, 1)
        XCTAssertEqual(free[0].start, d(60))
        XCTAssertEqual(free[0].end, d(180))
    }

    func testFreeBlocksFullyBusy() {
        let busy = [BusyInterval(start: d(60), end: d(180), title: nil)]
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: busy)
        XCTAssertEqual(free.count, 0)
    }
}
```

- [ ] **Step 2: Run swift tests; confirm compile failure**

```bash
cd swift && swift test 2>&1 | tail -15 ; cd ..
```

Expected: compile errors about `Availability` / `BusyInterval`.

- [ ] **Step 3: Implement `swift/Sources/ICalBridge/Availability.swift`**

```swift
import Foundation

struct BusyInterval: Equatable {
    let start: Date
    let end: Date
    let title: String?
}

struct FreeInterval: Equatable {
    let start: Date
    let end: Date
}

enum Availability {
    static func merge(busy: [BusyInterval], granularityMinutes: Int) -> [BusyInterval] {
        guard !busy.isEmpty else { return [] }
        let gap = TimeInterval(granularityMinutes * 60)
        let sorted = busy.sorted { $0.start < $1.start }
        var out: [BusyInterval] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.start.timeIntervalSince(current.end) <= gap {
                let mergedEnd = max(current.end, next.end)
                let mergedTitle = current.title
                current = BusyInterval(start: current.start, end: mergedEnd, title: mergedTitle)
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }

    static func freeBlocks(rangeStart: Date, rangeEnd: Date, merged: [BusyInterval]) -> [FreeInterval] {
        var out: [FreeInterval] = []
        var cursor = rangeStart
        for b in merged {
            let bStart = max(b.start, rangeStart)
            let bEnd = min(b.end, rangeEnd)
            if bStart > cursor {
                out.append(FreeInterval(start: cursor, end: bStart))
            }
            cursor = max(cursor, bEnd)
        }
        if cursor < rangeEnd {
            out.append(FreeInterval(start: cursor, end: rangeEnd))
        }
        return out
    }
}
```

- [ ] **Step 4: Run swift tests; confirm pass**

```bash
cd swift && swift test 2>&1 | tail -10 ; cd ..
```

Expected: all tests pass.

- [ ] **Step 5: Add `AvailabilityResultPayload` to EventMapper.swift**

Append:

```swift
struct AvailabilityBusyOut: Encodable {
    let start: String
    let end: String
    let title: String?
}

struct AvailabilityFreeOut: Encodable {
    let start: String
    let end: String
}

struct AvailabilityResultPayload: Encodable {
    let start: String
    let end: String
    let busy: [AvailabilityBusyOut]
    let free: [AvailabilityFreeOut]
}
```

- [ ] **Step 6: Replace `GetAvailability.run` in `main.swift`**

```swift
    struct GetAvailability: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-availability")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-ids")) var calendarIds: String?
        @Option var granularity: Int = 30

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let calendars: [EKCalendar]?
                if let csv = calendarIds, !csv.isEmpty {
                    let ids = csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    var resolved: [EKCalendar] = []
                    for cid in ids {
                        guard let cal = store.calendar(byId: cid) else {
                            throw BridgeError.notFound("calendar id \(cid)")
                        }
                        resolved.append(cal)
                    }
                    calendars = resolved
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate).filter { !$0.isAllDay }
                let busy = raw.map { BusyInterval(start: $0.startDate, end: $0.endDate, title: $0.title) }
                let merged = Availability.merge(busy: busy, granularityMinutes: granularity)
                let free = Availability.freeBlocks(rangeStart: startDate, rangeEnd: endDate, merged: merged)
                let payload = AvailabilityResultPayload(
                    start: EventMapper.formatISO(startDate),
                    end: EventMapper.formatISO(endDate),
                    busy: merged.map { AvailabilityBusyOut(start: EventMapper.formatISO($0.start), end: EventMapper.formatISO($0.end), title: $0.title) },
                    free: free.map { AvailabilityFreeOut(start: EventMapper.formatISO($0.start), end: EventMapper.formatISO($0.end)) }
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<AvailabilityResultPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<AvailabilityResultPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

Remove the leftover `StubAvailability*` types from `main.swift`.

- [ ] **Step 7: Build, swift test, hardware test**

```bash
cd swift && ./build.sh && swift test 2>&1 | tail -10 ; cd ..
./bin/ical-bridge get-availability --start "2026-05-08T08:00:00-07:00" --end "2026-05-08T18:00:00-07:00" | python3 -m json.tool | head -30
```

Expected: success JSON with `busy` and `free` arrays.

- [ ] **Step 8: Commit**

```bash
git add swift/Sources/ICalBridge/Availability.swift swift/Sources/ICalBridge/main.swift swift/Sources/ICalBridge/EventMapper.swift swift/Tests/ICalBridgeTests/EventMapperTests.swift
git commit -m "feat(swift): get-availability with merge/free-block logic and unit tests"
```

---

### Task 22: Mid-phase integration + bundle reinstall

**Files:** none modified.

- [ ] **Step 1: `pnpm package` and reinstall in Claude Desktop**

```bash
pnpm package
```

In Claude Desktop, uninstall the previous extension, then install the new `.mcpb`.

- [ ] **Step 2: In Claude, exercise read tools**

Ask Claude to:
- "List my calendars" → should return real calendars.
- "What's on my calendar this week?" → should call `get_events`.
- "Search for 'standup' in my calendar" → should call `search_events`.
- "When am I free tomorrow between 8 and 6?" → should call `get_availability`.

Expected: each returns sane real data.

- [ ] **Step 3: No commit** — verification only.

---

## Phase 5 — Real EventKit Writes

### Task 23: create-event implementation

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `CreateEvent`)

- [ ] **Step 1: Replace `CreateEvent.run`**

```swift
    struct CreateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create-event")
        @Option var title: String
        @Option var start: String
        @Option var end: String
        @Flag(name: .customLong("all-day")) var allDay: Bool = false
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let cal: EKCalendar
                if let cid = calendarId {
                    guard let resolved = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    cal = resolved
                } else {
                    guard let def = store.store.defaultCalendarForNewEvents else {
                        throw BridgeError.notFound("no default calendar for new events")
                    }
                    cal = def
                }
                guard cal.allowsContentModifications else {
                    throw BridgeError.readOnly("calendar \(cal.title) does not allow modifications")
                }
                let ev = EKEvent(eventStore: store.store)
                ev.calendar = cal
                ev.title = title
                ev.startDate = startDate
                ev.endDate = endDate
                ev.isAllDay = allDay
                ev.location = location
                ev.notes = notes
                if let urlStr = url, let u = URL(string: urlStr) {
                    ev.url = u
                }
                do {
                    try store.store.save(ev, span: .thisEvent, commit: true)
                } catch {
                    throw BridgeError.saveFailed(error.localizedDescription)
                }
                let payload = EventWrapperPayload(event: EventMapper.mapEvent(ev))
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

- [ ] **Step 2: Build + tests**

```bash
cd swift && ./build.sh && swift test 2>&1 | tail -5 ; cd ..
```

Expected: success.

- [ ] **Step 3: Hardware test**

```bash
./bin/ical-bridge create-event \
  --title "Plan integration test" \
  --start "2026-05-09T15:00:00-07:00" \
  --end "2026-05-09T15:30:00-07:00" \
  --notes "delete me" \
  | python3 -m json.tool
```

Expected: success JSON with a fresh `event.id`. Open Calendar.app and verify the event appears, then delete it manually.

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): create-event writes to default or specified writable calendar"
```

---

### Task 24: update-event implementation (patch semantics)

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `UpdateEvent`)

- [ ] **Step 1: Replace `UpdateEvent.run`**

```swift
    struct UpdateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "update-event")
        @Option var id: String
        @Option var title: String?
        @Option var start: String?
        @Option var end: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                guard let ev = store.event(byId: id) else {
                    throw BridgeError.notFound("event id \(id)")
                }
                guard ev.calendar?.allowsContentModifications == true else {
                    throw BridgeError.readOnly("calendar \(ev.calendar?.title ?? "?") does not allow modifications")
                }
                if let t = title { ev.title = t }
                if let s = start { ev.startDate = try EventMapper.parseISO(s) }
                if let e = end { ev.endDate = try EventMapper.parseISO(e) }
                if let l = location { ev.location = l }
                if let n = notes { ev.notes = n }
                if let u = url { ev.url = URL(string: u) }
                if let cid = calendarId {
                    guard let cal = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    guard cal.allowsContentModifications else {
                        throw BridgeError.readOnly("calendar \(cal.title) does not allow modifications")
                    }
                    ev.calendar = cal
                }
                if ev.endDate <= ev.startDate {
                    throw BridgeError.invalidInput("end must be after start after applying updates")
                }
                let span: EKSpan = ev.hasRecurrenceRules ? .futureEvents : .thisEvent
                do {
                    try store.store.save(ev, span: span, commit: true)
                } catch {
                    throw BridgeError.saveFailed(error.localizedDescription)
                }
                let payload = EventWrapperPayload(event: EventMapper.mapEvent(ev))
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
```

(Per PRD §5.5, recurring-series writes use the future-events span in v1; the tool description in `src/schemas.ts` already mentions this.)

- [ ] **Step 2: Build + tests + hardware test**

```bash
cd swift && ./build.sh && swift test 2>&1 | tail -5 ; cd ..
```

Manually create a test event in Calendar.app, copy its identifier (or use one from `get-events`), and run:

```bash
./bin/ical-bridge update-event --id "<paste-id>" --title "Updated title" | python3 -m json.tool
```

Expected: success JSON; Calendar.app reflects the new title.

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): update-event patch semantics with recurring-series fallback"
```

---

### Task 25: delete-event implementation

**Files:**
- Modify: `swift/Sources/ICalBridge/main.swift` (replace `DeleteEvent`)

- [ ] **Step 1: Replace `DeleteEvent.run`**

```swift
    struct DeleteEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete-event")
        @Option var id: String
        @Option var span: String = "this_only"

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                guard let ev = store.event(byId: id) else {
                    throw BridgeError.notFound("event id \(id)")
                }
                guard ev.calendar?.allowsContentModifications == true else {
                    throw BridgeError.readOnly("calendar \(ev.calendar?.title ?? "?") does not allow modifications")
                }
                let ekSpan: EKSpan = (span == "all") ? .futureEvents : .thisEvent
                do {
                    try store.store.remove(ev, span: ekSpan, commit: true)
                } catch {
                    throw BridgeError.saveFailed(error.localizedDescription)
                }
                struct Out: Encodable { let deleted: Bool; let id: String }
                OutputJSON.emit(BridgeResult.success(Out(deleted: true, id: id)))
            } catch let err as BridgeError {
                struct Out: Encodable { let deleted: Bool; let id: String }
                OutputJSON.emit(BridgeResult<Out>.error(err))
            } catch {
                struct Out: Encodable { let deleted: Bool; let id: String }
                OutputJSON.emit(BridgeResult<Out>.error(.internalError(String(describing: error))))
            }
        }
    }
```

Remove the `StubDeletePayload` struct from `main.swift`.

- [ ] **Step 2: Build + hardware test**

```bash
cd swift && ./build.sh && cd ..
# Use a real id from a test event
./bin/ical-bridge delete-event --id "<paste-id>" | python3 -m json.tool
```

Expected: success JSON; Calendar.app no longer shows the event.

- [ ] **Step 3: Read-only calendar smoke**

If a Birthdays/subscription calendar is available, attempt to delete one of its events. Expected: `read_only` error.

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/ICalBridge/main.swift
git commit -m "feat(swift): delete-event with read-only guard and span support"
```

---

### Task 26: End-to-end packaged regression

**Files:** none modified.

- [ ] **Step 1: Clean rebuild and repackage**

```bash
pnpm clean
pnpm install
pnpm test
cd swift && swift test ; cd ..
pnpm package
```

Expected: green tests, `.mcpb` produced.

- [ ] **Step 2: Reinstall in Claude Desktop and run the manual test matrix**

Walk through each row of PRD §11 "Manual test matrix":

| Scenario | Expected |
| --- | --- |
| First run, permission not granted | macOS prompt appears |
| Permission denied, then call any tool | error mentions System Settings |
| `list_calendars` after grant | real calendars |
| `get_events` for current week | matches Calendar.app |
| `create_event` | event appears in Calendar.app |
| `update_event` title change | reflected in Calendar.app |
| `delete_event` | event disappears |
| `get_availability` for a busy day | busy/free arrays match visible events |
| Machine with no iCloud | local calendars only, no error |
| `create_event` on subscription calendar | `read_only` error |
| 20 quick `list_calendars` calls | all complete cleanly |

For any failure, capture stderr from Claude Desktop's extension log, fix the underlying cause (do not work around it), commit, repackage, retest.

- [ ] **Step 3: No commit** — verification only.

---

## Phase 6 — QA and Polish

### Task 27: README, icon, final docs

**Files:**
- Modify: `README.md`
- Replace: `icon.png` (final 256x256 asset)

- [ ] **Step 1: Replace `README.md` with the full document**

```markdown
# iCal Integration

A Claude Desktop Extension that gives Claude full read and write access to your macOS Calendar (including any iCloud, Google, or Exchange calendars visible in Calendar.app) via Apple's native EventKit framework.

No app-specific passwords. No CalDAV. No credential storage. The extension reads and writes the same local Calendar database that Calendar.app uses.

## Requirements

- macOS 13.0 (Ventura) or later, Apple Silicon (arm64)
- Claude Desktop 1.0.0 or later
- Calendar.app set up with at least one calendar (iCloud, Google, Exchange, or local)

## Installation

1. Download the latest `ical-integration-1.0.0.mcpb` from the GitHub Releases page.
2. Open Claude Desktop, go to Settings, Extensions, Advanced settings, Extension Developer.
3. Click "Install Extension..." and pick the `.mcpb` file.
4. The first time Claude calls a calendar tool, macOS will prompt for permission. Click "OK".

If you ever need to grant or revoke permission manually: System Settings, Privacy and Security, Calendars.

## Tools

| Tool | Purpose |
| --- | --- |
| `list_calendars` | List all calendars Claude can see |
| `get_events` | Fetch events in a date range |
| `search_events` | Full-text search across event title, location, notes |
| `create_event` | Create a new event |
| `update_event` | Update fields of an existing event |
| `delete_event` | Delete an event |
| `get_availability` | Return free/busy blocks for scheduling |

## Troubleshooting

### "Calendar access denied"

macOS denied calendar permission, or you have not granted it yet. Open System Settings, Privacy and Security, Calendars, and turn on the toggle for Claude.

If the toggle is missing, the OS has not asked yet; restart Claude Desktop and call any tool to trigger the prompt.

### "Bridge binary not found"

The `.mcpb` did not unpack correctly. Reinstall it from Settings, Extensions.

### Calendar changes are not visible immediately

EventKit syncs through the macOS Calendar service. iCloud changes can take a few seconds to propagate.

## Privacy

See PRIVACY.md. All calendar data stays on your local machine.

## License

See LICENSE. Noncommercial use only; contact the author for commercial licensing.

## Build from source

Requirements: Node 18+, pnpm 9, Swift 5.9+.

```bash
pnpm install
pnpm build
pnpm test
pnpm package    # produces ical-integration-1.0.0.mcpb
```
```

- [ ] **Step 2: Replace `icon.png` with a real 256x256 icon**

If you have a final icon asset, copy it to `icon.png`. If not, generate one from a simple emoji/glyph using ImageMagick:

```bash
# Optional: requires `brew install imagemagick`. If unavailable, keep the placeholder for v1.
if command -v magick >/dev/null; then
  magick -size 256x256 xc:'#1F2937' -gravity center -fill '#F9FAFB' -font 'Apple-Color-Emoji' -pointsize 180 -annotate +0+0 '📅' icon.png
  file icon.png
fi
```

Expected (if magick available): `icon.png: PNG image data, 256 x 256, ...`. Otherwise leave the placeholder from Task 3.

- [ ] **Step 3: Final em-dash sweep on shipped text**

```bash
grep -nP '\x{2014}' README.md PRIVACY.md LICENSE manifest.json src/schemas.ts || echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add README.md icon.png
git commit -m "docs: full README + final icon"
```

---

### Task 28: Final clean build, tag, release

**Files:** none modified by hand.

- [ ] **Step 1: Final clean build and full test run**

```bash
pnpm clean
pnpm install
pnpm test
cd swift && swift test ; cd ..
pnpm package
```

Expected: every step green, `.mcpb` produced.

- [ ] **Step 2: Tag v1.0.0**

```bash
git tag -a v1.0.0 -m "v1.0.0: initial release"
git push origin main --tags
```

- [ ] **Step 3: Create GitHub release with `.mcpb` attached**

```bash
gh release create v1.0.0 ./ical-integration-*.mcpb \
  --title "v1.0.0" \
  --notes "Initial release. macOS Calendar (EventKit) MCP server. See README for installation."
```

Expected: release URL printed.

- [ ] **Step 4: Final manual install from release**

Download the `.mcpb` from the release page (not the local build), install it in a fresh Claude Desktop profile or after uninstalling the previous build, and run one tool of each kind (`list_calendars`, `get_events`, `create_event`, `delete_event`). Confirm all work.

- [ ] **Step 5: No commit** — release artifact lives on GitHub.

---

## Self-Review Checklist (run before dispatching task 1)

Spec coverage:
- §3 project structure — covered by Tasks 1, 4, 11, 15
- §4 manifest — Task 2
- §5.1 list_calendars — Tasks 10, 13, 18
- §5.2 get_events — Tasks 10, 13, 19
- §5.3 search_events — Tasks 10, 13, 20
- §5.4 create_event — Tasks 10, 13, 23
- §5.5 update_event — Tasks 10, 13, 24
- §5.6 delete_event — Tasks 10, 13, 25
- §5.7 get_availability — Tasks 10, 13, 21
- §6 Swift binary — Tasks 4–8, 17–25
- §7 Node MCP server — Tasks 9–14
- §8 Permissions (TCC + read-only) — Tasks 17, 23, 24, 25
- §9 License + privacy — Task 3
- §10 build/package — Tasks 4, 15, 28
- §11 testing matrix — Tasks 5, 6, 7, 12, 17, 21, 26
- §12 implementation order — entire plan structure
- §13 constraints — enforced via the "Style rules" preamble + manifest checks (Task 2) + lockfile check (Task 1.7) + no-em-dash sweep (Tasks 2, 27)

Placeholder scan: no "TBD", no "implement appropriate handling" without code, no "similar to Task N" without inlined code. Each step that changes code shows the code.

Type consistency:
- TS `BridgeResult<T>` (`src/types.ts`) ↔ Swift `BridgeResult<T>` (`OutputJSON.swift`) — both have `status`, `data`, `error_code`, `error_message`. ✓
- Tool names in `manifest.json` (Task 2) ↔ keys in `toolJsonSchemas` (Task 10) ↔ keys in `handlers` (Task 13). ✓
- CLI subcommand names: `list-calendars`, `get-events`, `search-events`, `create-event`, `update-event`, `delete-event`, `get-availability` — match between Task 8 (stub) and Tasks 18–25 (real). ✓
- Flag names (`--start`, `--end`, `--calendar-id`, `--no-all-day`, `--all-day`, `--calendar-ids`, `--granularity`) — consistent between Task 13 builder and Task 8/18–25 ArgumentParser definitions. ✓
- `EventPayload` fields (`id`, `title`, `start`, `end`, `all_day`, `calendar_id`, `calendar_title`, `location`, `notes`, `url`, `is_recurring`, `recurrence_rule`) — match between Swift `EventPayload` (Task 19) and TS `EventSummary` (Task 9). ✓

---

## Execution Notes for the Orchestrator

1. **Use `superpowers:subagent-driven-development`.** Fresh subagent per task; spec-compliance review then code-quality review after each.
2. **Every dispatched subagent runs on `sonnet[1m]` (verbatim).** This applies to implementer, spec-reviewer, and code-quality-reviewer roles equally for this plan.
3. **TCC-bound tasks (17–26) require running on the user's actual Mac.** Subagents executing those tasks must be told that the macOS calendar permission prompt is expected and the user may need to click "OK" in the system dialog. If the subagent runs in an environment without TCC, it will see `permission_denied` even from a freshly built binary — that is not a code defect.
4. **Hardware-only failures should not loop forever.** If a Phase 4/5 subagent hits a hardware/permission wall it cannot resolve, it should report `BLOCKED` with the captured stderr; do not switch to a more capable model — escalate to the human.
5. **Subagents must not run `pnpm clean` mid-phase** (it would discard the partially built artifacts the next subagent expects). Only Tasks 14, 26, 28 perform a full clean rebuild.
