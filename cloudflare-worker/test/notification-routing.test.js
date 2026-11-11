import assert from 'node:assert/strict';
import test from 'node:test';

import { buildFcmMessage, getNotificationRoute } from '../src/index.js';

const members = ['tracker-uid', 'partner-uid'];
const roles = { 'tracker-uid': 'tracker', 'partner-uid': 'partner' };

test('daily-log notifications route from tracker to partner', () => {
  assert.deepEqual(
    getNotificationRoute('daily_log_updated', 'tracker-uid', members, roles),
    { status: 200, recipientUid: 'partner-uid' },
  );
});

test('partner mood notifications route from partner to tracker', () => {
  assert.deepEqual(
    getNotificationRoute(
      'partner_mood_updated',
      'partner-uid',
      members,
      roles,
    ),
    { status: 200, recipientUid: 'tracker-uid' },
  );
});

test('a tracker cannot send a partner mood notification', () => {
  assert.equal(
    getNotificationRoute(
      'partner_mood_updated',
      'tracker-uid',
      members,
      roles,
    ).status,
    403,
  );
});

test('a partner cannot send a tracker daily-entry notification', () => {
  assert.equal(
    getNotificationRoute(
      'daily_log_updated',
      'partner-uid',
      members,
      roles,
    ).status,
    403,
  );
});

test('push messages retain Android notification display and include data', () => {
  assert.deepEqual(
    buildFcmMessage(
      'device-token',
      'Partner mood updated',
      'Feeling calm',
      'partner_mood_updated',
    ),
    {
      message: {
        token: 'device-token',
        notification: {
          title: 'Partner mood updated',
          body: 'Feeling calm',
        },
        android: {
          priority: 'HIGH',
          notification: { channel_id: 'tracker_updates' },
        },
        data: {
          type: 'partner_mood_updated',
          title: 'Partner mood updated',
          body: 'Feeling calm',
        },
      },
    },
  );
});
