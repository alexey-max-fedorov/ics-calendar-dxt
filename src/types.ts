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
