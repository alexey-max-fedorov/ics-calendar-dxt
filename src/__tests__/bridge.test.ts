import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = resolve(here, 'fixtures');

import { callBridge, BridgeOutcome } from '../bridge.js';

function withBin(p: string, fn: () => Promise<void>) {
  return async () => {
    const prev = process.env.ICS_BRIDGE_BIN;
    process.env.ICS_BRIDGE_BIN = p;
    try {
      await fn();
    } finally {
      if (prev === undefined) delete process.env.ICS_BRIDGE_BIN;
      else process.env.ICS_BRIDGE_BIN = prev;
    }
  };
}

describe('callBridge', () => {
  it('returns parsed success payload from list-calendars', withBin(
    resolve(fixtures, 'stub-calendars.app'),
    async () => {
      const out: BridgeOutcome = await callBridge(['list-calendars']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).calendars).toHaveLength(1);
      expect((out.data as any).calendars[0].title).toBe('Personal');
    }
  ));

  it('returns parsed events payload', withBin(
    resolve(fixtures, 'stub-events.app'),
    async () => {
      const out = await callBridge(['get-events', '--start', 'a', '--end', 'b']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).events[0].id).toBe('ev-1');
    }
  ));

  it('returns parsed create payload', withBin(
    resolve(fixtures, 'stub-create.app'),
    async () => {
      const out = await callBridge(['create-event']);
      expect(out.status).toBe('success');
      if (out.status !== 'success') throw new Error('unreachable');
      expect((out.data as any).event.id).toBe('new-ev-1');
    }
  ));

  it('surfaces permission_denied as a structured error', withBin(
    resolve(fixtures, 'stub-error.app'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_code).toBe('permission_denied');
      expect(out.error_message).toMatch(/System Settings/);
    }
  ));

  it('surfaces non-JSON stdout as an internal error', withBin(
    resolve(fixtures, 'stub-crash.app'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_code).toBe('internal');
      expect(out.error_message.toLowerCase()).toMatch(/binary|parse|json/);
    }
  ));

  it('errors clearly when ICS_BRIDGE_BIN is missing', withBin(
    resolve(fixtures, 'does-not-exist.app'),
    async () => {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_message.toLowerCase()).toMatch(/not found|missing/);
    }
  ));

  it('errors when ICS_BRIDGE_BIN env var is unset', async () => {
    const prev = process.env.ICS_BRIDGE_BIN;
    delete process.env.ICS_BRIDGE_BIN;
    try {
      const out = await callBridge(['list-calendars']);
      expect(out.status).toBe('error');
      if (out.status !== 'error') throw new Error('unreachable');
      expect(out.error_message.toLowerCase()).toMatch(/ics_bridge_bin/);
    } finally {
      if (prev !== undefined) process.env.ICS_BRIDGE_BIN = prev;
    }
  });
});
