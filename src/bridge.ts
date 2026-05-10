import { spawn } from 'node:child_process';
import { existsSync, unlinkSync, readFileSync } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import type { BridgeResult, BridgeErrorCode } from './types.js';

export type BridgeOutcome =
  | { status: 'success'; data: unknown }
  | { status: 'error'; error_code: BridgeErrorCode | 'internal'; error_message: string };

interface CallOptions {
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 10_000;

export async function callBridge(args: string[], opts: CallOptions = {}): Promise<BridgeOutcome> {
  const bin = process.env.ICS_BRIDGE_BIN;
  if (!bin) {
    return {
      status: 'error',
      error_code: 'internal',
      error_message: 'ICS_BRIDGE_BIN environment variable is not set.',
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

  return new Promise<BridgeOutcome>(async (resolveResult) => {
    const tmpDir = os.tmpdir();
    const id = `${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const stdoutPath = path.join(tmpDir, `ics-bridge-stdout-${id}.json`);
    const stderrPath = path.join(tmpDir, `ics-bridge-stderr-${id}.log`);

    let settled = false;
    const settle = (out: BridgeOutcome) => {
      if (settled) return;
      settled = true;
      // Best-effort cleanup
      try { unlinkSync(stdoutPath); } catch { /* noop */ }
      try { unlinkSync(stderrPath); } catch { /* noop */ }
      resolveResult(out);
    };

    const openArgs = [
      '-W',
      '-a', bin,
      '-n',
      `--stdout=${stdoutPath}`,
      `--stderr=${stderrPath}`,
      '--args',
      ...args,
    ];
    const child = spawn('open', openArgs, { stdio: ['ignore', 'pipe', 'pipe'] });

    let openStderr = '';
    child.stderr.on('data', (chunk) => { openStderr += chunk.toString('utf8'); });

    const killTimer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch { /* noop */ }
      settle({
        status: 'error',
        error_code: 'internal',
        error_message: `Bridge binary timed out after ${timeoutMs}ms.`,
      });
    }, timeoutMs);

    child.on('error', (err) => {
      clearTimeout(killTimer);
      settle({
        status: 'error',
        error_code: 'internal',
        error_message: `Bridge open() failed to spawn: ${err.message}`,
      });
    });

    child.on('close', (code) => {
      clearTimeout(killTimer);
      let stdout = '';
      let stderr = '';
      try { stdout = readFileSync(stdoutPath, 'utf8'); } catch { /* may not exist */ }
      try { stderr = readFileSync(stderrPath, 'utf8'); } catch { /* may not exist */ }
      // Forward bridge stderr to host stderr so users see Swift diagnostics
      if (stderr) process.stderr.write(stderr);

      if (code !== 0 && !stdout) {
        settle({
          status: 'error',
          error_code: 'internal',
          error_message: `open exited ${code}: ${(openStderr + stderr).trim().slice(0, 500)}`,
        });
        return;
      }

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
