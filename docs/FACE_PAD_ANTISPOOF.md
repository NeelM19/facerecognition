# Face PAD / anti-spoof (MiniFASNetV2)

On-device **presentation attack detection** rejects printed photos, phone screens, and many replayed videos after liveness challenges pass.

## Model

| Item | Value |
| --- | --- |
| File | [`assets/models/silentface.tflite`](../assets/models/silentface.tflite) (~1.85 MB) |
| Architecture | MiniFASNetV2 (Silent-Face-Anti-Spoofing) |
| Source | [litert-community/Silent-Face-Anti-Spoofing-LiteRT](https://huggingface.co/litert-community/Silent-Face-Anti-Spoofing-LiteRT) |
| Upstream | [minivision-ai/Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) (Apache-2.0) |
| Input | Float32 `[1,3,80,80]` NCHW, **BGR**, values **0..255** (not `/255` — matches Silent-Face `ToTensor`), face crops × **2.7** and **4.0** ensembled |
| Output | 3-class probabilities; **class 1 = live**, 0/2 = spoof |
| Gate | `argmax == 1` and live score ≥ [`AppConstants.padMinLiveScore`](../lib/core/constants/app_constants.dart) (default `0.70`) |

## Runtime path

1. Challenge liveness (blink + head turn) in `LivenessTracker`
2. Capture punch still
3. Image quality + screen/print heuristic
4. **PAD** on the face crop (`FacePadService`)
5. Face match embedding

PAD also runs on **enroll** stills so a photo cannot be enrolled as a template.

## Re-download the model

```powershell
New-Item -ItemType Directory -Force -Path assets\models
Invoke-WebRequest `
  -Uri "https://huggingface.co/litert-community/Silent-Face-Anti-Spoofing-LiteRT/resolve/main/silentface.tflite" `
  -OutFile "assets\models\silentface.tflite"
```

## Tuning

- Too many genuine rejects → lower `padMinLiveScore` (e.g. `0.75`)
- Video/screen still passes → raise toward `0.90`, and/or ensemble a second MiniFASNet scale (`4.0`) later

## Limits

PAD + challenge liveness raise the bar a lot, but determined attacks (high-quality 3D masks, deepfakes, curated video under matched lighting) may still need server-side checks or depth/IR hardware.
