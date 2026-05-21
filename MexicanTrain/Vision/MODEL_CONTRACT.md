# DominoDetector CoreML model

The bundled `DominoDetector.mlpackage` is a YOLOv11n trained by the web app's
`ml/` pipeline (commit history in `~/Documents/code/platform/apps/mextrain/ml/`).
It detects individual domino **halves** (one detection per half), labeling each
with its pip value (class index = value, range 0–12). It is **not** a
tile-level detector — pairing halves into tiles is left for a future model
revision.

## Input

`image` — 640×640 RGB `ImageType`. Vision rescales arbitrary photos for us
via `VNCoreMLRequest.imageCropAndScaleOption = .scaleFill`.

## Output

`var_1688` (the exporter's auto-named output) — `MLMultiArray` of shape
`[1, 17, 8400]`:

- Anchor count: 8400 (YOLOv11 grid at strides 8, 16, 32 over 640²).
- Channels 0–3: bounding box in 640-pixel space, format `(cx, cy, w, h)`.
- Channels 4–16: per-class scores (13 classes, one per pip value 0…12).

The exporter ran with `nms: False`, so the raw output contains overlapping
detections. `VisionPipCounter.decodeYOLO` thresholds by confidence and
`VisionPipCounter.nms` applies greedy non-max suppression in Swift.

Defaults: `confidenceThreshold = 0.30`, `iouThreshold = 0.45`. Tuned in
practice against `testdata/photos` in the web app; revisit when accuracy
shifts.

## Pip total

Each surviving detection contributes its class index to the total:
`total = Σ detection.classIndex`. Class 0 detections are blank halves and
add 0 — they're kept in the count so the UI can still show "N tiles" if
useful.

## Result shape

`PipCountResult.tiles` is a `[TileObservation]`. Since this model detects
halves (not tiles), each detection is encoded as `TileObservation(a: value, b: 0)`
so the existing `a + b` pip arithmetic still produces the correct total.
A future tile-pairing pass can populate both halves of each `TileObservation`.

## Conversion recipe

Source ONNX lives at
`~/Documents/code/platform/apps/mextrain/internal/staticfs/assets/models/v1-halves/domino.onnx`.

```python
# in a venv with torch, onnx2torch, coremltools installed
import torch, onnx2torch, coremltools as ct
m = onnx2torch.convert('path/to/domino.onnx')
m.eval()
example = torch.rand(1, 3, 640, 640)
traced = torch.jit.trace(m, example)
ml = ct.convert(
    traced,
    inputs=[ct.ImageType(name='image', shape=(1, 3, 640, 640),
                         scale=1/255.0, bias=[0, 0, 0])],
    minimum_deployment_target=ct.target.iOS17,
    convert_to='mlprogram',
)
ml.save('MexicanTrain/Vision/DominoDetector.mlpackage')
```

(coremltools 9.0 dropped direct ONNX conversion; the `onnx2torch → torchscript → coremltools`
roundtrip is the working path.)
