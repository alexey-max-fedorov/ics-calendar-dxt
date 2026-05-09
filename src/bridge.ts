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
    }, timeoutMs);

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
