# ICS Calendar — Product Requirements Document

> **Naming note:** The display name "ICS Calendar" uses "iCal," which is a trademark of Apple Inc.
> Before submitting to the Anthropic extension directory, rename to something like "Calendar Integration,"
> "Apple Calendar MCP," or "EventKit Bridge" to avoid trademark issues.

**Version:** 1.0
**Format:** MCP Bundle (`.mcpb`) following manifest spec v0.3
**Target client:** Claude Desktop on macOS (Apple Silicon)
**Owner:** Alexey Fedorov

---

## Reference Implementations

Before writing any code, Claude Code should read the following repos for architecture patterns,
CalDAV quirks, and EventKit permission flows. These are the closest prior art:

- **`iteratio/icloud-mcp`** (Python, macOS Keychain, EventKit + IMAP via stdio MCP)
  `https://github.com/iteratio/icloud-mcp`
- **`roygabriel/mcp-icloud-calendar`** (Go binary, CalDAV, single static executable)
  `https://github.com/roygabriel/mcp-icloud-calendar`
- **`icloud-calendar-mcp/icloud-calendar-mcp`** (Kotlin/JVM, CalDAV, OWASP-aligned)
  `https://github.com/icloud-calendar-mcp/icloud-calendar-mcp`
- **`localhost433/icloud-mcp`** (Python HTTP MCP, CalDAV, the prior implementation)
  `https://github.com/localhost433/icloud-mcp`

The present project departs from all of the above by using **EventKit** (Apple's native macOS
Calendar framework) instead of CalDAV. This means no app-specific password, no network calls,
and no credential storage. The binary reads and writes the same local Calendar database that
Calendar.app uses, which already syncs iCloud calendars via the OS.

Also reference the **deskview-mcp** project for the exact Node.js + Swift binary DXT pattern
this project mirrors: `https://github.com/alexey-max-fedorov/deskview-mcp`

---

## 1. Overview

### What this is

A Claude Desktop Extension distributed as an `.mcpb` bundle that gives Claude full read/write
access to the user's macOS Calendar (including all iCloud-synced calendars) via Apple's
EventKit framework. The extension exposes seven MCP tools covering the full calendar lifecycle:
listing calendars, fetching events, searching events, creating events, updating events, deleting
events, and checking availability.

### Why EventKit instead of CalDAV

| Approach | Credential required | Network calls | Offline support | Covers all calendars |
|---|---|---|---|---|
| CalDAV | App-specific password | Yes | No | iCloud only |
| EventKit | None (TCC permission) | No | Yes | All (iCloud, Google, Exchange, local) |

EventKit is the right call. It is the same API that Calendar.app, Fantastical, BusyCal, and
Reminders use. The TCC permission prompt ("Claude wants access to your calendars") is the
standard macOS flow users already recognize.

### Architecture summary

```
Claude Desktop (MCP host)
  └── Spawns via stdio transport (per manifest mcp_config)
      └── Node.js MCP server (server/index.js)
          - Registers 7 tools with @modelcontextprotocol/sdk
          - On tool call: child_process.spawn(swift binary)
          - Parses JSON from binary stdout
          - Returns MCP content blocks
          └── Swift CLI binary (bin/ics-bridge, arm64)
              - EventKit: EKEventStore, EKCalendar, EKEvent
              - Reads/writes local Calendar database (iCloud-synced by OS)
              - Outputs single JSON object to stdout, exits
```

### Tools exposed

| Tool | Behavior | Mutating |
|---|---|---|
| `list_calendars` | List all calendars with id, title, color, type | No |
| `get_events` | Fetch events in a date range, optionally filtered by calendar | No |
| `search_events` | Full-text search events by keyword across a time window | No |
| `create_event` | Create a new event | Yes |
| `update_event` | Update fields of an existing event by id | Yes |
| `delete_event` | Delete an event by id | Yes |
| `get_availability` | Return free/busy blocks for a date range | No |

---

## 2. Goals and Non-Goals

### Goals (v1)

- Single double-click install via `.mcpb` bundle
- Native macOS TCC calendar permission prompt on first run
- Zero credentials required from the user
- Works with all calendar sources visible in Calendar.app (iCloud, Google, Exchange, local)
- Sub-200ms response for read operations on a local database
- Full CRUD: list, read, search, create, update, delete
- Availability query (free/busy) for scheduling use cases
- Self-contained bundle: ships compiled arm64 binary, no Swift runtime install needed
- Clear error surfaces when permissions are denied or calendar is not found

### Non-Goals (v1)

