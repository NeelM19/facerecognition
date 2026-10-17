# Face Attendance API — Backend Developer Prompt

Copy-paste this document to the backend team for `easyPagarEnterpriseApi`.

This document covers **backend APIs only**: endpoints, request bodies, responses, DB, server matching, **server-side PAD**, **liveness challenge nonce**, multi-frame PAD attestation, depth attestation (iOS TrueDepth), and **geo / device binding**.

---

## Context (locked decisions)

| Decision | Choice |
|----------|--------|
| Punch storage | **New Face DB only** now; schema includes hooks for later sync to `employeeAttendence` |
| Match authority | **Server re-verifies** live 192-d MobileFaceNet embedding vs stored clear/mask templates (do **not** trust client `matched`) |
| Liveness / PAD | Client runs blink+turn + MiniFASNetV2; server **requires** attestation **and** **re-runs PAD** on `livePhotoBase64` (do **not** trust client `pad.passed` alone) |
| Challenge binding | Server issues a short-lived **nonce** before punch; punch must return it or reject |
| Depth | Client may send iOS TrueDepth Z-variance; server stores + enforces **only when `supported: true`** |
| Geo / device | Optional org geofence + device binding + failed-punch rate limit |
| Backend | `easyPagarEnterpriseApi` (Express + native Mongo + JWT + `orgId`) |

**Do not reuse / break:** existing AWS Rekognition (`/attendance/setImage`, `/attendance/getUserByImage`) or Hikvision `/biometric/*`. This is a **new module**.

---

## Goal

Build a **Mobile Face Attendance** module that:

1. Stores face templates and punches in a **dedicated MongoDB database**.
2. Supports **clear + mask** enrollments (MobileFaceNet 192-d embeddings).
3. Performs **server-side face verification** on every punch.
4. Issues a **liveness challenge nonce**, then requires it on punch.
5. Runs **server-side MiniFASNet PAD** on the punch still (stops forged client PAD JSON).
6. Accepts **multi-frame PAD** + optional **TrueDepth** attestation from the app.
7. Optionally enforces **geofence / device binding / rate limits**.
8. Exposes history + report APIs; leaves hooks for Phase-2 sync to main attendance.

---

## Stack constraints

- Repo: `easyPagarEnterpriseApi`
- Node ESM + Express, native `mongodb` driver (no Mongoose)
- Base path: `/api/v1/faceAttendance/...`
- Auth header: `Authorization: Bearer <JWT>`
- Middleware chain: `auth.isAuth` → `user.isUserValid` → `auth.setResponseHeaders`
  - Tenant = `request.body.user.orgId`
  - Identity = `userId` = Mongo user `_id` from JWT
- Response envelope: `{ status, message [, data] }` via `helper/apiResponse.js`
- Validation: Celebrate + Joi in `helper/validationSchema.js`
- Prefer **POST** for all endpoints

### Recommended npm packages (server PAD + images + crypto)

Add to `easyPagarEnterpriseApi` (pick **one** PAD runtime — prefer ONNX):

| Package | Purpose |
|---------|---------|
| **`onnxruntime-node`** | Run MiniFASNetV2 **ONNX** on CPU (recommended for Linux servers) |
| **`sharp`** | Decode JPEG base64 → resize/crop → raw BGR/RGB buffers for PAD |
| **`uuid`** | Challenge `nonce` generation (`uuid` v4) |
| **`crypto`** (Node built-in) | HMAC of nonce (optional signed challenge) |
| **`ioredis`** or in-memory Map | Store active challenges + rate-limit counters (Redis preferred in multi-instance) |
| **`@turf/turf`** or `@turf/boolean-point-in-polygon` | Optional geofence check on `geoJson` |
| **`joi`** / Celebrate | Already used — extend schemas for nested `pad` / `depth` / `challenge` |

**Alternative PAD runtimes (if you prefer TFLite):**

| Package | Notes |
|---------|--------|
| `@tensorflow/tfjs-node` | Heavier; convert MiniFASNet to TF.js or use SavedModel |
| `node-tfjs` / custom C++ addon | Avoid unless you already run TFLite in Node |

**Model asset (commit under `assets/faceAttendance/models/`):**

