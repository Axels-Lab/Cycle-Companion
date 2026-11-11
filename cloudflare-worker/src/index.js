const FIREBASE_CERTS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FIRESTORE_SCOPE = 'https://www.googleapis.com/auth/datastore';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

let cachedAccessToken;
let cachedAccessTokenExpiresAt = 0;

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const allowedOrigin = origin && isAllowedOrigin(origin, env) ? origin : null;
    const respond = (body, status) => json(body, status, allowedOrigin);

    if (request.method === 'OPTIONS') {
      if (!allowedOrigin) return new Response(null, { status: 403 });
      return new Response(null, {
        status: 204,
        headers: corsHeaders(allowedOrigin),
      });
    }

    if (origin && !allowedOrigin) {
      return new Response(null, { status: 403 });
    }

    if (request.method !== 'POST' || new URL(request.url).pathname !== '/notify') {
      return respond({ error: 'Not found' }, 404);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return respond({ error: 'Invalid request' }, 400);
    }

    try {
      const notificationType = body?.type ?? 'daily_log_updated';
      const validTitle =
        notificationType === 'daily_log_updated'
          ? [
              'Daily entry added',
              'Daily entry updated',
              'Daily entry deleted',
            ].includes(body?.title)
          : notificationType === 'partner_mood_updated' &&
            body?.title === 'Partner mood updated';
      const validMessage =
        typeof body?.message === 'string' &&
        body.message.length > 0 &&
        body.message.length <= 240;
      if (
        !body ||
        typeof body.coupleId !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(body.coupleId) ||
        !['daily_log_updated', 'partner_mood_updated'].includes(notificationType) ||
        !validTitle ||
        !validMessage
      ) {
        return respond({ error: 'Invalid request' }, 400);
      }

      const firebaseProjectId = env.FIREBASE_PROJECT_ID;
      if (!firebaseProjectId) throw new Error('Missing Firebase project configuration.');
      const uid = await verifyFirebaseToken(request, firebaseProjectId);
      const googleToken = await getGoogleAccessToken(env);

      const couple = await getFirestoreDocument(
        firebaseProjectId,
        `couples/${encodeURIComponent(body.coupleId)}`,
        googleToken,
      );
      if (!couple) return respond({ error: 'Pairing not found' }, 404);

      const route = getNotificationRoute(
        notificationType,
        uid,
        couple.members,
        couple.roles ?? {},
      );
      if (route.status !== 200) {
        return respond({ error: route.error }, route.status);
      }

      const recipientUid = route.recipientUid;
      const deviceDocuments = await listDeviceDocuments(
        firebaseProjectId,
        recipientUid,
        googleToken,
      );
      let sent = 0;
      for (const device of deviceDocuments) {
        const token = device.fields?.token?.stringValue;
        if (typeof token !== 'string' || token.length === 0) continue;

        const result = await sendPush(
          firebaseProjectId,
          googleToken,
          token,
          body.title,
          body.message,
          notificationType,
        );
        if (result === 'unregistered') {
          await deleteDeviceDocument(
            firebaseProjectId,
            recipientUid,
            device.name,
            googleToken,
          );
        } else {
          sent++;
        }
      }
      return respond({ sent }, 200);
    } catch (error) {
      console.error(
        'Push notification delivery failed:',
        error instanceof Error ? error.message : 'Unknown error',
      );
      if (error instanceof UnauthorizedError) {
        return respond({ error: 'Unauthorized' }, 401);
      }
      return respond({ error: 'Push notification delivery failed' }, 502);
    }
  },
};

export function getNotificationRoute(notificationType, senderUid, members, roles) {
  const expectedRoles =
    notificationType === 'daily_log_updated'
      ? { sender: 'tracker', recipient: 'partner' }
      : notificationType === 'partner_mood_updated'
        ? { sender: 'partner', recipient: 'tracker' }
        : null;
  if (!expectedRoles) {
    return { status: 400, error: 'Unsupported notification type' };
  }
  if (
    !Array.isArray(members) ||
    !members.includes(senderUid) ||
    roles[senderUid] !== expectedRoles.sender
  ) {
    return {
      status: 403,
      error: `Only the paired ${expectedRoles.sender} can send this notification`,
    };
  }

  const recipients = members.filter(
    (member) =>
      member !== senderUid && roles[member] === expectedRoles.recipient,
  );
  if (recipients.length !== 1) {
    return {
      status: 409,
      error: `Pairing has no single ${expectedRoles.recipient}`,
    };
  }
  return {
    status: 200,
    recipientUid: recipients[0],
  };
}

class UnauthorizedError extends Error {}

