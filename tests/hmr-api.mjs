import assert from 'node:assert/strict';
import * as native from '../packages/solid-zig/src/native.js';
import * as solid from 'solid-js';
import * as renderer from '../packages/solid-zig/src/renderer.js';
globalThis.__NATIVE_HMR__ = true;
try {
  native.mountApp(() => renderer.createElement('label'));
  globalThis.__hmrExpected = { native, solid, renderer };
  globalThis.__uiModules.apply({ app: `
    const expected = globalThis.__hmrExpected;
    const api = require('native-host');
    for (const key of Object.keys(expected.native)) {
      if (api[key] !== expected.native[key]) throw Error('API mismatch: ' + key);
    }
    if (require('solid-js') !== expected.solid) throw Error('duplicate Solid');
    if (require('native-renderer') !== expected.renderer) throw Error('duplicate renderer');
    if (typeof api.findById !== 'function') throw Error('missing findById');
  ` }, 'app');
} finally {
  globalThis.uiDispose();
  delete globalThis.__hmrExpected;
  delete globalThis.__uiModules;
  delete globalThis.__NATIVE_HMR__;
}
console.log('Actual HMR host API and runtime identity parity passed');
