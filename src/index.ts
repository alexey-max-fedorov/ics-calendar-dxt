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
  GetCurrentDatetimeInput,
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
      ...flag('calendar-ids', Array.isArray(a.calendar_ids) && (a.calendar_ids as string[]).length > 0 ? (a.calendar_ids as string[]).join(',') : undefined),
      ...flag('granularity', a.granularity_minutes ?? 30),
    ],
  },
  get_current_datetime: {
    name: 'get_current_datetime',
    description: toolDescriptions.get_current_datetime,
    inputSchema: toolJsonSchemas.get_current_datetime,
    zod: GetCurrentDatetimeInput,
    build: () => ['get-current-datetime'],
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