- Preferred: convert MiniFASNetV2 (`2.7_80x80`) to **ONNX** once, ship `silentface.onnx`
- Source weights: [minivision-ai/Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) (Apache-2.0)
- Client TFLite reference: [litert-community/Silent-Face-Anti-Spoofing-LiteRT](https://huggingface.co/litert-community/Silent-Face-Anti-Spoofing-LiteRT) (`silentface.tflite`)

**PAD preprocess (must match training):**

- Face crop scales **2.7** and **4.0** (ensemble average of class probs)
- Resize **80×80**, **BGR**, float values **0..255** (Silent-Face `ToTensor` does **not** divide by 255)
- Output: 3-class softmax; **class 1 = live**; require `argmax === 1` and `liveScore >= padMinLiveScore`

### Folder layout

| Path | Purpose |
|------|---------|
| `config/faceAttendanceDb.js` | Separate Mongo connection |
| `routes/faceAttendance.js` | Router |
| `routes/apiRoute.js` | Mount as `/faceAttendance` |
| `controllers/faceAttendance/*.js` | Business logic |
| `models/faceAttendance/*.js` | DB access |
| `helper/faceEmbeddingMath.js` | Cosine / Euclidean / L2-normalize |
| `helper/faceLivenessPolicy.js` | Client attestation + nonce + freshness |
| `helper/facePadServer.js` | Server MiniFASNet ONNX inference via `onnxruntime-node` + `sharp` |
| `helper/faceChallengeStore.js` | Nonce create / consume (Mongo or Redis) |
| `helper/faceGeoDevicePolicy.js` | Geofence, device bind, rate limit |
| `helper/validationSchema.js` | Joi schemas |
| `assets/faceAttendance/models/silentface.onnx` | PAD model |

---

## Separate database

Same pattern as `config/trackingDb.js`:

```env
FACE_MONGO_HOSTNAME=
FACE_MONGO_PORT=
FACE_MONGO_DBNAME=faceAttendance

# Optional Redis for challenges + rate limits
FACE_REDIS_URL=redis://127.0.0.1:6379

# Anti-spoof
FACE_PAD_MODEL_PATH=./assets/faceAttendance/models/silentface.onnx
FACE_PAD_MIN_LIVE_SCORE=0.70
FACE_CHALLENGE_TTL_SECONDS=90
FACE_PUNCH_RATE_LIMIT_WINDOW_SECONDS=300
FACE_PUNCH_RATE_LIMIT_MAX_FAILS=8
```

`config/faceAttendanceDb.js` exports `connectFaceAttendanceDb()`.

All face collections live **only** in this DB.

---

## Collections

### 1) `faceEnrollments` (one active enrollment per user per org)

```js
{
  _id: ObjectId,
  orgId: ObjectId,
  userId: ObjectId,
  employeeId: String,
  displayName: String,

  clearEmbedding: [Number],           // required, length 192
  maskedEmbedding: [Number] | null,   // optional, length 192
  appearanceEmbeddings: [[Number]],   // optional, max 8 × 192

  clearPhotoPath: String | null,

  modelName: "MobileFaceNet",
  embeddingDim: 192,
  enrolledAt: Date,
  updatedAt: Date,
  isActive: true,

  enrollPadLiveScore: Number | null,
  enrollPadPassed: Boolean | null,
  enrollPadServerLiveScore: Number | null,  // if server PAD run on enroll photo

  // Device binding (optional product policy)
  boundDeviceIds: [String],           // empty = any device allowed
  lastDeviceId: String | null,

  syncToMainAttendanceEnabled: false,
  lastSyncedAt: null
}
```

**Indexes**

- `{ orgId: 1, userId: 1 }` unique partial where `isActive: true`
- `{ orgId: 1, employeeId: 1 }`

### 2) `facePunches`

```js
{
  _id: ObjectId,
  orgId: ObjectId,
  userId: ObjectId,
  employeeId: String | null,
  type: "checkIn" | "checkOut",
  transactionDate: Date,
  serverReceivedAt: Date,

  matched: Boolean,
  similarity: Number,
  distance: Number,
  matchedTemplate: "clear" | "masked" | "appearance" | null,
  matchThresholdUsed: Number,
  distanceThresholdUsed: Number,

  liveEmbedding: [Number],
  livePhotoPath: String | null,

  challengeNonce: String | null,      // consumed nonce
  challengeId: ObjectId | null,

  liveness: {
    passed: Boolean,
    method: "blinkAndHeadTurn" | null,
    challenges: ["blink", "turnLeft" | "turnRight"],
    completedAt: Date | null,
    durationMs: Number | null
  },

  // Client multi-frame PAD (attest) + server PAD (authoritative for spoof)
  pad: {
    passed: Boolean,                  // client claim
    liveScore: Number,
    argmax: Number,
    model: "MiniFASNetV2",
    minLiveScoreUsed: Number,
    frames: [                         // multi-frame client scores
      { liveScore: Number, argmax: Number, at: Date }
    ]
  },
  padServer: {
    passed: Boolean,
    liveScore: Number,
    argmax: Number,
    model: "MiniFASNetV2-ONNX",
    scalesUsed: [2.7, 4.0]
  },

  // iOS TrueDepth (optional; enforce only when supported)
  depth: {
    supported: Boolean,
    passed: Boolean | null,
    stdDevMeters: Number | null,
    frames: Number | null,
    source: "TrueDepth" | "none" | null
  },

  deviceId: String | null,
  appVersion: String | null,
  geoJson: { type: "Point", coordinates: [lng, lat] } | null,
  rejectReason: String | null,

  syncedToMainAttendance: false,
  mainAttendanceId: null,
  syncError: null
}
```

**Indexes**

- `{ orgId: 1, userId: 1, transactionDate: -1 }`
- `{ orgId: 1, transactionDate: -1 }`
- `{ orgId: 1, type: 1, transactionDate: -1 }`
- `{ orgId: 1, userId: 1, matched: 1, serverReceivedAt: -1 }` (rate-limit queries)

### 3) `faceChallenges` (liveness nonce store — or use Redis instead)

```js
{
  _id: ObjectId,
  orgId: ObjectId,
  userId: ObjectId,
  nonce: String,                      // uuid v4
  requiredSteps: ["blink", "turnLeft"] | ["blink", "turnRight"] | ...,
  // Randomize step order + turn direction on create
  expiresAt: Date,                    // now + FACE_CHALLENGE_TTL_SECONDS (default 90s)
  consumedAt: Date | null,
  createdAt: Date,
  deviceId: String | null
}
```

**Indexes**

- `{ nonce: 1 }` unique
- `{ orgId: 1, userId: 1, expiresAt: 1 }`
- TTL index on `expiresAt` if Mongo TTL preferred

### 4) `faceMatchConfig` (optional org overrides)

Default **match** thresholds:

| Gate | Cosine min | Euclidean max |
|------|------------|---------------|
| clear ↔ clear (and appearance) | 0.72 | 0.85 |
| masked ↔ masked | 0.70 | 0.88 |
| clear template ↔ occluded live (only if no mask enrolled) | 0.68 | 0.92 |

Default **anti-spoof / policy** (overridable per org):

| Gate | Default |
|------|---------|
| Require challenge nonce | **yes** |
| Require `liveness.passed` | **yes** |
| Require client `pad.passed` | **yes** (still re-check on server) |
| Require `livePhotoBase64` | **yes** |
| Run **server PAD** | **yes** |
| Min client / server `pad.liveScore` | **0.70** |
| Multi-frame PAD: min frames | **2** |
| Multi-frame: all frames `argmax === 1` | **yes** |
| Multi-frame: min mean liveScore | **0.70** |
| Max age `liveness.completedAt` vs `transactionDate` | **10s** |
| Depth: if `depth.supported === true` require `passed` | **yes** |
| Depth min `stdDevMeters` (hint only; client already gates) | **0.004** |
| Geofence enabled | **no** (opt-in per org) |
| Bound devices only | **no** (opt-in; empty `boundDeviceIds` = allow all) |
| Failed punch rate limit | **8 fails / 5 min / user** |

Example org config document:

```js
{
  orgId: ObjectId,
  padMinLiveScore: 0.70,
  requireServerPad: true,
  requireChallengeNonce: true,
  requireLivePhoto: true,
  multiFramePadMin: 2,
  geofence: {
    enabled: false,
    // GeoJSON Polygon of allowed sites (lng, lat)
    polygon: null,
    maxDistanceMeters: null   // or use circle center + radius instead of polygon
  },
  deviceBinding: {
    enabled: false,
    maxDevices: 2
  },
  rateLimit: {
    failWindowSeconds: 300,
    maxFails: 8
  }
}
```

---

## Anti-spoof architecture (server + client)

```text
1) POST /liveness/challenge  →  { nonce, requiredSteps, expiresAt }
2) App: blink + turn (prefer matching requiredSteps) + TrueDepth if iOS
3) App: multi-frame PAD on 2–3 stills
4) POST /punch {
     challengeNonce, liveEmbedding, livePhotoBase64,
     liveness, pad.frames, depth?, geoJson?, deviceId
   }
5) Server:
     consume nonce (single use)
     → geo / device / rate-limit
     → client attestation policy
     → SERVER PAD on livePhotoBase64  (authoritative spoof gate)
     → embedding match (authoritative identity gate)
     → write checkIn/checkOut
```

| Attack | Mitigation |
|--------|------------|
| Forge `pad.passed: true` JSON | **Server PAD** on photo |
| Replay old successful punch payload | **Nonce** single-use + TTL |
| Flat photo / phone tilt (iPhone) | Client **TrueDepth**; server enforces when `supported` |
| One lucky PAD frame | **Multi-frame PAD** mean + all live |
| Remote punch / shared phone | **Geofence** + **device bind** + **rate limit** |

---

## Server punch pipeline (mandatory)

On every `POST .../punch`:

1. Load enrollment for `orgId` + `userId`. Missing → `404` `"Face not enrolled"`.
2. **Rate limit** failed punches for this user (`faceGeoDevicePolicy.js`). Exceeded → `429` / `400` `RATE_LIMITED`.
3. **Consume challenge nonce** (`faceChallengeStore.js`):
   - Exists, not expired, not consumed, same `orgId`+`userId`
   - Mark `consumedAt = now`
   - Fail → `400` `CHALLENGE_INVALID` | `CHALLENGE_EXPIRED` | `CHALLENGE_REQUIRED`
4. **Device binding** (if enabled): `deviceId` must be in `boundDeviceIds` (or allow first bind). Fail → `DEVICE_NOT_ALLOWED`.
5. **Geofence** (if enabled): `geoJson` required and inside polygon / radius. Fail → `GEO_REQUIRED` | `GEO_OUT_OF_RANGE`.
6. **Client attestation** (`faceLivenessPolicy.js`):
   - `liveness.passed === true`, freshness ≤ 10s
   - `pad.frames.length >= multiFramePadMin`
   - each frame `argmax === 1`; mean `liveScore >= padMinLiveScore`
   - if `depth.supported === true` → `depth.passed === true`
   - Fail → audit row + `400` with `rejectReason`
7. Require `livePhotoBase64` (non-empty). Decode + save JPEG under  
   `assets/faceAttendance/{orgId}/punches/{punchId}.jpg`.
8. **Server PAD** (`facePadServer.js` + `onnxruntime-node` + `sharp`):
   - Detect face box: use client-provided normalized box **or** a simple center-crop fallback if no detector on server (prefer client `faceBox` field)
   - Run MiniFASNet scales 2.7 + 4.0, average probs
   - Require `argmax === 1` and `liveScore >= padMinLiveScore`
   - Fail → `400` `PAD_FAILED_SERVER` (even if client pad claimed pass)
9. Validate `liveEmbedding` (192 finite floats); L2-normalize; match vs clear/mask/appearance gates.
10. Fail match → audit `FACE_MISMATCH` + `400`.
11. Success → server decides `checkIn`/`checkOut` from last matched punch; insert; return `200`.

**Never** trust client `matched`, `type`, `similarity`, or client `pad.passed` as the final spoof decision.

---

## Common auth

```http
Authorization: Bearer <JWT>
Content-Type: application/json
```

`userId` / `orgId` from authenticated user only.

| HTTP | When |
|------|------|
| 401 | Missing/invalid token |
| 400 | Validation / mismatch / liveness / PAD / challenge / geo / device |
| 404 | Not enrolled |
| 409 | Already enrolled |
| 429 | Rate limited (optional; or use 400 + `RATE_LIMITED`) |
| 500 | Server error |

```json
{ "status": 200, "message": "...", "data": {} }
```

---

## APIs

### 0) Create liveness challenge (nonce) — **new, required before punch**

`POST /api/v1/faceAttendance/liveness/challenge`

Call when the punch screen opens (or right before starting camera challenges).

#### Request body

```json
{
  "deviceId": "android-device-id"
}
```

#### Success `200`

```json
{
  "status": 200,
  "message": "Challenge created",
  "data": {
    "challengeId": "66f1a2b3c4d5e6f708090a11",
    "nonce": "f3c2a9e1-8b44-4c2a-9d1e-0a1b2c3d4e5f",
    "requiredSteps": ["blink", "turnLeft"],
    "expiresAt": "2026-10-17T06:01:30.000Z",
    "ttlSeconds": 90,
    "policy": {
      "requireServerPad": true,
      "requireLivePhoto": true,
      "padMinLiveScore": 0.70,
      "multiFramePadMin": 2,
      "depthRequiredIfSupported": true
    }
  }
}
```

`requiredSteps` must be a random permutation of:

- always include `"blink"`
- exactly one of `"turnLeft"` | `"turnRight"`

Flutter should prefer completing steps in this order (still acceptable if both completed in either order, as long as punch returns the nonce).

#### Errors

- Not enrolled → `404`
- Too many open challenges → invalidate previous; create new (keep one active per user)

Implement with `uuid` + Mongo `faceChallenges` or Redis key  
`face:challenge:{orgId}:{userId}` → `{ nonce, steps, exp }`.

---

### 1) Enroll face

`POST /api/v1/faceAttendance/enroll`

```json
{
  "displayName": "John Doe",
  "clearEmbedding": [0.01, 0.02],
  "maskedEmbedding": [0.01, 0.02],
  "appearanceEmbeddings": [[0.01, 0.02]],
  "photoBase64": "<jpeg base64>",
  "deviceId": "android-device-id",
  "enrolledAt": "2026-10-17T06:00:00.000Z",
  "pad": {
    "passed": true,
    "liveScore": 0.91,
    "argmax": 1,
    "model": "MiniFASNetV2",
    "minLiveScoreUsed": 0.70,
    "frames": [
      { "liveScore": 0.90, "argmax": 1 },
      { "liveScore": 0.92, "argmax": 1 }
    ]
  }
}
```

If `photoBase64` present and `requireServerPad` for enroll: run server PAD; reject `PAD_FAILED_SERVER`.

If device binding enabled and `boundDeviceIds` empty: append `deviceId` as first bound device.

---

### 2) Update face

`POST /api/v1/faceAttendance/update`

Same fields as enroll (partial). Re-run server PAD when photo/embeddings change.

---

### 3) Punch — server verified + nonce + server PAD

`POST /api/v1/faceAttendance/punch`

#### Request body

```json
{
  "challengeNonce": "f3c2a9e1-8b44-4c2a-9d1e-0a1b2c3d4e5f",
  "liveEmbedding": [0.01, 0.02],
  "transactionDate": "2026-10-17T06:00:00.000Z",
  "type": "checkIn",
  "deviceId": "android-device-id",
  "appVersion": "1.0.0+1",
  "geoJson": {
    "type": "Point",
    "coordinates": [72.8777, 19.076]
  },
  "templateHint": "auto",
  "livePhotoBase64": "<required jpeg base64>",
  "faceBox": {
    "xmin": 0.25,
    "ymin": 0.18,
    "xmax": 0.72,
    "ymax": 0.78
  },
  "liveness": {
    "passed": true,
    "method": "blinkAndHeadTurn",
    "challenges": ["blink", "turnLeft"],
    "completedAt": "2026-10-17T06:00:01.200Z",
    "durationMs": 4200
  },
  "pad": {
    "passed": true,
    "liveScore": 0.91,
    "argmax": 1,
    "model": "MiniFASNetV2",
    "minLiveScoreUsed": 0.70,
    "frames": [
      { "liveScore": 0.88, "argmax": 1, "at": "2026-10-17T06:00:00.500Z" },
      { "liveScore": 0.93, "argmax": 1, "at": "2026-10-17T06:00:01.800Z" },
      { "liveScore": 0.92, "argmax": 1, "at": "2026-10-17T06:00:02.100Z" }
    ]
  },
  "depth": {
    "supported": false,
    "passed": null,
    "stdDevMeters": null,
    "frames": null,
    "source": "none"
  },
  "clientPreview": {
    "similarity": 0.81,
    "distance": 0.62,
    "matched": true
  }
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `challengeNonce` | **Yes** | From `/liveness/challenge` |
| `liveEmbedding` | Yes | 192 floats |
| `livePhotoBase64` | **Yes** | Server PAD input |
| `faceBox` | Recommended | Normalized box for PAD crop; else center-ish crop |
| `liveness` | Yes | Client challenge result |
| `pad.frames` | **Yes** | ≥ 2 frames; mean used for client policy |
| `depth` | Yes object | `supported: false` on Android / no TrueDepth |
| `deviceId` | Recommended | Required if device binding on |
| `geoJson` | Required if geofence on | `[lng, lat]` |
| `clientPreview` | No | Ignored for decisions |

**iOS TrueDepth example when available:**

```json
"depth": {
  "supported": true,
  "passed": true,
  "stdDevMeters": 0.012,
  "frames": 8,
  "source": "TrueDepth"
}
```

#### Success `200`

```json
{
  "status": 200,
  "message": "Check-In successful",
  "data": {
    "punchId": "66f1a2b3c4d5e6f708090a0c",
    "type": "checkIn",
    "matched": true,
    "similarity": 0.81,
    "distance": 0.62,
    "matchedTemplate": "clear",
    "transactionDate": "2026-10-17T06:00:00.000Z",
    "padLiveScore": 0.91,
    "padServerLiveScore": 0.89,
    "livenessMethod": "blinkAndHeadTurn",
    "syncedToMainAttendance": false
  }
}
```

#### Error examples

**Challenge**

```json
{
  "status": 400,
  "message": "Invalid or expired liveness challenge",
  "data": { "matched": false, "rejectReason": "CHALLENGE_EXPIRED" }
}
```

**Server PAD**

```json
{
  "status": 400,
  "message": "Spoof detected by server anti-spoof model",
  "data": {
    "matched": false,
    "rejectReason": "PAD_FAILED_SERVER",
    "padServerLiveScore": 0.22,
    "padServerArgmax": 2
  }
}
```

**Face mismatch**

```json
{
  "status": 400,
  "message": "Face mismatch",
  "data": {
    "matched": false,
    "bestSimilarity": 0.41,
    "bestDistance": 1.12,
    "rejectReason": "FACE_MISMATCH"
  }
}
```

**Geo / device / rate limit**

| `rejectReason` | Meaning |
|----------------|---------|
| `GEO_REQUIRED` | Geofence on but no `geoJson` |
| `GEO_OUT_OF_RANGE` | Outside allowed area |
| `DEVICE_NOT_ALLOWED` | Device not bound |
| `RATE_LIMITED` | Too many failed punches |
| `LIVENESS_REQUIRED` | Client liveness missing/false |
| `LIVENESS_STALE` | Challenge finished too long before punch |
| `PAD_FAILED` | Client multi-frame PAD failed policy |
| `DEPTH_REQUIRED` | `depth.supported` true but not passed |
| `PAD_FAILED_SERVER` | Server MiniFASNet rejected photo |
| `PHOTO_REQUIRED` | Missing `livePhotoBase64` |

---

### 4) Enrollment status

`POST /api/v1/faceAttendance/status`

```json
{}
```

```json
{
  "status": 200,
  "message": "success",
  "data": {
    "isEnrolled": true,
    "hasClear": true,
    "hasMasked": false,
    "enrolledAt": "2026-10-17T06:00:00.000Z",
    "updatedAt": "2026-10-17T07:30:00.000Z",
    "policy": {
      "requireLiveness": true,
      "requirePad": true,
      "requireServerPad": true,
      "requireChallengeNonce": true,
      "requireLivePhoto": true,
      "padMinLiveScore": 0.70,
      "multiFramePadMin": 2,
      "depthRequiredIfSupported": true,
      "geofenceEnabled": false,
      "deviceBindingEnabled": false
    }
  }
}
```

Never return embeddings.

---

### 5) Punch history (self)

`POST /api/v1/faceAttendance/history`

Include `padServerLiveScore`, `rejectReason` in items; **never** embeddings or photos.

---

### 6) Report list (org-scoped)

`POST /api/v1/faceAttendance/report/list`

Permission: `faceAttendance.reports.view` (or reuse existing attendance report permission). Always filter by auth `orgId`.

---

### 7) Report export

`POST /api/v1/faceAttendance/report/export`

**Columns:** employeeId, name, type, transactionDate, matched, similarity, matchedTemplate, padLiveScore, padServerLiveScore, livenessMethod, deviceId, rejectReason.

---

## `helper/facePadServer.js` — implementation sketch

```js
// Packages: onnxruntime-node, sharp
import ort from 'onnxruntime-node';
import sharp from 'sharp';

// 1) sharp(Buffer.from(base64, 'base64')) → raw { data, info }
// 2) Expand faceBox by scale 2.7 and 4.0 (Silent-Face CropImage math)
// 3) Resize each crop to 80x80, extract BGR float32 0..255, layout NCHW [1,3,80,80]
// 4) session.run({ input: tensor }) → softmax probs [3]
// 5) Average probs across scales; liveScore = probs[1]; argmax = index of max
```

Load the ONNX session **once** at process start (singleton). Unit-test against a known live JPEG and a known print/screen JPEG.

---

## `helper/faceChallengeStore.js` — sketch

```js
import { randomUUID } from 'crypto';

// createChallenge(orgId, userId, deviceId):
//   invalidate previous active challenges for user
//   nonce = randomUUID()
//   requiredSteps = shuffle(['blink', randomTurn])
//   expiresAt = now + TTL
//   persist Mongo or Redis

// consumeChallenge(orgId, userId, nonce):
//   find + not expired + consumedAt == null
//   set consumedAt = now
//   return challenge or throw CHALLENGE_*
```

---

## Explicit non-goals (this milestone)

- Do **not** write to `employeeAttendence` / call `/attendance/add` yet.
- Do **not** call AWS Rekognition for this module.
- Keep `syncedToMainAttendance: false` until a later sync job is approved.

---

## Later hook (main attendance sync)

```text
// When syncToMainAttendanceEnabled, after successful matched punch,
// enqueue job to create official attendance via existing addAttendenceData pipeline
// and set syncedToMainAttendance + mainAttendanceId.
```

---

## Acceptance checklist

- [ ] Separate DB only; zero writes to main attendance collections
- [ ] `/liveness/challenge` returns nonce + randomized steps + TTL
- [ ] Punch **rejects** missing/expired/reused nonce
- [ ] Punch **requires** `livePhotoBase64`
- [ ] Server PAD via `onnxruntime-node` + `sharp` rejects spoof photos (`PAD_FAILED_SERVER`)
- [ ] Client multi-frame PAD policy enforced (≥2 frames, mean ≥ threshold)
- [ ] When `depth.supported === true`, require `depth.passed`
- [ ] Punch rejects wrong-length embeddings; server match is authoritative
- [ ] Punch type alternates correctly on server
- [ ] Optional geofence / device bind / rate limit work when enabled in org config
- [ ] Status returns full `policy` object for Flutter alignment
- [ ] Joi validation on all nested fields
- [ ] Unit tests: embedding math, challenge consume, server PAD live vs spoof, punch happy path

---

## Suggested file touch list

- `config/faceAttendanceDb.js` (new)
- `routes/faceAttendance.js` (new)
- `routes/apiRoute.js` (mount)
- `controllers/faceAttendance/enroll.js`, `punch.js`, `challenge.js`, `report.js` (new)
- `models/faceAttendance/enrollment.js`, `punch.js`, `challenge.js`, `config.js` (new)
- `helper/faceEmbeddingMath.js` (new)
- `helper/faceLivenessPolicy.js` (new)
- `helper/facePadServer.js` (new — **onnxruntime-node**, **sharp**)
- `helper/faceChallengeStore.js` (new — **uuid** / `crypto.randomUUID`, Redis optional **ioredis**)
- `helper/faceGeoDevicePolicy.js` (new — optional **@turf/boolean-point-in-polygon**)
- `helper/validationSchema.js` (schemas)
- `assets/faceAttendance/models/silentface.onnx` (model asset)
- `package.json` deps: `onnxruntime-node`, `sharp`, `uuid` (if needed), `ioredis` (optional), `@turf/boolean-point-in-polygon` (optional)
- `.env`: `FACE_MONGO_*`, `FACE_PAD_MODEL_PATH`, `FACE_PAD_MIN_LIVE_SCORE`, `FACE_CHALLENGE_TTL_SECONDS`, `FACE_REDIS_URL` (optional)
