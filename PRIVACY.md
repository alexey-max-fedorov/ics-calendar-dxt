# Privacy Policy

ICS Calendar is an MCP server that runs entirely on your local machine.

## Data handling

- All calendar data stays on the local machine. Nothing is transmitted to any external server.
- The bundled Swift binary reads and writes the local EventKit database, the same database that Calendar.app uses.
- iCloud, Google, and Exchange syncing is performed by the macOS Calendar service, not by this extension. This extension never sees your iCloud, Google, or Exchange credentials.
- No telemetry, analytics, or crash reports are sent.
- macOS will prompt you for calendar permission on first use. That prompt is controlled entirely by the operating system. You can revoke access in System Settings, Privacy and Security, Calendars.

## Permissions

ICS Calendar requests full access to your calendars (read and write). Without that permission the extension cannot list events or create new ones. There is no "read only" mode in v1.

## Contact

Questions or concerns: alexey.max.fedorov@gmail.com
