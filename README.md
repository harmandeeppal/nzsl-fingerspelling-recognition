# NZSL Fingerspelling Recognition

## Quick Start — Run on Your Local Machine

The fastest way to get the demo running is the **bootstrap script**. It handles environment creation, dependency installation, and server startup in a single command.

### Prerequisites

- [Miniconda3](https://docs.conda.io/en/latest/miniconda.html) or Anaconda installed and on your PATH
- A terminal opened **in the project root** (the folder that contains `environment.yml`)

### First run

```powershell
.\bootstrap.ps1
```

On the first run the script will:

1. Verify you are in the correct project folder
2. Check that `conda` is available
3. Create the `nzsl-env` conda environment from `environment.yml` *(takes a few minutes)*
4. Install the backend API dependencies from `backend\requirements.txt` into that environment
5. Verify all model checkpoints are present in `checkpoints\`
6. Check that sign reference images exist in `backend\static\signs\`
7. Confirm port 8000 is free
8. Start the FastAPI server

Once the server is running, open your browser at:

```
http://localhost:8000
```

Press **CTRL+C** in the terminal to stop the server.

### Subsequent runs

Run the same command:

```powershell
.\bootstrap.ps1
```

The script detects that `nzsl-env` already exists and skips environment creation. It runs a quick package health check and launches the server immediately.

### If PowerShell blocks script execution

Run this once in the terminal, then retry:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Changing the port

Edit the `$PORT` variable at the top of `bootstrap.ps1`:

```powershell
$PORT = 8080   # change to any free port
```

Then visit `http://localhost:8080` instead.

---

## Overview

This demo uses a FastAPI backend and an HTML frontend for live NZSL/BSL fingerspelling recognition.

The frontend opens the webcam, extracts MediaPipe hand keypoints, and sends a 508-dimensional feature vector to the backend. The backend automatically routes the prediction to the correct one-hand or two-hand model based on the active hand slots in the keypoint vector.

The user selects only the model type:

- SVM
- Random Forest
- k-NN
- MLP sklearn
- MLP Keras

The backend decides whether to use the one-hand or two-hand version of that selected model.

---

## Prerequisites checklist

Before starting, confirm these files exist in the `checkpoints/` folder:

```text
checkpoints/
├── svm_rbf_one_hand.joblib
├── svm_rbf_two_hand.joblib
├── random_forest_one_hand.joblib
├── random_forest_two_hand.joblib
├── knn_one_hand.joblib
├── knn_two_hand.joblib
├── mlp_sklearn_one_hand.joblib
├── mlp_sklearn_two_hand.joblib
├── mlp_keras_one_hand.h5
├── mlp_keras_two_hand.h5
├── keras_scaler_one_hand.pkl
├── keras_scaler_two_hand.pkl
├── label_classes_one_hand.npy
├── label_classes_two_hand.npy
└── model_results.json
```

Optional report-comparison file:

```text
checkpoints/
└── pixel_svm_baseline.joblib
```

The raw-pixel baseline is mainly used for report/presentation comparison. The live demo uses the routed keypoint models.

If any routed model files are missing, rerun the full notebook export section.

---

## Step 1 — Generate skeleton reference images

The sign reference panel in the web UI shows a skeleton image for each predicted class.

These images should exist here:

```text
backend/
└── static/
    └── signs/
        ├── A.png
        ├── B.png
        ├── C.png
        └── ... one PNG per class
```

If this folder is empty, rerun the notebook section that generates skeleton reference PNGs.

---

## Step 2 — Activate the project environment

Open a terminal in the project root folder.

If you are using the VS Code virtual environment, activate it with:

```powershell
.\.venv\Scripts\Activate.ps1
```

If PowerShell blocks activation, run this once:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then activate again:

```powershell
.\.venv\Scripts\Activate.ps1
```

You should see `(.venv)` at the beginning of the terminal line.

---

## Step 3 — Install backend dependencies

Run this from the project root:

```powershell
pip install -r backend\requirements.txt
```

The backend requirements are only for the API/server side. Use the same Python environment that was used to train/export the models so that scikit-learn, TensorFlow, NumPy, and joblib versions remain compatible.

---

## Step 4 — Navigate to the project root

Make sure your terminal is in the project root, not inside the `backend/` folder.

You can verify you are in the correct folder by running:

```powershell
dir
```

You should see files/folders like:

```text
nzsl_frontend.html
backend/
checkpoints/
notebook/
outputs/
README.md
```

---

## Step 5 — Start the API server

Run:

```powershell
uvicorn backend.nzsl_api:app --reload --port 8000
```

A successful routed startup should show loaded one-hand and two-hand routes, for example:

```text
[OK]  svm_rbf_one_hand ← svm_rbf_one_hand.joblib
[OK]  svm_rbf_two_hand ← svm_rbf_two_hand.joblib
[OK]  random_forest_one_hand ← random_forest_one_hand.joblib
[OK]  random_forest_two_hand ← random_forest_two_hand.joblib
[OK]  knn_one_hand ← knn_one_hand.joblib
[OK]  knn_two_hand ← knn_two_hand.joblib
[OK]  mlp_sklearn_one_hand ← mlp_sklearn_one_hand.joblib
[OK]  mlp_sklearn_two_hand ← mlp_sklearn_two_hand.joblib
[OK]  mlp_keras_one_hand ← mlp_keras_one_hand.h5
[OK]  mlp_keras_two_hand ← mlp_keras_two_hand.h5
INFO:     Uvicorn running on http://127.0.0.1:8000
```

---

## Step 6 — Check API health

Open this in your browser:

```text
http://localhost:8000/health
```

Expected result:

```text
"status": "ok"
"version": "routed_one_two_hand"
```

It should also show loaded routes such as:

```text
"svm_rbf": ["one_hand", "two_hand"]
"random_forest": ["one_hand", "two_hand"]
"knn": ["one_hand", "two_hand"]
"mlp_sklearn": ["one_hand", "two_hand"]
```

Keras should show:

```text
"keras_models_loaded": ["one_hand", "two_hand"]
```

---

## Step 7 — Check available models

Open:

```text
http://localhost:8000/models
```

Expected model keys:

```text
svm_rbf
random_forest
knn
mlp_sklearn
mlp_keras
```

Each model should show:

```text
"available_routes": ["one_hand", "two_hand"]
"routing": "automatic_by_detected_hand_count"
```

This confirms that the frontend can still show simple model buttons while the backend handles one-hand/two-hand routing automatically.

---

## Step 8 — Open the web demo

Open:

```text
http://localhost:8000
```

Your browser will ask for webcam permission. Click **Allow**.

---

## Using the demo

| What you see | What it means |
|---|---|
| Status badge shows green `N models ready` | API loaded routed models successfully |
| `Webcam active — show your hands` | Camera is running |
| Skeleton appears on your hands | MediaPipe tracking is working |
| Large letter appears | Current prediction |
| Confidence percentage appears | Model confidence for the current prediction |
| Blue hold bar fills | Hold the sign steady to commit the letter |
| Letter appears in word builder | Stable sign has been committed |
| Reference sign panel updates | Shows skeleton reference for the predicted class |

Controls:

- **Skeleton only / Webcam + overlay** — toggle between black canvas and live video with skeleton overlay.
- **Model pills** — switch between SVM, Random Forest, k-NN, MLP sklearn, and MLP Keras.
- **Backspace** — remove the last committed letter.
- **Clear** — clear the whole word.
- **Speak word** — read the built word aloud.
- **Speak each committed letter** — toggle per-letter audio feedback.

---

## User guidance

For better live prediction:

- For one-hand signs, show one hand clearly.
- For two-hand signs, keep both hands visible and stable.
- Try to match the reference skeleton shown in the web interface.
- Hold the sign still until the confidence stabilises.
- Keep your hand inside the camera frame.
- Use good lighting and avoid cluttered backgrounds.
- Some visually similar signs may still be confused if the hand shape, angle, or finger spacing is different from the training examples.

---

## How routing works

The frontend sends:

```text
features + selected model key
```

The backend then:

```text
checks whether one or two hand slots are active
→ selects the one-hand or two-hand checkpoint
→ predicts the class
→ returns label, confidence, hand group, and routed model used
```

Example:

```text
selected model = svm_rbf
one hand detected → svm_rbf_one_hand.joblib
two hands detected → svm_rbf_two_hand.joblib
```

The frontend does not need a separate one-hand/two-hand selection button. The backend handles this automatically.

---

## Privacy note

The demo does not store webcam frames.

The live system uses MediaPipe skeleton/keypoint features for prediction instead of storing raw visual frames. This supports the privacy-preserving goal of the project.

The raw-pixel SVM baseline is kept for report/presentation comparison only. It helps compare privacy risk and model performance, but the live demo focuses on keypoint-based recognition.

---

## Stopping the server

Press:

```text
CTRL + C
```

in the terminal where Uvicorn is running.

---

## Troubleshooting

### API shows `no_models_loaded`

Check that the routed checkpoint files exist in:

```text
checkpoints/
```

If missing, rerun the full notebook export section.

---

### Model buttons do not appear

Check:

```text
http://localhost:8000/models
```

If it returns empty data, the backend did not load the checkpoint files correctly.

---

### API offline badge appears

The browser cannot reach the backend. Check:

- Uvicorn is still running.
- You are visiting `http://localhost:8000`, not `https://localhost:8000`.
- No other process is using port 8000.
- The terminal did not show Python errors.

To use a different port:

```powershell
uvicorn backend.nzsl_api:app --reload --port 8080
```

Then visit:

```text
http://localhost:8080
```

---

### Sign reference panel shows no image

The `backend/static/signs/` folder may be empty.

Rerun the notebook section that generates skeleton reference PNGs, then restart the server.

---

### `ModuleNotFoundError: No module named 'fastapi'`

Install backend dependencies:

```powershell
pip install -r backend\requirements.txt
```

---

### Keras model shows `[ERR]`

The most likely cause is a TensorFlow/Keras version mismatch.

Use the same Python environment used to train/export the models. Check TensorFlow with:

```powershell
python -c "import tensorflow as tf; print(tf.__version__)"
```

If the environment was changed after training, recreate or reactivate the correct project environment and try again.

---

### Webcam not detected

Try:

- Close Teams, Zoom, OBS, or any other app using the camera.
- Refresh the page.
- Check browser camera permission.
- On Windows, check: **Settings → Privacy & Security → Camera**.

---

### Predictions are unstable

Try:

- Hold the sign still.
- Improve lighting.
- Move hands closer to the camera.
- Match the reference skeleton.
- Keep both hands visible for two-hand signs.
- Keep the same left/right hand position while signing.

If predictions are still too unstable, increase `MIN_CONF` in `nzsl_frontend.html`.

---

## Quick reference commands

```powershell
# One-command launch (recommended)
.\bootstrap.ps1

# Manual launch
conda activate nzsl-env
uvicorn backend.nzsl_api:app --reload --port 8000

# Open browser
# http://localhost:8000
```