- Intel Mac support (arm64 only, M-series target)
- Recurring event instance editing (editing a single occurrence of a recurring series) -- v2
- Attendee management / sending invites (requires mail integration) -- v2
- Alarm / notification management -- v2
- CalDAV fallback for non-Mac environments -- out of scope by design
- Cross-platform support -- EventKit is Apple-only by definition
- Real-time push notifications for calendar changes -- v2

---

## 3. Project Structure

```
ics-calendar/
├── manifest.json                              # MCPB v0.3 manifest
├── package.json                               # Node deps + scripts (pnpm only)
├── pnpm-lock.yaml                             # Committed lockfile
├── tsconfig.json                              # Strict TS, ES2022, outDir=server/
├── vitest.config.ts                           # Test runner config
├── .mcpbignore                                # Excludes src/, swift/, etc. from pack
├── .gitignore
├── README.md
├── LICENSE
├── PRIVACY.md
├── icon.png                                   # 256x256 extension icon
│
├── src/                                       # TypeScript source
│   ├── index.ts                               # MCP server entry, ListTools/CallTool
│   ├── bridge.ts                              # Spawns Swift binary, parses JSON
│   ├── schemas.ts                             # Zod schemas + JSON Schema mirrors
│   ├── types.ts                               # Shared TS types
│   └── __tests__/
│       ├── bridge.test.ts                     # Bridge tests using stub binaries
│       └── fixtures/
│           ├── stub-calendars.sh              # Returns fake calendar list JSON
│           ├── stub-events.sh                 # Returns fake event list JSON
│           ├── stub-create.sh                 # Returns fake created event JSON
│           ├── stub-error.sh                  # Returns permission-denied error JSON
│           └── stub-crash.sh                  # Exits non-zero with garbage stdout
│
├── server/                                    # tsc output (gitignored, packed into .mcpb)
│   └── index.js
│
├── swift/                                     # Swift source (NOT shipped in bundle)
│   ├── Package.swift
│   ├── build.sh
│   ├── Sources/
│   │   └── ICSBridge/
│   │       ├── main.swift                     # ArgumentParser CLI entry, subcommands
│   │       ├── CalendarStore.swift            # EKEventStore wrapper, permission flow
│   │       ├── EventMapper.swift              # EKEvent <-> JSON serialization
│   │       ├── OutputJSON.swift               # Codable result structs, emit(), logStderr()
│   │       └── BridgeError.swift              # Typed errors -> error_code strings
│   └── Tests/
│       └── ICSBridgeTests/
│           ├── EventMapperTests.swift         # Pure-function tests on date/field mapping
│           └── SmokeTests.swift               # Error code and JSON encoding tests
│
├── bin/                                       # Compiled binary (gitignored, packed)
│   └── ics-bridge
│
└── node_modules/                              # Production deps (packed into .mcpb)
```

---

## 4. Manifest Specification

Manifest follows MCPB spec **version 0.3**.

### `manifest.json`

```json
{
  "manifest_version": "0.3",
  "name": "ics-calendar",
  "display_name": "ICS Calendar",
  "version": "1.0.0",
  "description": "Read and write your Mac Calendar (including iCloud) directly from Claude, via Apple's native EventKit framework. No credentials required.",
  "long_description": "ICS Calendar gives Claude full access to your macOS Calendar database through Apple's EventKit framework, the same API used by Calendar.app and Fantastical. List calendars, fetch and search events, create, update, and delete events, and check your availability, all without entering any credentials. Any calendar visible in Calendar.app works, including iCloud, Google, Exchange, and local calendars.",
  "author": {
    "name": "Alexey Fedorov",
    "email": "alexey.max.fedorov@gmail.com",
    "url": "https://github.com/alexey-max-fedorov"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/alexey-max-fedorov/ics-calendar"
  },
  "homepage": "https://github.com/alexey-max-fedorov/ics-calendar",
  "documentation": "https://github.com/alexey-max-fedorov/ics-calendar#readme",
  "support": "https://github.com/alexey-max-fedorov/ics-calendar/issues",
  "icon": "icon.png",
  "keywords": ["calendar", "ical", "icloud", "eventkit", "macos", "scheduling"],
  "license": "LicenseRef-iCal-Integration",
  "server": {
    "type": "node",
    "entry_point": "server/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["${__dirname}/server/index.js"],
      "env": {
        "ICS_BRIDGE_BIN": "${__dirname}/bin/ics-bridge"
      }
    }
  },
  "tools": [
    {
      "name": "list_calendars",
      "description": "List all calendars visible in Calendar.app (iCloud, Google, Exchange, local)."
    },
    {
      "name": "get_events",
      "description": "Fetch events within a date range, optionally filtered by calendar."
    },
    {
      "name": "search_events",
      "description": "Search events by keyword across a configurable time window."
    },
    {
      "name": "create_event",
      "description": "Create a new calendar event."
    },
    {
      "name": "update_event",
      "description": "Update fields of an existing event by its id."
    },
    {
      "name": "delete_event",
      "description": "Delete an event by its id."
    },
    {
      "name": "get_availability",
      "description": "Return free and busy blocks for a date range to support scheduling."
    }
  ],
  "compatibility": {
    "claude_desktop": ">=1.0.0",
    "platforms": ["darwin"],
    "runtimes": {
      "node": ">=18.0.0"
    }
  }
}
```

