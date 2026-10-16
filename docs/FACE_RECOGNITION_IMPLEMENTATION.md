# Face Recognition Implementation

This document describes how on-device face recognition is implemented in the **Face Attendance** Flutter app: which models are used, how enrollment and punch matching work, and where the logic lives in the codebase.

---

## Overview

The app performs **1:1 face verification** fully **on-device** (no cloud inference). A live camera frame is detected, optionally checked for liveness, converted into a face **embedding**, and compared against locally stored templates using cosine similarity and Euclidean distance.


| Concern           | Approach                                                                            |
| ----------------- | ----------------------------------------------------------------------------------- |
| Runtime           | Flutter + GetX                                                                      |
| ML package        | `[face_detection_tflite](https://pub.dev/packages/face_detection_tflite)` `^6.10.1` |
| Inference backend | LiteRT (formerly TensorFlow Lite) via MediaPipe-style models                        |
| Storage           | SQLite (`sqflite`) + enrolled JPEG on device storage                                |
| Camera            | `camera` plugin (front camera)                                                      |


Primary service: `lib/services/face_recognition_service.dart`  
Bootstrapped in `lib/main.dart` before `runApp`.

---

## Models Used

The app does **not** ship custom `.tflite` files. Models are bundled inside `face_detection_tflite` and loaded when `FaceDetector.create(...)` runs.

### 1. Face detection — BlazeFace (MediaPipe)


| Setting in app                   | Model variant                                                       |
| -------------------------------- | ------------------------------------------------------------------- |
| `FaceDetectionModel.frontCamera` | Short-range BlazeFace (`face_detection_front.tflite` / short-range) |


- Optimized for **selfie / front-camera** distance.
- Outputs face bounding boxes and a detection confidence score.
- App floors: `detectorMinScore = 0.5`, `detectorMinFacePresence = 0.25` (so masked/occluded faces are not dropped too early).

### 2. Face landmarks / mesh — MediaPipe Face Mesh

Used in **full detection mode** during punch auto-scan:

- **468-point face mesh** (`face_landmark.tflite`)
- Iris / eye tracking and **head pose** (yaw / pitch / roll)
- Per-eye **open probability** (for blink liveness)
- Landmarks used for a simple **occlusion / mask heuristic** (eye–nose–mouth geometry)

### 3. Face recognition (identity) — MobileFaceNet


