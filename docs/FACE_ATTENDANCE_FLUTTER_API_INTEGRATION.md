# Face Attendance — Flutter / Kavach API Integration

Flutter-side contract for wiring this face attendance app (and later Kavach) to live EasyPagar APIs with **server-authoritative punch-in / punch-out**, **challenge nonce**, **multi-frame PAD**, optional **TrueDepth**, and **geo / device** policy.

| App | Path |
|-----|------|
| Temp / prototype | `D:\Flutter Project\facerecognition` |
| Main product (merge target) | `D:\Flutter Project\Kavach` |

---

## Current vs target (important)

| Layer | Today (local prototype) | Target (real project) |
|-------|-------------------------|------------------------|
| Enroll templates | SQLite + noop sync print | `POST .../enroll` or `.../update` |
| Challenge nonce | Not used | `POST .../liveness/challenge` → send `challengeNonce` on punch |
| Liveness (blink + turn) | On-device `LivenessTracker` | Keep; prefer `requiredSteps` from challenge; send attestation |
| PAD (MiniFASNetV2) | Single still inside match | **Multi-frame** (≥2) + send `pad.frames`; **always send** `livePhotoBase64` |
| Server PAD | N/A | Server re-scores photo; client cannot forge pass |
| TrueDepth | Not wired | iOS: send `depth`; Android: `supported: false` |
| Face match | On-device → local SQLite punch | Preview only; **server match authorizes** |
| Check-in / out type | Local alternate `in`/`out` | **Server decides** `checkIn` / `checkOut` |
| Geo / device | Not sent | Send `deviceId` + `geoJson` when policy requires |
| History | Local SQLite | Prefer `POST .../history` when online |

**Rule:** never treat a local match as the official attendance event once APIs are live. Local DB is offline UX / cache.

---

## Auth

```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

Use the same EasyPagar base URL / JWT already used by Kavach (`/api/v1/...`).

`userId` / `orgId` / `employeeId` come from the logged-in user on the server — **do not** send them as authority in the body.

---

## On-device pipeline (target)

```text
1) status() → policy (padMinLiveScore, multiFramePadMin, geofence, deviceBinding, …)
2) liveness/challenge() → { nonce, requiredSteps, expiresAt }
3) Camera:
     → optional TrueDepth (iOS) in parallel
     → LivenessTracker (blink + directed turn; prefer requiredSteps order)
4) Capture 2–3 JPEGs (before hold-still / at punch / after brief delay)
     → FacePadService each frame → pad.frames[]
5) Final still:
     → ImageQualityService
     → MobileFaceNet preview match (UX only)
6) POST /punch {
     challengeNonce, liveEmbedding, livePhotoBase64, faceBox,
     liveness, pad.frames, depth, deviceId, geoJson, …
   }
7) Server: consume nonce → geo/device/rate-limit → client policy
     → SERVER PAD on photo → embedding match → checkIn/checkOut