### Critical manifest details

- `manifest_version` must be `"0.3"`.
- `server.type` is `"node"`. The Swift binary is a subprocess, not the MCP server itself.
- `${__dirname}` resolves to the bundle install directory at runtime.
- `ICS_BRIDGE_BIN` passes the resolved binary path to the Node server.
- `tools` entries only need `name` and optional `description`. Input schemas live in `src/schemas.ts`.
- `compatibility.platforms: ["darwin"]` is explicit macOS-only.

### `.mcpbignore`

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
```

---

## 5. Tool Specifications

All dates and times are **ISO 8601** strings with explicit timezone offset or `Z` for UTC.
The binary handles timezone conversion; callers always pass ISO strings.
All event `id` values are the `calendarItemIdentifier` from EventKit, which is a stable opaque
string that persists across app restarts.

---

### 5.1 `list_calendars`

**Description:** Return all calendars available in Calendar.app.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    type_filter: {
      type: "string",
      enum: ["all", "event", "reminder"],
      default: "event",
      description: "Which calendar types to include. Use 'event' for standard calendars."
    }
  },
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "text",
      text: JSON.stringify({
        calendars: [
          {
            id: "EKCalendar-opaque-id",
            title: "Personal",
            color: "#FF2D55",
            type: "calDAV",        // "local" | "calDAV" | "exchange" | "subscription" | "birthday"
            account: "iCloud",
            is_default: true
          }
        ],
        count: 1
      })
    }
  ]
}
```

**Output (error):**
```typescript
{
  content: [{ type: "text", text: "<human-readable error>" }],
  isError: true
}
```

---

### 5.2 `get_events`

**Description:** Return events in a date range. Up to 500 events returned; use a tighter range if needed.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    start: {
      type: "string",
      description: "ISO 8601 start datetime, e.g. '2026-05-01T00:00:00-07:00'."
    },
    end: {
      type: "string",
      description: "ISO 8601 end datetime."
    },
    calendar_id: {
      type: "string",
      description: "Optional. Restrict to a specific calendar by its id from list_calendars."
    },
    include_all_day: {
      type: "boolean",
      default: true,
      description: "Whether to include all-day events."
    }
  },
  required: ["start", "end"],
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "text",
      text: JSON.stringify({
        events: [
          {
            id: "EKEvent-opaque-id",
            title: "Team standup",
            start: "2026-05-08T09:00:00-07:00",
            end: "2026-05-08T09:30:00-07:00",
            all_day: false,
            calendar_id: "EKCalendar-opaque-id",
            calendar_title: "Work",
            location: "Zoom",
            notes: "Link: zoom.us/j/123",
            url: null,
            is_recurring: false,
            recurrence_rule: null
          }
        ],
        count: 1,
        truncated: false
      })
    }
  ]
}
```

**Error cases:**
- `start` or `end` is not a valid ISO 8601 string: schema validation error
- `calendar_id` not found: error text naming the unknown id
- Range exceeds 2 years: error text asking for a tighter range

---

### 5.3 `search_events`

**Description:** Full-text search across event titles, notes, and location within a time window.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    query: {
      type: "string",
      description: "Search term to match against event title, location, and notes."
    },
    start: {
      type: "string",
      description: "ISO 8601 start of the search window. Defaults to 90 days ago."
    },
    end: {
      type: "string",
      description: "ISO 8601 end of the search window. Defaults to 1 year from now."
    },
    calendar_id: {
      type: "string",
      description: "Optional. Restrict search to one calendar."
    }
  },
  required: ["query"],
  additionalProperties: false
}
```

**Output:** Same shape as `get_events` output, filtered to matching events.

**Implementation note (Swift side):**
EventKit's `EKEventStore.events(matching:)` accepts a predicate but does not do full-text
search natively. The binary fetches all events in the window via predicate, then filters in-process
by lowercased substring match on `title`, `location`, and `notes`. This is fine for typical
calendar sizes (< 10,000 events).

---

### 5.4 `create_event`

