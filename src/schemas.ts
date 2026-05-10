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

export const GetCurrentDatetimeInput = z.object({}).strict();

export type ListCalendarsArgs = z.infer<typeof ListCalendarsInput>;
export type GetEventsArgs = z.infer<typeof GetEventsInput>;
export type SearchEventsArgs = z.infer<typeof SearchEventsInput>;
export type CreateEventArgs = z.infer<typeof CreateEventInput>;
export type UpdateEventArgs = z.infer<typeof UpdateEventInput>;
export type DeleteEventArgs = z.infer<typeof DeleteEventInput>;
export type GetAvailabilityArgs = z.infer<typeof GetAvailabilityInput>;
export type GetCurrentDatetimeArgs = z.infer<typeof GetCurrentDatetimeInput>;

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
        type: 'integer',
        default: 30,
        minimum: 15,
        maximum: 120,
        description: 'Minimum block size in minutes. Adjacent events closer than this are merged.',
      },
    },
    required: ['start', 'end'],
    additionalProperties: false,
  },
  get_current_datetime: {
    type: 'object',
    properties: {},
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
  get_current_datetime: 'Return the current local date, time, and timezone (the system clock of the machine running the extension).',
} as const;

export type ToolName = keyof typeof toolJsonSchemas;