8) Cache server result in SQLite; show data.type
```

Do **not** remove on-device liveness/PAD — they reduce bad requests and fill attestation fields. Server PAD + nonce remain authoritative against forged payloads.

---

## Embedding + PAD + depth contract

| Item                      | Value                                                                      |
| ------------------------- | -------------------------------------------------------------------------- |
| Match model               | MobileFaceNet via `face_detection_tflite`                                  |
| Embedding dim             | **192** floats, L2-normalized on device (server re-normalizes)             |
| PAD model                 | MiniFASNetV2 `assets/models/silentface.tflite`                             |
| PAD input                 | Crops × **2.7** + **4.0**, 80×80, BGR **0..255**, NCHW                     |
| PAD pass (client)         | Each frame `argmax == 1`; mean live ≥ `padMinLiveScore` (default **0.70**) |
| Multi-frame               | ≥ `policy.multiFramePadMin` (default **2**) scores in `pad.frames`         |
| Depth (iOS)               | TrueDepth Z std-dev; send `depth.supported: true` when available           |
| Depth (Android)           | Always `{ "supported": false, "source": "none" }`                          |
| Clear / mask / appearance | Same as today                                                              |

Align thresholds with `data.policy` from `status` / `liveness/challenge`.

### Suggested Flutter packages (client)

| Package | Use |
|---------|-----|
| Existing `face_detection_tflite` + `flutter_litert` | Face + PAD (already in prototype) |
| `geolocator` or Kavach’s existing location helper | `geoJson` Point `[lng, lat]` |
| `device_info_plus` / Kavach device id | Stable `deviceId` |
| `arkit_plugin` (iOS only) | TrueDepth face mesh Z-variance (optional module) |
| `package_info_plus` | `appVersion` |

Do **not** run ONNX on device for server PAD — that stays on Node (`onnxruntime-node`).

---

## Field map (local / stub → backend)

Backend uses **camelCase**. Stub (`noop_face_sync_client.dart`) still prints snake_case — switch in `HttpFaceSyncClient`.

| Flutter / local concept | Stub snake_case (today) | Backend API (camelCase) |
|-------------------------|-------------------------|-------------------------|
| Clear embedding | `embedding` | `clearEmbedding` |
| Masked embedding | `masked_embedding` | `maskedEmbedding` |
| Appearance gallery | (local only) | `appearanceEmbeddings` |
| Enroll photo | `photo_base64` | `photoBase64` |
| Punch still | (not sent yet) | `livePhotoBase64` (**required**) |
| Face box for PAD | (local Face bbox) | `faceBox: { xmin, ymin, xmax, ymax }` |
| Challenge nonce | — | `challengeNonce` (**required**) |
| Employee code | `employee_id` | Not in body (JWT) |
| Display name | `display_name` | `displayName` |
| Device id | `device_id` | `deviceId` |
| Enrolled at | `enrolled_at` | `enrolledAt` |
| Punch type | `type: "in"\|"out"` | Server returns `checkIn`\|`checkOut` |
| Live vector | `embedding` | `liveEmbedding` |
| Punch time | `timestamp` | `transactionDate` |
| Preview scores | client fields | `clientPreview` only (ignored for decisions) |
| Liveness | local only | `liveness: { passed, method, challenges, completedAt, durationMs }` |
| PAD | local only | `pad: { passed, liveScore, argmax, model, minLiveScoreUsed, frames[] }` |
| Depth | — | `depth: { supported, passed, stdDevMeters, frames, source }` |
| Location | — | `geoJson` |

---

## Endpoint map (stub → production)

| Flutter stub / gap | Production path |
|--------------------|-----------------|
| `POST /api/faces/enroll` | `POST /api/v1/faceAttendance/enroll` |
| (re-enroll / update) | `POST /api/v1/faceAttendance/update` |
| **(new)** | `POST /api/v1/faceAttendance/liveness/challenge` |
| `POST /api/attendance/punch` | `POST /api/v1/faceAttendance/punch` |
| (gate check) | `POST /api/v1/faceAttendance/status` |
| (history) | `POST /api/v1/faceAttendance/history` |

Admin `/report/*` is HR/web only.

---

## Client flows

### Gate (open attendance)

1. `POST /api/v1/faceAttendance/status` with `{}`.
2. Cache `data.policy`:

```json
{
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
```

3. If `isEnrolled == false` → enroll; else → punch.

### Enroll

1. Capture clear frames → `clearEmbedding` + `photoBase64`.
2. Run PAD (≥1–2 frames); block UI if not live.
3. Optional mask → `maskedEmbedding`.
4. `POST .../enroll` with `pad` (+ `pad.frames` if available) + `deviceId`.
5. On `409` → `POST .../update`.
6. Mirror to SQLite for offline UX.

### Challenge (before / as punch camera starts)

`POST /api/v1/faceAttendance/liveness/challenge`

```json
{ "deviceId": "<stable-device-id>" }
```

Store in memory on `PunchController`:

- `nonce`
- `requiredSteps` (e.g. `["blink","turnLeft"]`)
- `expiresAt`

If `expiresAt` passes before punch → call challenge again.

Wire `requiredSteps` into `LivenessTracker` when possible (ordered blink + directed turn). If tracker still uses random order, still OK as long as both blink and the required turn direction are completed before punch.

### Punch (server is source of truth)

1. Ensure fresh **challenge nonce** (not expired).
2. If `geofenceEnabled` → acquire GPS → `geoJson`.
3. Run liveness until complete; record `completedAt`, `challenges`, `durationMs`.
4. Collect **≥ multiFramePadMin** PAD scores into `pad.frames` (e.g. mid-liveness + final still).
5. On iOS with TrueDepth: fill `depth`; else `supported: false`.
6. Final `takePicture()` → quality + preview match; keep JPEG bytes + `faceBox`.
7. If any **local** gate fails → friendly error; **do not** call punch.
8. `POST /api/v1/faceAttendance/punch`:

```json
{
  "challengeNonce": "<from challenge API>",
  "liveEmbedding": [/* 192 floats */],
  "transactionDate": "<ISO8601 now>",
  "deviceId": "<stable-device-id>",
  "appVersion": "1.0.0+1",
  "geoJson": {
    "type": "Point",
    "coordinates": [lng, lat]
  },
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
    "completedAt": "<ISO>",
    "durationMs": 4200
  },
  "pad": {
    "passed": true,
    "liveScore": 0.91,
    "argmax": 1,
    "model": "MiniFASNetV2",
    "minLiveScoreUsed": 0.70,
    "frames": [
      { "liveScore": 0.88, "argmax": 1, "at": "<ISO>" },
      { "liveScore": 0.93, "argmax": 1, "at": "<ISO>" }
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

**iOS when TrueDepth available:**

```json
"depth": {
  "supported": true,
  "passed": true,
  "stdDevMeters": 0.012,
  "frames": 8,
  "source": "TrueDepth"
}
```

9. On `200`: use `data.type`, show success, cache local history from server. Prefer showing success without raw scores.
10. On errors → map `rejectReason` (below); reset liveness; refresh challenge nonce before retry.
11. On `404` → enroll.

| Server | Local (`AttendanceType`) |
|--------|--------------------------|
| `checkIn` | `in` / `clockIn` |
| `checkOut` | `out` / `clockOut` |

### `rejectReason` → user copy

| `rejectReason` | Snackbar / instruction |
|----------------|------------------------|
| `CHALLENGE_REQUIRED` / `CHALLENGE_INVALID` / `CHALLENGE_EXPIRED` | Session expired — try again |
| `PAD_FAILED` | Couldn’t verify live face — try again |
| `PAD_FAILED_SERVER` | Photo rejected — use your live face (no screen/photo) |
| `PHOTO_REQUIRED` | Capture failed — try again |
| `LIVENESS_REQUIRED` / `LIVENESS_STALE` | Follow the blink / turn steps again |
| `DEPTH_REQUIRED` | Keep your face in view (iOS depth check failed) |
| `FACE_MISMATCH` | Face not recognized |
| `GEO_REQUIRED` / `GEO_OUT_OF_RANGE` | You must be at an allowed location |
| `DEVICE_NOT_ALLOWED` | This device isn’t allowed for attendance |
| `RATE_LIMITED` | Too many attempts — wait and retry |

### Offline policy

Recommended for Kavach:

- **Online required** for official punch (nonce + server PAD need network).
- Do not queue punches that skip nonce/photo — they will fail server policy later.

### History

`POST /api/v1/faceAttendance/history` with optional date range + pagination. Prefer server when online.

---

## Suggested Flutter wiring checklist

### 1) Network client

| Current | Target |
|---------|--------|
| `NoopFaceSyncClient` | `HttpFaceSyncClient` implementing expanded `FaceSyncPort` |
| Stub paths | `/api/v1/faceAttendance/*` camelCase + Bearer JWT |
| `ApiClient` | Kavach base URL + auth |

```dart
abstract class FaceSyncPort {
  Future<FaceStatusResult> status();
  Future<LivenessChallengeResult> createLivenessChallenge({String? deviceId});
  Future<EnrollResult> enroll(FaceEnrollRequest request);
  Future<EnrollResult> update(FaceEnrollRequest request);
  Future<PunchResult> punch(FacePunchRequest request);
  Future<PunchHistoryPage> history({DateTime? start, DateTime? end, int page, int limit});
}
```

### 2) DTOs to add

Under `lib/data/models/` or `remote/dto/`:

- `FacePolicy` — from `status` / challenge `policy`
- `LivenessChallengeResult` — `nonce`, `requiredSteps`, `expiresAt`
- `FaceLivenessAttestation`
- `FacePadFrame` / `FacePadAttestation` (with `frames`)
- `FaceDepthAttestation`
- `FaceBox` — normalized xmin/ymin/xmax/ymax
- `FacePunchRequest` / `FacePunchResult`

### 3) Services / controllers to extend

| Area | Change |
|------|--------|
| `FacePadService` | Support scoring multiple stills; return list for `pad.frames` |
| `FaceRecognitionService` | Expose last PAD + `faceBox` on match (or score PAD in controller) |
| `LivenessTracker` | Optional: accept `requiredSteps` from challenge |
| `DepthLivenessPort` (new) | iOS ARKit TrueDepth; Android no-op `supported: false` |
| `PunchController` | Fetch challenge on open; collect multi-frame PAD; attach nonce/photo/depth/geo; call HTTP punch |
| Gate / enroll controllers | `status` policy; enroll with pad frames + deviceId |

### 4) Files to touch when integrating

- `lib/data/remote/face_sync_port.dart`
- `lib/data/remote/http_face_sync_client.dart` (**new**)
- `lib/data/remote/noop_face_sync_client.dart` (demo flag)
- `lib/core/network/api_client.dart`
- `lib/data/models/*` (DTOs)
- `lib/data/repositories/profile_repository.dart`
- `lib/data/repositories/attendance_repository.dart`
- `lib/modules/attendance/controllers/punch_controller.dart`
- `lib/modules/attendance/controllers/enroll_controller.dart`
- `lib/modules/attendance/controllers/attendance_gate_controller.dart`
- `lib/services/face_pad_service.dart` / `face_recognition_service.dart`
- `lib/services/depth_liveness_port.dart` (**new**, iOS)
- `lib/bindings/initial_binding.dart`
- `pubspec.yaml` — `geolocator`, `device_info_plus`, `arkit_plugin` (iOS) as needed

---

## Minimal punch sequence (Kavach PR description)

```text
1. Open Punch → status() + liveness/challenge()
2. Complete requiredSteps (blink + turn)
3. Collect ≥2 PAD frame scores; optional TrueDepth
4. Capture final JPEG + embedding + faceBox
5. POST /punch with challengeNonce + livePhotoBase64 + attestations
6. 200 → show server checkIn/checkOut; cache locally
7. 400 → map rejectReason; new challenge(); reset liveness
```

---

## Acceptance checklist (Flutter)

- [ ] JWT on all faceAttendance calls  
- [ ] Punch opens only after `liveness/challenge` succeeds  
- [ ] Punch body includes `challengeNonce`, `liveEmbedding` (192), `livePhotoBase64`, `faceBox`, `liveness`, `pad.frames` (≥2), `depth`  
- [ ] Official IN/OUT only after server `200`  
- [ ] Server `data.type` drives UI + local cache  
- [ ] All listed `rejectReason` values mapped to friendly copy  
- [ ] `geolocator` / device id sent when policy requires  
- [ ] iOS depth module optional; Android always `supported: false`  
- [ ] Enroll sends `pad` (+ frames) and `deviceId`  
- [ ] Noop client remains for local demos behind a debug flag  

---

## Related constants (device)

See `lib/core/constants/app_constants.dart`:

- `padModelAsset`, `padCropScale` (2.7), `padMinLiveScore` (0.70)  
- Match gates: `punchMatchThreshold`, `punchMaxDistance`, masked / occluded variants

Override live from server `policy` at runtime when online.
