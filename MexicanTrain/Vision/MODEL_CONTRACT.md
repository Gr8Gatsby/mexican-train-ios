# DominoDetector CoreML model contract

Drop a compiled `DominoDetector.mlmodelc` or source `DominoDetector.mlmodel`
into this directory (and add it to the Xcode target via `project.yml`
resources). `VisionPipCounter.loadFromBundle()` discovers it automatically;
otherwise `PipCounterFactory` falls back to `MockPipCounter`.

## Input

A single image. Vision passes pixel buffers; we use
`VNCoreMLRequest.imageCropAndScaleOption = .scaleFill`, so the model is
responsible for handling its own resize. Typical model input is **640×640 RGB**
(YOLOv11 default), but any size the Vision pipeline can satisfy works.

## Output

The model must emit object detections in the shape Vision parses as
`[VNRecognizedObjectObservation]`. Each detection's top-1 label encodes one
domino tile's half-values via a class string matching the loose regex:

```
^tile[-_]?(\d{1,2})[-_](\d{1,2})$
```

Examples:

- `tile-5-3`  → a 5-3 tile (8 pips)
- `tile_12_12` → a 12-12 tile (24 pips)
- `tile-0-0`  → a blank tile (0 pips)

The parser is forgiving: it extracts all digit groups from the class string and
takes the first two as (a, b). Order isn't significant — a tile-5-3 and
tile-3-5 result in the same pip count.

The half-values must each be in `[0, 12]`. Anything outside that range is
dropped silently.

## Per-detection confidence

`VNRecognizedObjectObservation.labels[0].confidence` is interpreted as the
detection's confidence in [0, 1]. `VisionPipCounter.consolidate` rolls them up
to a single bucket:

| Bucket  | Rule                                       |
| ------- | ------------------------------------------ |
| high    | avg ≥ 0.80 **and** min ≥ 0.50              |
| medium  | avg ≥ 0.50                                 |
| low     | everything else, including zero detections |

The UI uses the bucket to decide whether to nudge the user toward manual
correction.

## Where the trained model comes from

The web app's `~/Documents/code/platform/apps/mextrain/ml/` folder is the
source of the training pipeline. Convert the final PyTorch checkpoint to
CoreML via `coremltools`:

```bash
# from a Python env with coremltools and ultralytics installed
yolo export model=runs/train/exp/weights/best.pt format=coreml nms=True imgsz=640
```

The resulting `.mlpackage` / `.mlmodel` should be copied here and added to
the target. Verify the class label format matches the contract above; if the
training labels use a different scheme, update `VisionPipCounter.parseTileClass`
to match — that's the one extension point.