**Description:** Create a new event in the specified calendar.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    title: {
      type: "string",
      description: "Event title."
    },
    start: {
      type: "string",
      description: "ISO 8601 start datetime."
    },
    end: {
      type: "string",
      description: "ISO 8601 end datetime. Must be after start."
    },
    all_day: {
      type: "boolean",
      default: false,
      description: "If true, start and end are treated as dates, not datetimes."
    },
    calendar_id: {
      type: "string",
      description: "Optional. Target calendar id. Defaults to the user's default calendar."
    },
    location: {
      type: "string",
      description: "Optional. Location string."
    },
    notes: {
      type: "string",
      description: "Optional. Free-text notes body."
    },
    url: {
      type: "string",
      description: "Optional. URL associated with the event."
    }
  },
  required: ["title", "start", "end"],
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "text",
      text: JSON.stringify({
        event: {
          id: "EKEvent-new-opaque-id",
          title: "Dentist",
          start: "2026-05-20T14:00:00-07:00",
          end: "2026-05-20T15:00:00-07:00",
          all_day: false,
          calendar_id: "EKCalendar-opaque-id",
          calendar_title: "Personal",
          location: "123 Main St",
          notes: null,
          url: null,
          is_recurring: false,
          recurrence_rule: null
        }
      })
    }
  ]
}
```

**Error cases:**
- `end` is before or equal to `start`: validation error
- `calendar_id` not found: error naming the unknown id
- No writable calendars available: error explaining permissions
- EventKit save failure: error with detail

---

### 5.5 `update_event`

**Description:** Update one or more fields of an existing event. Only supplied fields are changed.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    id: {
      type: "string",
      description: "Event id from get_events or create_event."
    },
    title: { type: "string" },
    start: { type: "string", description: "ISO 8601 datetime." },
    end: { type: "string", description: "ISO 8601 datetime." },
    location: { type: "string" },
    notes: { type: "string" },
    url: { type: "string" },
    calendar_id: {
      type: "string",
      description: "Move the event to a different calendar."
    }
  },
  required: ["id"],
  additionalProperties: false
}
```

**Behavior:**
- Fetch the existing event by `id`.
- Apply only the fields present in the input (patch semantics, not replace).
- If `start` is updated but `end` is not (or vice versa), validate that the final start < end.
- For recurring events: update the entire series (span `.futureEvents` is not supported in v1).
  Add a note in the response text if the event is recurring.
- Save and return the updated event JSON.

**Output:** Same shape as `create_event` success output with the updated event.

**Error cases:**
- Event not found by `id`: error naming the unknown id
- Read-only calendar (subscriptions, birthdays): error explaining the calendar type
- start >= end after partial update: validation error

---

### 5.6 `delete_event`

**Description:** Delete an event by id. This is permanent.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    id: {
      type: "string",
      description: "Event id from get_events or create_event."
    },
    span: {
      type: "string",
      enum: ["this_only", "all"],
      default: "this_only",
      description: "For recurring events: delete only this occurrence or the entire series."
    }
  },
  required: ["id"],
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "text",
      text: JSON.stringify({ deleted: true, id: "EKEvent-opaque-id" })
    }
  ]
}
```

**Output (error):**
```typescript
{
  content: [{ type: "text", text: "<human-readable error>" }],
  isError: true
}
```

**Error cases:**
- Event not found: error naming the id
- Read-only calendar: error
- EventKit remove failure: error with detail

---

### 5.7 `get_availability`

**Description:** Return free and busy blocks for a date range. Useful for scheduling.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    start: {
      type: "string",
      description: "ISO 8601 start of the range."
    },
    end: {
      type: "string",
      description: "ISO 8601 end of the range."
    },
    calendar_ids: {
      type: "array",
      items: { type: "string" },
      description: "Optional. Restrict to specific calendar ids. Defaults to all event calendars."
    },
    granularity_minutes: {
      type: "number",
      default: 30,
      minimum: 15,
      maximum: 120,
      description: "Minimum block size in minutes. Adjacent events closer than this are merged."
    }
  },
  required: ["start", "end"],
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "text",
      text: JSON.stringify({
        start: "2026-05-08T08:00:00-07:00",
        end: "2026-05-08T18:00:00-07:00",
        busy: [
          { start: "2026-05-08T09:00:00-07:00", end: "2026-05-08T09:30:00-07:00", title: "Standup" },
          { start: "2026-05-08T14:00:00-07:00", end: "2026-05-08T15:00:00-07:00", title: "1:1" }
        ],
        free: [
          { start: "2026-05-08T08:00:00-07:00", end: "2026-05-08T09:00:00-07:00" },
          { start: "2026-05-08T09:30:00-07:00", end: "2026-05-08T14:00:00-07:00" },
          { start: "2026-05-08T15:00:00-07:00", end: "2026-05-08T18:00:00-07:00" }
        ]
      })
    }
  ]
}
```

