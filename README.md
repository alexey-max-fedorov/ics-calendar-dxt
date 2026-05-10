# ICS Calendar

A Claude Desktop Extension that gives Claude full read and write access to your macOS Calendar (including any iCloud, Google, or Exchange calendars visible in Calendar.app) via Apple's native EventKit framework.

No app-specific passwords. No CalDAV. No credential storage. The extension reads and writes the same local Calendar database that Calendar.app uses.

## Requirements

- macOS 13.0 (Ventura) or later, Apple Silicon (arm64)
- Claude Desktop 1.0.0 or later
- Calendar.app set up with at least one calendar (iCloud, Google, Exchange, or local)

## Installation

1. Download the latest `ics-calendar-dxt.mcpb` from the GitHub Releases page.
2. Open Claude Desktop, go to Settings, Extensions, Advanced settings, Extension Developer.
3. Click "Install Extension..." and pick the `.mcpb` file.
4. The first time Claude calls a calendar tool, macOS will prompt for permission. Click "Allow Full Access".

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
| `get_current_datetime` | Return the host machine's current local date, time, and timezone |

All event timestamps are emitted in your local timezone with offset (e.g. `2026-05-09T15:00:00-07:00`), so Claude can read them without timezone math.

## Troubleshooting

### "Calendar access denied"

macOS denied calendar permission, or you have not granted it yet. Open System Settings, Privacy and Security, Calendars, and turn on the toggle for "ICS Calendar Bridge".

If the toggle is missing, the OS has not asked yet. Quit Claude Desktop fully (Cmd+Q), relaunch, and call any calendar tool to trigger the prompt.

### "Bridge binary not found"

The `.mcpb` did not unpack correctly. Reinstall it from Settings, Extensions.

### Calendar changes are not visible immediately

EventKit syncs through the macOS Calendar service. iCloud changes can take a few seconds to propagate.

## Privacy

See PRIVACY.md. All calendar data stays on your local machine. No telemetry. No network calls.

## License

See LICENSE. Noncommercial use only; contact the author for commercial licensing.

## Build from source

Requirements: Node 18+, pnpm 9, Swift 5.9+, Xcode command line tools.

```bash
pnpm install
pnpm build
pnpm test
pnpm package    # produces ics-calendar-dxt.mcpb
```
