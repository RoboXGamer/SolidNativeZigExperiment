// Opt-in measurements. UTF-8 content accounting is separate from sampled V8
// heap/RSS; it does not pretend to measure JS object/AST allocator overhead.
export function createProducerMetrics() {
  const baseline = process.memoryUsage(), started = performance.now();
  const cpuBefore = process.cpuUsage();
  const values = { attempts: 0, completedCompiles: 0, discarded: 0, failures: 0, publications: 0, modules: 0, fetchedUtf8Bytes: 0, compiledUtf8Bytes: 0, active: 0, peakActive: 0, peakPendingRequests: 0, peakGraphUtf8Bytes: 0, peakPayloadUtf8Bytes: 0, peakRetainedUtf8Bytes: 0, heapBeforeBytes: baseline.heapUsed, rssBeforeBytes: baseline.rss, sampledPeakHeapBytes: baseline.heapUsed, sampledPeakRssBytes: baseline.rss, taskWallMs: 0 };
  function sample() { const memory = process.memoryUsage(); values.sampledPeakHeapBytes = Math.max(values.sampledPeakHeapBytes, memory.heapUsed); values.sampledPeakRssBytes = Math.max(values.sampledPeakRssBytes, memory.rss); }
  return {
    begin() { values.attempts++; values.active++; values.peakActive = Math.max(values.peakActive, values.active); sample(); },
    end(ms) { values.active--; values.taskWallMs += ms; sample(); },
    request() { values.peakPendingRequests = 1; },
    module({ sourceBytes, compiledBytes, retainedGraphBytes }) {
      values.modules++; values.fetchedUtf8Bytes += sourceBytes; values.compiledUtf8Bytes += compiledBytes;
      values.peakGraphUtf8Bytes = Math.max(values.peakGraphUtf8Bytes, retainedGraphBytes); sample();
    },
    prepared(graphBytes, payloadBytes) { values.completedCompiles++; values.peakPayloadUtf8Bytes = Math.max(values.peakPayloadUtf8Bytes, payloadBytes); values.peakRetainedUtf8Bytes = Math.max(values.peakRetainedUtf8Bytes, graphBytes + payloadBytes); sample(); },
    discard() { values.discarded++; },
    fail() { values.failures++; },
    published() { values.publications++; sample(); },
    snapshot() { sample(); const cpu = process.cpuUsage(cpuBefore); return { ...values, cpuUserUs: cpu.user, cpuSystemUs: cpu.system, elapsedMs: performance.now() - started, pendingGraphCapacity: 0, latestRequestCapacity: 1 }; },
  };
}