---

## 6. Swift Binary Specification

### CLI surface

```bash
# List calendars
./ics-bridge list-calendars [--type event|reminder|all]

# Get events in range
./ics-bridge get-events \
  --start "2026-05-01T00:00:00-07:00" \
  --end "2026-06-01T00:00:00-07:00" \
  [--calendar-id <id>] \
  [--no-all-day]

# Search events
./ics-bridge search-events \
  --query "dentist" \
  [--start <iso>] \
  [--end <iso>] \
  [--calendar-id <id>]

# Create event
./ics-bridge create-event \
  --title "Team lunch" \
  --start "2026-05-15T12:00:00-07:00" \
  --end "2026-05-15T13:00:00-07:00" \
  [--all-day] \
  [--calendar-id <id>] \
  [--location "Chipotle"] \
  [--notes "Bring receipt"] \
  [--url "https://..."]

# Update event (only pass fields to change)
./ics-bridge update-event \
  --id <event-id> \
  [--title <new-title>] \
  [--start <iso>] \
  [--end <iso>] \
  [--location <loc>] \
  [--notes <notes>] \
  [--url <url>] \
  [--calendar-id <id>]

# Delete event
./ics-bridge delete-event \
  --id <event-id> \
  [--span this_only|all]

# Get availability
./ics-bridge get-availability \
  --start <iso> \
  --end <iso> \
  [--calendar-ids <id1,id2>] \
  [--granularity 30]
```

### Output JSON schema

All subcommands write a **single JSON object** to stdout and exit. All logs go to stderr.

```json
{
  "status": "success" | "error",
  "data": <subcommand-specific payload> | null,
  "error_code": null | "permission_denied" | "not_found" | "invalid_input" | "read_only" | "save_failed" | "internal",
  "error_message": null | "<human-readable detail>"
}
```

The `data` field shape matches the JSON described in Section 5 for each tool.

### `CalendarStore.swift` -- EKEventStore wrapper

Key responsibilities:
1. Manage a shared `EKEventStore` instance.
2. Handle the TCC authorization request synchronously using a `DispatchSemaphore`
   (same pattern as `DeskViewSession.ensureCameraAuthorization` in deskview-mcp).
3. Expose typed methods for each operation that map to subcommands.

Authorization flow:
```swift
func ensureCalendarAuthorization() throws {
    // EKAuthorizationStatus changed in macOS 14: use requestFullAccessToEvents
    let status: EKAuthorizationStatus
    if #available(macOS 14.0, *) {
        status = EKEventStore.authorizationStatus(for: .event)
    } else {
        status = EKEventStore.authorizationStatus(for: .event)
    }
    switch status {
    case .fullAccess, .authorized:
        return
    case .notDetermined:
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, _ in granted = ok; sem.signal() }
        } else {
            store.requestAccess(to: .event) { ok, _ in granted = ok; sem.signal() }
        }
        sem.wait()
        if !granted { throw BridgeError.permissionDenied }
    case .denied, .restricted, .writeOnly:
        throw BridgeError.permissionDenied
    @unknown default:
        throw BridgeError.permissionDenied
    }
}
```

Note: macOS 14 (Sonoma) changed the EventKit authorization API. The binary must handle both
macOS 13 (using `requestAccess`) and macOS 14+ (using `requestFullAccessToEvents`). The
`#available` guards handle this.

### `EventMapper.swift` -- EKEvent to/from JSON

Key responsibilities:
1. Convert `EKEvent` to the serializable `EventPayload` struct.
2. Parse ISO 8601 strings to `Date` using `ISO8601DateFormatter` with fractional seconds
   support and timezone offset parsing.
3. Map `EKCalendar.type` (`EKCalendarType`) to a human-readable string.

Date parsing helper:
```swift
static func parseISO(_ s: String) throws -> Date {
    // Try with fractional seconds first, then without.
    let formatters: [ISO8601DateFormatter] = [
        { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
        { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    ]
    for f in formatters {
        if let d = f.date(from: s) { return d }
    }
    throw BridgeError.invalidInput("Cannot parse date: \(s)")
}
```

### `BridgeError.swift` -- Typed errors