async function verifyFirebaseToken(request, projectId) {
  const authorization = request.headers.get('Authorization') ?? '';
  const match = /^Bearer ([^\s]+)$/.exec(authorization);
  if (!match) throw new UnauthorizedError('Missing Firebase authentication token.');

  const parts = match[1].split('.');
  if (parts.length !== 3) throw new UnauthorizedError('Invalid Firebase authentication token.');
  const header = decodeJwtPart(parts[0]);
  const claims = decodeJwtPart(parts[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') {
    throw new UnauthorizedError('Unsupported Firebase authentication token.');
  }

  const response = await fetch(FIREBASE_CERTS_URL, {
    cf: { cacheTtl: 3600, cacheEverything: true },
  });
  if (!response.ok) throw new Error('Could not load Firebase signing keys.');
  const keys = await response.json();
  const jwk = keys.keys?.find((key) => key.kid === header.kid);
  if (!jwk) throw new UnauthorizedError('Firebase signing key not found.');

  const publicKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const signedContent = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const validSignature = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    decodeBase64Url(parts[2]),
    signedContent,
  );
  const now = Math.floor(Date.now() / 1000);
  if (
    !validSignature ||
    claims.iss !== `https://securetoken.google.com/${projectId}` ||
    claims.aud !== projectId ||
    typeof claims.sub !== 'string' ||
    claims.sub.length === 0 ||
    !Number.isFinite(claims.exp) ||
    claims.exp <= now ||
    !Number.isFinite(claims.iat) ||
    claims.iat > now + 60
  ) {
    throw new UnauthorizedError('Invalid or expired Firebase authentication token.');
  }
  return claims.sub;
}

function decodeJwtPart(part) {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(part)));
}

function decodeBase64Url(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function encodeBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function getGoogleAccessToken(env) {
  if (cachedAccessToken && cachedAccessTokenExpiresAt > Date.now() + 60_000) {
    return cachedAccessToken;
  }
  if (!env.FIREBASE_SERVICE_ACCOUNT_EMAIL || !env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new Error('Missing service account secrets.');
  }

  const now = Math.floor(Date.now() / 1000);
  const header = encodeBase64Url(
    new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })),
  );
  const claims = encodeBase64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: env.FIREBASE_SERVICE_ACCOUNT_EMAIL,
        scope: `${FIRESTORE_SCOPE} ${FCM_SCOPE}`,
        aud: GOOGLE_TOKEN_URL,
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsignedAssertion = `${header}.${claims}`;
  const privateKeyPem = env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, '\n');
  const privateKeyBytes = decodeBase64(
    privateKeyPem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, ''),
  );
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedAssertion),
  );
  const assertion = `${unsignedAssertion}.${encodeBase64Url(new Uint8Array(signature))}`;
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const tokenResult = await response.json();
  if (!response.ok || typeof tokenResult.access_token !== 'string') {
    throw new Error('Google service account authentication failed.');
  }

  cachedAccessToken = tokenResult.access_token;
  cachedAccessTokenExpiresAt = Date.now() + tokenResult.expires_in * 1000;
  return cachedAccessToken;
}

function decodeBase64(value) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

async function getFirestoreDocument(projectId, path, accessToken) {
  const response = await fetch(
    firestoreUrl(projectId, path),
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error('Firestore document read failed.');
  const document = await response.json();
  return decodeFields(document.fields ?? {});
}

async function listDeviceDocuments(projectId, uid, accessToken) {
  const documents = [];
  let pageToken;
  do {
    const url = new URL(firestoreUrl(projectId, `users/${encodeURIComponent(uid)}/devices`));
    url.searchParams.set('pageSize', '100');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!response.ok) throw new Error('Recipient device lookup failed.');
    const result = await response.json();
    documents.push(...(result.documents ?? []));
    pageToken = result.nextPageToken;
  } while (pageToken);
  return documents;
}

async function deleteDeviceDocument(projectId, uid, documentName, accessToken) {
  const deviceId = documentName?.split('/').pop();
  if (typeof deviceId !== 'string' || !/^[a-f0-9]{64}$/.test(deviceId)) {
    throw new Error('Invalid device document name.');
  }
  const response = await fetch(
    firestoreUrl(
      projectId,
      `users/${encodeURIComponent(uid)}/devices/${encodeURIComponent(deviceId)}`,
    ),
    { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!response.ok && response.status !== 404) {
    throw new Error('Stale device token cleanup failed.');
  }
}

async function sendPush(
  projectId,
  accessToken,
  token,
  title,
  body,
  notificationType,
) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(
        buildFcmMessage(token, title, body, notificationType),
      ),
    },
  );
  if (response.ok) return 'sent';

  const result = await response.json();
  const isUnregistered =
    response.status === 404 ||
    result.error?.details?.some((detail) => detail.errorCode === 'UNREGISTERED');
  if (isUnregistered) return 'unregistered';
  throw new Error(`FCM rejected a notification with HTTP ${response.status}.`);
}

export function buildFcmMessage(token, title, body, notificationType) {
  return {
    message: {
      token,
      notification: { title, body },
      android: {
        priority: 'HIGH',
        notification: { channel_id: 'tracker_updates' },
      },
      data: { type: notificationType, title, body },
    },
  };
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeField(value)]),
  );
}

function decodeField(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('arrayValue' in value) {
    return (value.arrayValue.values ?? []).map(decodeField);
  }
  if ('mapValue' in value) return decodeFields(value.mapValue.fields ?? {});
  if ('nullValue' in value) return null;
  return undefined;
}

function firestoreUrl(projectId, path) {
  return `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/${path}`;
}

function isAllowedOrigin(origin, env) {
  if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return true;
  const configuredOrigins = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  return configuredOrigins.includes(origin);
}

function corsHeaders(origin) {
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(value, status, origin) {
  const headers = { 'Content-Type': 'application/json; charset=utf-8' };
  if (origin) Object.assign(headers, corsHeaders(origin));
  return new Response(JSON.stringify(value), {
    status,
    headers,
  });
}
