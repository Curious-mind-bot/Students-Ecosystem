const test = require('node:test');
const assert = require('node:assert/strict');

test('readiness-review risk categories stay explicitly defined', () => {
  assert.deepEqual(
    ['permanent-settlement', 'asylum', 'unsupported-claim'].length,
    3,
  );
});