```swift
enum BridgeError: Error {
    case permissionDenied
    case notFound(String)
    case invalidInput(String)
    case readOnly(String)
    case saveFailed(String)
    case internalError(String)

    var code: String {
        switch self {
        case .permissionDenied: return "permission_denied"
        case .notFound: return "not_found"
        case .invalidInput: return "invalid_input"
        case .readOnly: return "read_only"
        case .saveFailed: return "save_failed"
        case .internalError: return "internal"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied:
            return "Calendar access denied. Grant access in System Settings, Privacy and Security, Calendars."
        case .notFound(let detail): return "Not found: \(detail)"
        case .invalidInput(let detail): return "Invalid input: \(detail)"
        case .readOnly(let detail): return "Calendar is read-only: \(detail)"
        case .saveFailed(let detail): return "Save failed: \(detail)"
        case .internalError(let detail): return "Internal error: \(detail)"
        }
    }
}
```

### `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICSBridge",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ICSBridge",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ICSBridge"
        ),
        .testTarget(
            name: "ICSBridgeTests",
            dependencies: ["ICSBridge"],
            path: "Tests/ICSBridgeTests"
        )
    ]
)
```

### `build.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ICSBridge for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_DIR="../bin"
mkdir -p "$OUT_DIR"
cp .build/arm64-apple-macosx/release/ICSBridge "$OUT_DIR/ics-bridge"
chmod +x "$OUT_DIR/ics-bridge"