| Property   | Value                                                                 |
| ---------- | --------------------------------------------------------------------- |
| Model file | `mobilefacenet.tflite`                                                |
| Paper      | [MobileFaceNets (arXiv:1804.07573)](https://arxiv.org/abs/1804.07573) |
| Output     | **192-dimensional** embedding vector                                  |
| Purpose    | Face **verification / identification** (not detection)                |


MobileFaceNet is a compact CNN (< ~1M parameters class of models) designed for real-time face verification on mobile devices. Embeddings are L2-normalized in app code before comparison.

Comparison APIs from the package:

- `FaceDetector.compareFaces(a, b)` → **cosine similarity** (−1…1; higher = more alike)
- `FaceDetector.faceDistance(a, b)` → **Euclidean distance** (lower = more alike)

Package guidance (mirrored in `AppConstants` comments): similarity **> ~0.6** often same person; distance **< ~0.6** very likely same. This app uses **stricter** gates (see [Match thresholds](#match-thresholds)).

---

## Architecture

```
┌─────────────────┐     ┌──────────────────────────┐     ┌─────────────────┐
│  Camera / JPEG  │────▶│  FaceRecognitionService  │────▶│  SQLite profile │
│  (enroll/punch) │     │  + ImageQualityService   │     │  + photo file   │
└─────────────────┘     │  + LivenessTracker       │     └─────────────────┘
                        └──────────────────────────┘
                                      │
                        FaceDetector (TFLite / LiteRT)
                        ├── BlazeFace (detect)
                        ├── Face Mesh (landmarks / eyes / yaw)
                        └── MobileFaceNet (192-d embedding)
```

### Key modules


| Path                                                        | Role                                            |
| ----------------------------------------------------------- | ----------------------------------------------- |
| `lib/services/face_recognition_service.dart`                | Detect, embed, match, appearance gallery        |
| `lib/services/image_quality_service.dart`                   | Brightness / sharpness gate on stills           |
| `lib/services/liveness_tracker.dart`                        | Blink **or** head-turn anti-spoof               |
| `lib/modules/attendance/controllers/enroll_controller.dart` | Multi-frame clear + optional mask enroll        |
| `lib/modules/attendance/controllers/punch_controller.dart`  | Stream detect → liveness → auto punch           |
| `lib/data/models/employee_profile.dart`                     | Template storage shape                          |
| `lib/core/constants/app_constants.dart`                     | Default thresholds and limits                   |
| `lib/core/config/match_threshold_config.dart`               | Runtime-tunable match gates (SharedPreferences) |


---

## Pipeline Details

### A. Initialization

On app start (`main.dart`):

1. Load `SharedPreferences` → `MatchThresholdStore`
2. Create `ImageQualityService` + `FaceRecognitionService`
3. `await faceService.init()` → `FaceDetector.create(model: frontCamera, …)`
4. Inject into GetX via `InitialBinding`

### B. Enrollment

Implemented in `EnrollController`:

1. **Clear face** — capture **3 frames** (`clearEnrollFrameCount`), each:
  - Image quality check (luma + sharpness)
  - Single-face detection (reject multi-face)
  - Score / size gates (`minFaceScore`, `minFaceWidthFraction`)
  - MobileFaceNet embedding → L2-normalize
2. First frame becomes the **primary clear template**; other frames seed an **appearance gallery** (beard/glasses/lighting variants), capped at 8 vectors.
3. **Optional masked template** — user can enroll once with a mask (eyes must stay visible); uses softer face-score gates.
4. Persist via `ProfileRepository.saveEnrollment`:
  - JPEG under app documents
  - Embeddings as JSON in SQLite `employee_profile`

Template kinds (`FaceTemplateKind`):

- `clear` — primary unmasked embedding  
- `masked` — optional mask embedding  
- `appearance` — extra clear-face variants

### C. Punch (recognition)

Implemented in `PunchController`:

1. Load stored clear / masked / appearance embeddings.
2. Start front-camera **YUV image stream**.
3. Each frame → `detectFromCameraImage(..., mode: FaceDetectionMode.full)` for eyes + yaw.
4. **Liveness** (`LivenessTracker`): pass by **blink** (open→closed→open) **or** **head turn** (~12° yaw after frontal).
5. After liveness, require **3 stable face hits**, then still capture + `matchFromBytes`.
6. Match against all candidate templates; best passing gate wins.
7. On strong match, optionally **adapt** appearance gallery; record attendance and navigate to dashboard.

### D. Matching logic

For a punch still:

1. Quality gate (reject too dark / too blurry).
2. Detect single best face; extract live MobileFaceNet embedding; L2-normalize.
3. Heuristic `_looksOccludedOrCovered` from landmark geometry / mesh score.
4. Build candidate list: clear + appearance + (if enrolled) masked.
5. For each candidate, compute similarity + distance; apply gates from `_gatesFor`:
  - Clear / appearance → strict clear thresholds  
  - Masked + live occluded → masked thresholds  
  - Clear vs occluded live **without** masked template → slightly softer occluded thresholds
6. Accept if similarity ≥ min **and** distance ≤ max.

### E. Image quality

`ImageQualityService` downscales the JPEG to ~160px width and scores:

- Mean luminance (reject < 45 or > 210)
- Mean absolute gradient as a blur proxy (reject < 12)

---

## Match Thresholds

Defaults in `AppConstants` / `MatchThresholdConfig.defaults` (tunable in Settings via SharedPreferences):


| Scenario                               | Min cosine similarity | Max Euclidean distance |
| -------------------------------------- | --------------------- | ---------------------- |
| Clear ↔ clear / appearance             | 0.72                  | 0.85                   |
| Masked ↔ masked (live occluded)        | 0.70                  | 0.88                   |
| Clear ↔ occluded (no masked template)  | 0.68                  | 0.92                   |
| Appearance gallery adapt (post-accept) | ≥ 0.78                | ≤ 0.80                 |


These are intentionally stricter than the package’s “likely same person” guide (~0.6) to reduce false accepts.

---

## Data Stored Locally

SQLite DB: `face_attendance.db` (`AppConstants.dbVersion = 4`)

`employee_profile`


| Column                  | Content                                   |
| ----------------------- | ----------------------------------------- |
| `embedding`             | Primary clear MobileFaceNet vector (JSON) |
| `masked_embedding`      | Optional masked vector                    |
| `appearance_embeddings` | JSON list of extra clear vectors          |
| `photo_path`            | Enrolled still path                       |
| `remote_synced_at`      | Placeholder sync marker                   |


`attendance_records` — punch type, timestamp, similarity, matched flag.

Remote sync is stubbed (`NoopFaceSyncClient`); inference remains local.

---

## Liveness (Anti-Spoof)

Not a separate neural spoof model. Rule-based tracking on MediaPipe outputs:


| Method    | Signal                                               | Pass condition       |
| --------- | ---------------------------------------------------- | -------------------- |
| Blink     | `leftEyeOpenProbability` / `rightEyeOpenProbability` | Open → closed → open |
| Head turn | `headEulerAngleY`                                    | Near-frontal then    |


Either method completes liveness before auto-punch.

---

## Design Choices

1. **On-device only** — privacy and offline attendance.
2. **MobileFaceNet for identity** — small, mobile-friendly 192-d embeddings.
3. **BlazeFace front + Face Mesh** — detection + landmark features for liveness and occlusion hints.
4. **Multi-template profile** — clear + optional mask + appearance gallery improves robustness without lowering the clear gate too far.
5. **Dual metric gates** — both similarity and distance must pass.
6. **Strict thresholds** — favor fewer false accepts over easy punches.

---

## References

- Package: [face_detection_tflite on pub.dev](https://pub.dev/packages/face_detection_tflite)
- MediaPipe BlazeFace / Face Mesh model cards (via package `doc/model_cards/`)
- MobileFaceNets paper: [arXiv:1804.07573](https://arxiv.org/abs/1804.07573)
- App entry: `lib/main.dart`
- Recognition core: `lib/services/face_recognition_service.dart`

