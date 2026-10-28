// Headless check of the WebAssembly UI, without a browser.
//
//   node web/smoke-node.cjs [dist-dir]
//
// Loads uvl.js, steps one frame, reads the accessibility tree, clicks the
// first tap target, and checks that the ping counter moved.
const path = require('path');

const dist = path.resolve(process.argv[2] || path.join(__dirname, 'dist'));
const createUVL = require(path.join(dist, 'uvl.js'));

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

(async () => {
  const m = await createUVL();
  if (m._uvl_init(480, 360) !== 1) fail('uvl_init failed');
  const stepped = m._uvl_step(0, 0, 16);
  if (stepped !== 1) fail(`expected a first frame, got ${stepped}`);
  const before = m.UTF8ToString(m._uvl_semantics());
  if (!before.includes('vlab')) fail(`semantics missing vlab:\n${before}`);
  if (!before.includes('pings 0')) fail(`semantics missing pings 0:\n${before}`);
  const center = m._uvl_target_center(0);
  if (!center) fail('no tap target');
  const x = m.HEAPF64[center / 8];
  const y = m.HEAPF64[center / 8 + 1];
  const ev = m._malloc(2 * 5 * 8);
  const f = ev / 8;
  // pointer down, then pointer up, button 1
  m.HEAPF64[f] = 2; m.HEAPF64[f + 1] = x; m.HEAPF64[f + 2] = y; m.HEAPF64[f + 3] = 1; m.HEAPF64[f + 4] = 0;
  m.HEAPF64[f + 5] = 3; m.HEAPF64[f + 6] = x; m.HEAPF64[f + 7] = y; m.HEAPF64[f + 8] = 1; m.HEAPF64[f + 9] = 0;
  m._uvl_step(ev, 2, 16);
  m._free(ev);
  const after = m.UTF8ToString(m._uvl_semantics());
  if (!after.includes('pings 1')) fail(`click did not increment:\n${after}`);
  const pixels = m._uvl_render_cpu();
  const w = m._uvl_width();
  const h = m._uvl_height();
  if (!pixels || w !== 480 || h !== 360) fail(`frame ${w}x${h} ptr ${pixels}`);
  let ink = 0;
  const view = m.HEAPU8.subarray(pixels, pixels + w * h * 4);
  for (let i = 0; i < view.length; i += 16) {
    if (view[i] !== 0xf4 || view[i + 1] !== 0xf6 || view[i + 2] !== 0xf8) ink++;
  }
  if (ink < 20) fail(`frame looks empty (${ink} sampled pixels differ from the background)`);
  console.log(`wasm smoke ok ${w}x${h} ink=${ink}`);
})().catch((e) => fail(e && e.stack ? e.stack : String(e)));