echo "Built: $OUT_DIR/ics-bridge"
```

### Calendar usage description (Info.plist)

The Swift binary needs `NSCalendarsFullAccessUsageDescription` (macOS 14+) and
`NSCalendarsUsageDescription` (macOS 13) in an embedded `Info.plist` so the TCC prompt has
friendly copy. Add to `Package.swift` target resources or embed via a custom build step.
If embedding cleanly proves difficult, the system generic prompt still appears and the user
is still prompted correctly.

Suggested strings:
- `NSCalendarsFullAccessUsageDescription`: `"ICS Calendar reads and writes your calendars so Claude can help you schedule, plan, and manage events."`
- `NSCalendarsUsageDescription`: `"ICS Calendar reads your calendars so Claude can help you schedule and plan."`

---

## 7. Node MCP Server Specification

### `package.json`

```json
{
  "name": "ics-calendar",
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
    "pnpm": ">=11"
  },
  "packageManager": "pnpm@11.2.2"
}
```

**Package manager: pnpm only. Never npm. Never yarn. Lockfile is `pnpm-lock.yaml`.**

### `tsconfig.json`

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

### `src/bridge.ts` -- Swift binary wrapper

Same pattern as `deskview-mcp/src/capture.ts`. Key responsibilities:
1. Resolve binary path from `process.env.ICS_BRIDGE_BIN`.
2. Validate binary exists at startup (return clear error if not).
3. Parse and validate input with Zod before spawning.
4. Spawn via `child_process.spawn` with `{ stdio: ["ignore", "pipe", "pipe"] }`.
5. Pipe stderr to `process.stderr` (Claude Desktop captures extension logs).
6. Parse stdout as JSON `BridgeResult`.
7. Map result to MCP content blocks.
8. Safety kill at `timeout + 5000ms`.

Default timeout: **10000ms** for all read operations. **15000ms** for write operations (create,
update, delete). EventKit operations should complete in well under 1s on a local database.

### `src/schemas.ts` -- Zod + JSON Schema

Define all seven tool input schemas as both Zod schemas (for runtime validation in bridge.ts)
and plain JSON Schema objects (for the `ListToolsRequestSchema` response in index.ts).

All ISO 8601 date inputs should be validated as non-empty strings at the Zod layer. Full
parsing validity is enforced by the Swift binary.

---

## 8. Permissions

### macOS Calendar (TCC)

The Swift binary triggers the standard macOS calendar permission prompt on first access to
`EKEventStore`. The permission lives in `System Settings > Privacy and Security > Calendars`.

There is no programmatic way to re-trigger the prompt once denied. Document this in the README.

The TCC permission is scoped to the binary's path. After reinstalling the extension (which may
place the binary at a different path), macOS may prompt again. This is expected behavior.

### Read-only calendars

Certain calendar types are always read-only and cannot be mutated:
- Subscription calendars (`.subscription` type)
- Birthday calendars (`.birthday` type)
- Some Exchange / shared calendars depending on server permissions

The binary detects `EKCalendar.allowsContentModifications` before any write operation and
returns `read_only` error if false.

---

## 9. License

Use the same noncommercial license structure as `deskview-mcp`. The `LICENSE` file should be
titled "ICS Calendar License" with the same terms: noncommercial use permitted, no
autonomous surveillance, no autonomous weapons, contact for commercial licensing.

Replace "Deskview MCP" and "Deskview MCP License" with "ICS Calendar" and
"ICS Calendar License" throughout. Keep all other terms identical to the deskview-mcp
LICENSE file verbatim.

`PRIVACY.md` should note:
- All calendar data stays on the local machine.
- No data is transmitted to any external server.
- The binary only reads/writes the local EventKit database.
- macOS will prompt for permission; that prompt is controlled entirely by the OS.

---

## 10. Build and Package Process

### `scripts/package.sh`

Identical to `deskview-mcp/scripts/package.sh` -- installs a flat prod-only `node_modules`
(hoisted linker) to survive the `.mcpb` pack/unpack round-trip, packs, and restores dev
`node_modules` on exit. Copy that file verbatim, replacing any project-specific references.

### Local install for testing

1. Claude Desktop: Settings, Extensions, Advanced settings, Extension Developer
2. "Install Extension..." -- select the `.mcpb`
3. Confirm install. Tools appear in the next chat.
4. First tool call triggers the macOS calendar permission prompt.

---

## 11. Testing

### Node unit test matrix (vitest, stub binaries)

| Test | Fixture | Expected |
|---|---|---|
| `list_calendars` returns array of calendars | `stub-calendars.sh` | content[0] is text, parses as JSON with `calendars` array |
| `get_events` returns event array | `stub-events.sh` | content[0] is text, `events` array, each has `id`, `title`, `start`, `end` |
| `create_event` returns new event | `stub-create.sh` | content[0] has `event.id` field |
| `permission_denied` error surfaces clearly | `stub-error.sh` | `isError: true`, text mentions "System Settings" |
| Binary crash (non-JSON stdout) | `stub-crash.sh` | `isError: true`, text mentions "binary" |
| Binary path missing | N/A | `isError: true`, text mentions "not found" |
| Unknown tool name | N/A | `isError: true`, text mentions "unknown" |
| Invalid ISO date string | N/A | `isError: true`, Zod-level rejection |
| `start` after `end` in create | N/A | `isError: true`, validation error |

### Swift unit test matrix (XCTest)

Test pure-function logic that does not require device hardware or TCC permission:

| Test | What it covers |
|---|---|
| `testParseISO_withOffset` | `EventMapper.parseISO` parses `"2026-05-08T09:00:00-07:00"` correctly |
| `testParseISO_withZ` | `EventMapper.parseISO` parses UTC `Z` suffix correctly |
| `testParseISO_rejectsGarbage` | `EventMapper.parseISO` throws on `"not-a-date"` |
| `testCalendarTypeString` | `CalendarStore.typeString` maps all `EKCalendarType` cases |
| `testErrorCodes` | All `BridgeError` cases return the correct `code` string |
| `testResultEncoding_success` | `BridgeResult.success(data:)` encodes without `error_code` |
| `testResultEncoding_error` | `BridgeResult.error(_:)` encodes `status: "error"` correctly |
| `testAvailabilityMerge` | Merging overlapping busy blocks produces correct free slots |

### Manual test matrix (hardware + TCC)

| Scenario | Expected |
|---|---|
| First run, permission not granted | macOS permission prompt appears |
| Permission denied, then call any tool | `isError` text references System Settings |
| All permissions granted, `list_calendars` | Returns actual calendars including iCloud ones |
| `get_events` for current week | Returns real events matching Calendar.app |
| `create_event` with title/start/end | Event appears in Calendar.app within seconds |
| `update_event` changing title | Calendar.app reflects updated title |
| `delete_event` | Event disappears from Calendar.app |
| `get_availability` for a busy day | Busy blocks match visible events |
| `list_calendars` on a machine with no iCloud sign-in | Returns local calendars only, no error |
| Call `create_event` on a subscription calendar | Returns `read_only` error |
| Run `list_calendars` 20 times in quick succession | All complete cleanly, no zombie processes |

---

## 12. Implementation Order (for Claude Code)

Build in this sequence so each step leaves a working, testable state. Do not batch steps.

**Phase 0: Repo scaffold**

1. Create directory structure, `package.json` (pnpm engines), `tsconfig.json`, `manifest.json`,
   `.mcpbignore`, `.gitignore`, `vitest.config.ts`, `LICENSE`, `PRIVACY.md`, empty `README.md`.
   Run `pnpm install`. Commit.

2. Verify pnpm was used: `ls | grep lock` must show only `pnpm-lock.yaml`. No `package-lock.json`.

**Phase 1: Swift CLI skeleton (stub JSON output)**

3. Create `swift/Package.swift` with `swift-argument-parser` dependency. Create all seven
   subcommands in `main.swift`, each printing a hardcoded stub JSON success response and
   exiting 0. Build via `swift/build.sh`. Verify: `./bin/ics-bridge list-calendars | jq .status`
   prints `"success"`.

4. Create `BridgeError.swift`, `OutputJSON.swift` (BridgeResult struct, `emit()`, `logStderr()`),
   and `EventMapper.swift` (stub, just the struct definitions, no EK imports yet).

5. Add Swift unit tests for error codes and JSON encoding. Run `cd swift && swift test`. All pass.

**Phase 2: Node MCP server (stub pipeline end-to-end)**

6. Implement `src/types.ts` and `src/schemas.ts` (all seven tools).

7. Write failing tests in `src/__tests__/bridge.test.ts` using stub shell scripts. Commit
   failing tests.

8. Implement `src/bridge.ts` to make all tests pass. Commit.

9. Implement `src/index.ts` (ListTools + CallTool). Compile. Smoke-test the compiled server
   against the stub Swift binary.

**Phase 3: First bundle install**

10. Run `pnpm package`. Inspect bundle with `unzip -l *.mcpb`. Install in Claude Desktop.
    Confirm all seven tools appear. Call each tool and get stub responses.

**Phase 4: Real EventKit reads**

11. Implement `CalendarStore.swift` with `EKEventStore`, authorization flow (macOS 13 and 14+
    `#available` guard), and `list-calendars` subcommand. Test via Terminal (TCC prompt appears
    on first run). Wire into Claude Desktop.

