import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { purgeExpiredMotionData } = require('../.tmp-test-dist/lib/motion_privacy.js');

// The 90-day retention promise in the public Privacy Policy is only true if
// this purge actually selects old artifacts, deletes their R2 objects, and
// removes their D1 rows. Fake D1 emulates the `datetime('now','-90 days')`
// cutoff in JS.
function makeFake() {
  const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const sessions = [
    { session_id: 'ms_old', user_id: 'ref1', object_key: 'motion-sessions/old.bin', created_at: '2020-01-01 00:00:00' },
    { session_id: 'ms_new', user_id: 'ref1', object_key: 'motion-sessions/new.bin', created_at: new Date().toISOString() },
  ];
  const training = [
    { id: 'te_old', user_id: 'ref1', object_key: 'motion-training/old.bin', created_at: '2020-01-01 00:00:00' },
    { id: 'te_new', user_id: 'ref1', object_key: 'motion-training/new.bin', created_at: new Date().toISOString() },
  ];
  const feedback = [
    { id: 'fb1', motion_session_id: 'ms_old', user_id: 'ref1' },
    { id: 'fb2', motion_session_id: 'ms_new', user_id: 'ref1' },
  ];
  const deletedObjects = [];

  const DB = {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let args = [];
      return {
        bind(...a) { args = a; return this; },
        async run() {
          if (q.startsWith('DELETE FROM motion_feedback_labels')) {
            for (let i = feedback.length - 1; i >= 0; i--) {
              if (feedback[i].motion_session_id === args[0] || feedback[i].user_id === args[0]) feedback.splice(i, 1);
            }
          }
          if (q.startsWith('DELETE FROM motion_sessions')) {
            for (let i = sessions.length - 1; i >= 0; i--) {
              if (sessions[i].session_id === args[0]) sessions.splice(i, 1);
            }
          }
          if (q.startsWith('DELETE FROM motion_training_examples')) {
            for (let i = training.length - 1; i >= 0; i--) {
              if (training[i].id === args[0]) training.splice(i, 1);
            }
          }
          return { success: true };
        },
        async all() {
          if (q.includes('FROM motion_sessions')) {
            if (q.includes("-90 days")) {
              return { results: sessions.filter((s) => s.created_at < cutoff).map(({ session_id, object_key }) => ({ session_id, object_key })) };
            }
            return { results: sessions };
          }
          if (q.includes('FROM motion_training_examples')) {
            if (q.includes("-90 days")) {
              return { results: training.filter((t) => t.created_at < cutoff).map(({ id, object_key }) => ({ id, object_key })) };
            }
            return { results: training };
          }
          return { results: [] };
        },
        async first() { return null; },
      };
    },
  };
  const R2 = { async delete(key) { deletedObjects.push(key); } };
  return { DB, R2, sessions, training, feedback, deletedObjects };
}

test('90-day purge deletes old sessions, examples, R2 objects, and feedback — keeps recent', async () => {
  const { DB, R2, sessions, training, feedback, deletedObjects } = makeFake();
  const result = await purgeExpiredMotionData(DB, R2);

  assert.deepEqual(result, { sessions: 1, trainingExamples: 1 });
  assert.deepEqual(deletedObjects.sort(), ['motion-sessions/old.bin', 'motion-training/old.bin']);
  assert.deepEqual(sessions.map((s) => s.session_id), ['ms_new']);
  assert.deepEqual(training.map((t) => t.id), ['te_new']);
  assert.deepEqual(feedback.map((f) => f.id), ['fb2']);
});
