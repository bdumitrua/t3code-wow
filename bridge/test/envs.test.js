import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { remoteT3 } from '../src/envs.js';

// Run the command mintRemote sends over SSH in a made-up home, with no t3 on PATH.
function runRemote(home) {
  return spawnSync('sh', ['-c', remoteT3('--version')], { encoding: 'utf8', env: { HOME: home, PATH: '/usr/bin:/bin' } });
}

function fakeT3(home, rel, says) {
  const file = path.join(home, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `#!/bin/sh\necho "${says} $*"\n`, { mode: 0o755 });
}

const skip = process.platform === 'win32' && 'needs a POSIX shell, as on the remote machines';

test('finds a headless server\'s t3 under its newest runtime version', { skip }, () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-env-'));
  try {
    fakeT3(home, '.t3/runtime/versions/0.1.9/t3', 'runtime 0.1.9');
    fakeT3(home, '.t3/runtime/versions/0.1.10/t3', 'runtime 0.1.10');
    assert.equal(runRemote(home).stdout.trim(), 'runtime 0.1.10 --version');
    // The desktop app's CLI, when there is one, comes first.
    fakeT3(home, '.t3/bin/t3', 'desktop');
    assert.equal(runRemote(home).stdout.trim(), 'desktop --version');
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test('says so when the machine has no t3 at all', { skip }, () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-env-'));
  try {
    const r = runRemote(home);
    assert.equal(r.status, 127);
    assert.match(r.stderr, /t3 not found on this machine/);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