12. Implement `get-events` and `search-events` subcommands using `EKEventStore.predicateForEvents`
    and in-process text filtering. Test via Terminal and Claude Desktop.

13. Implement `get-availability` subcommand: fetch events in range, sort by start, build busy
    blocks with granularity merge, compute free blocks as gaps. Write Swift unit test for the
    merge logic using synthetic event arrays (no EK required).

**Phase 5: Real EventKit writes**

14. Implement `create-event` subcommand. Test: created event appears in Calendar.app.

15. Implement `update-event` subcommand (patch semantics). Test: updated title/time reflects
    in Calendar.app.

16. Implement `delete-event` subcommand. Test: event disappears from Calendar.app. Test
    read-only calendar rejection.

**Phase 6: QA and polish**

17. Run full manual test matrix from Section 11.

18. Write README (install steps, prerequisites, troubleshooting). Make icon.png (256x256).

19. Final clean build: `pnpm clean && pnpm install && pnpm test && pnpm package`. Tag v1.0.0.
    Cut GitHub release with `.mcpb` attached.

---

## 13. Constraints and Conventions

- **Package manager: pnpm only. Never npm. Never yarn. Lockfile is `pnpm-lock.yaml`.**
- **Manifest version: `0.3`.** Do not downgrade.
- **Node version:** 18 or higher.
- **Swift version:** 5.9 or higher.
- **macOS target:** 13.0 or higher (EventKit full-access API requires 13+; 14+ path handled via `#available`).
- **Architecture:** arm64 only for v1.
- **No em dashes** in any committed text content (README, comments, error messages, manifest
  descriptions). Use commas, parens, or sentence breaks instead.
- **Stdout is sacred** in the Swift binary: only valid JSON goes there. All diagnostics go to stderr.
- **No telemetry, no external network calls.** All calendar data stays local.
- **No bundled secrets or credentials.** EventKit uses OS-level TCC, not passwords.
- **Tool input schemas live in `src/schemas.ts`**, not in `manifest.json`. The manifest only
  lists tool names and one-line descriptions.
- **Variable substitution in manifest:** use `${__dirname}` for bundle-relative paths.
- **`data` field in BridgeResult is always an `Encodable` Swift struct**, not a raw dictionary.
  All fields should be explicitly typed -- no `[String: Any]`.
- **EventKit date handling:** always round-trip dates through ISO 8601 with explicit timezone
  offsets. Never rely on system timezone assumptions.
- **Recurring events in v1:** read them normally (they appear as individual instances in
  EventKit predicates). For write operations, apply changes to the full series via
  `.allEvents` span. Document this limitation clearly in tool descriptions.

---

## 14. Future Enhancements (Out of Scope for v1)

- Single-instance editing of recurring events (`.thisEvent` span in EventKit)
- Alarm/reminder management on events
- Attendee read access (EKParticipant fields)
- Meeting availability polling (check multiple attendees via CalDAV free/busy)
- Natural language date parsing ("next Tuesday at 3pm") -- handled by Claude, not the binary
- Universal binary (arm64 + x86_64) for Intel Mac compatibility
- Reminders integration (separate tool set or separate extension)
- Event template support ("create a standup every weekday at 9am")
- macOS 15 CalendarKit integration for richer event metadata
- Bulk import from ICS/iCal file

---

End of PRD.
