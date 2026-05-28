from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import os
import shutil

ROOT_DIR      = Path(__file__).resolve().parent.parent
CHECKPOINTS   = ROOT_DIR / 'checkpoints'

# ── Hugging Face Bootstrapping ─────────────────────────────────────────────────
def bootstrap_artifacts():
    manifest_path = ROOT_DIR / 'model_manifest.json'
    if not manifest_path.exists():
        print(f'[WARN] model_manifest.json not found at {manifest_path}. Skipping Hugging Face download.')
        return

    try:
        with open(manifest_path, encoding='utf-8') as f:
            manifest = json.load(f)
    except Exception as e:
        print(f'[ERR] Could not parse model_manifest.json: {e}')
        return

    repo_id = manifest.get('repo_id', 'harmandeeppal/nzsl-fingerspelling-recognition')
    revision = manifest.get('revision', 'main')
    files_to_download = manifest.get('files', [])

    CHECKPOINTS.mkdir(parents=True, exist_ok=True)
    hf_token = os.getenv("HF_TOKEN") or os.getenv("HUGGINGFACE_HUB_TOKEN")

    missing_files = [f for f in files_to_download if not (CHECKPOINTS / f).exists()]
    if not missing_files:
        print('[OK]  All checkpoints present locally.')
        return

    print(f'[INFO] Found {len(missing_files)} missing checkpoint(s). Initiating Hugging Face download from {repo_id}...')
    try:
        from huggingface_hub import hf_hub_download
        for filename in missing_files:
            target_path = CHECKPOINTS / filename
            print(f'[INFO] Downloading {filename}...')
            downloaded_path = hf_hub_download(
                repo_id=repo_id,
                filename=filename,
                revision=revision,
                token=hf_token,
                local_dir=str(CHECKPOINTS)
            )
            # Ensure the downloaded file matches target_path
            downloaded = Path(downloaded_path)
            if downloaded.resolve() != target_path.resolve():
                shutil.copy2(downloaded, target_path)
            print(f'[OK]  Downloaded {filename}')
    except ImportError:
        print('[ERR] huggingface_hub library not installed. Cannot download missing checkpoints.')
    except Exception as e:
        print(f'[ERR] Hugging Face download failed: {e}')
        print('[WARN] Running in fallback mode. The server may fail if key checkpoints are missing.')

bootstrap_artifacts()

SIGNS_DIR     = Path(__file__).resolve().parent / 'static' / 'signs'
FRONTEND_HTML = ROOT_DIR / 'nzsl_frontend.html'
RESULTS_JSON  = CHECKPOINTS / 'model_results.json'

DISPLAY_NAMES = {
    'svm_rbf':       'SVM (RBF)',
    'random_forest': 'Random Forest',
    'knn':           'k-NN',
    'mlp_sklearn':   'MLP (sklearn)',
    'mlp_keras':     'MLP (Keras)',
}

HAND_GROUPS = ['one_hand', 'two_hand']

# ── Load accuracy results ─────────────────────────────────────────────────────
MODEL_RESULTS: dict[str, Any] = {}

if RESULTS_JSON.exists():
    try:
        with open(RESULTS_JSON, encoding='utf-8') as f:
            MODEL_RESULTS = json.load(f)
        print(f'[OK]  model results <- {RESULTS_JSON.name}')
    except Exception as e:
        print(f'[ERR] Could not load {RESULTS_JSON.name}: {e}')


# ── Helper: infer one-hand/two-hand from 508-dim feature vector ────────────────
def infer_hand_group_from_features(features: np.ndarray) -> tuple[str, int]:
    """
    First 254 values = left-hand slot.
    Last 254 values  = right-hand slot.

    If one slot is all zeros, only one hand is detected.
    If both slots contain values, two hands are detected.
    """
    if features.shape[1] != 508:
        raise HTTPException(
            status_code=400,
            detail=f'Expected 508 features, got {features.shape[1]}'
        )

    flat = features.reshape(-1)

    left_present  = bool(np.any(np.abs(flat[:254]) > 1e-8))
    right_present = bool(np.any(np.abs(flat[254:]) > 1e-8))

    hand_count = int(left_present) + int(right_present)

    if hand_count == 0:
        raise HTTPException(
            status_code=400,
            detail='No valid hand features found in request'
        )

    hand_group = 'one_hand' if hand_count == 1 else 'two_hand'

    return hand_group, hand_count


# ── Load sklearn routed models ────────────────────────────────────────────────
# Expected files:
# svm_rbf_one_hand.joblib, svm_rbf_two_hand.joblib, etc.
ROUTED_SKLEARN_MODELS: dict[str, dict[str, Any]] = {
    'svm_rbf': {},
    'random_forest': {},
    'knn': {},
    'mlp_sklearn': {},
}

for model_key in list(ROUTED_SKLEARN_MODELS.keys()):
    for hand_group in HAND_GROUPS:
        ckpt_path = CHECKPOINTS / f'{model_key}_{hand_group}.joblib'

        if not ckpt_path.exists():
            print(f'[MISS] {model_key}_{hand_group} <- {ckpt_path.name}')
            continue

        try:
            bundle = joblib.load(ckpt_path)
            ROUTED_SKLEARN_MODELS[model_key][hand_group] = bundle
            print(f'[OK]  {model_key}_{hand_group} <- {ckpt_path.name}')
        except Exception as e:
            print(f'[ERR] {ckpt_path.name}: {e}')

# Remove model keys where neither one-hand nor two-hand checkpoint loaded.
ROUTED_SKLEARN_MODELS = {
    model_key: groups
    for model_key, groups in ROUTED_SKLEARN_MODELS.items()
    if groups
}


# ── Load Keras routed models ──────────────────────────────────────────────────
# Expected files:
# mlp_keras_one_hand.h5, mlp_keras_two_hand.h5
# keras_scaler_one_hand.pkl, keras_scaler_two_hand.pkl
# label_classes_one_hand.npy, label_classes_two_hand.npy

KERAS_MODELS: dict[str, Any] = {}
KERAS_SCALERS: dict[str, Any] = {}
KERAS_LABELS: dict[str, list[str]] = {}

for hand_group in HAND_GROUPS:
    keras_model_path  = CHECKPOINTS / f'mlp_keras_{hand_group}.h5'
    keras_scaler_path = CHECKPOINTS / f'keras_scaler_{hand_group}.pkl'
    keras_labels_path = CHECKPOINTS / f'label_classes_{hand_group}.npy'

    if not (keras_model_path.exists() and keras_scaler_path.exists() and keras_labels_path.exists()):
        print(f'[MISS] mlp_keras_{hand_group} files')
        continue

    try:
        import tensorflow as tf

        KERAS_MODELS[hand_group] = tf.keras.models.load_model(str(keras_model_path))
        KERAS_SCALERS[hand_group] = joblib.load(keras_scaler_path)
        KERAS_LABELS[hand_group] = np.load(keras_labels_path, allow_pickle=True).tolist()

        print(f'[OK]  mlp_keras_{hand_group} <- {keras_model_path.name}')
    except Exception as e:
        print(f'[ERR] mlp_keras_{hand_group}: {e}')



def _sign_sort_key(path: Path) -> tuple[int, Any]:
    """Sort numeric signs first, then alphabetic signs."""
    stem = path.stem

    if stem.isdigit():
        return (0, int(stem))

    return (1, stem.upper())



# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(title='NZSL Fingerspelling Recognition API', version='2.0.0-routed')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_methods=['*'],
    allow_headers=['*'],
)

if SIGNS_DIR.exists():
    app.mount('/signs', StaticFiles(directory=str(SIGNS_DIR)), name='signs')


class PredictRequest(BaseModel):
    features: list[float]
    model_key: str = 'svm_rbf'


@app.get('/')
def root():
    if not FRONTEND_HTML.exists():
        raise HTTPException(status_code=404, detail='nzsl_frontend.html not found at project root')
    return FileResponse(str(FRONTEND_HTML))


@app.get('/health')
def health():
    loaded_sklearn = {
        model_key: sorted(groups.keys())
        for model_key, groups in ROUTED_SKLEARN_MODELS.items()
    }

    loaded_keras = sorted(KERAS_MODELS.keys())

    total_loaded = sum(len(v) for v in loaded_sklearn.values()) + len(loaded_keras)

    return {
        'status': 'ok' if total_loaded else 'no_models_loaded',
        'version': 'routed_one_two_hand',
        'checkpoints': str(CHECKPOINTS),
        'sklearn_models_loaded': loaded_sklearn,
        'keras_models_loaded': loaded_keras,
    }


def _get_metric_for_model(model_key: str, metric: str) -> float:
    """
    For frontend display, show the average of one-hand and two-hand results
    when both are available.
    """
    values = []

    for hand_group in HAND_GROUPS:
        routed_key = f'{model_key}_{hand_group}'
        result = MODEL_RESULTS.get(routed_key, {})
        if metric in result:
            values.append(float(result[metric]))

    if not values:
        return 0.0

    return round(sum(values) / len(values), 4)


@app.get('/models')
def models():
    result: dict[str, Any] = {}

    # Sklearn routed models
    for model_key, groups in ROUTED_SKLEARN_MODELS.items():
        available_groups = sorted(groups.keys())

        result[model_key] = {
            'display_name': DISPLAY_NAMES.get(model_key, model_key),
            'accuracy': _get_metric_for_model(model_key, 'accuracy'),
            'weighted_f1': _get_metric_for_model(model_key, 'weighted_f1'),
            'available_routes': available_groups,
            'routing': 'automatic_by_detected_hand_count',
        }

    # Keras routed model
    if KERAS_MODELS:
        result['mlp_keras'] = {
            'display_name': DISPLAY_NAMES['mlp_keras'],
            'accuracy': _get_metric_for_model('mlp_keras', 'accuracy'),
            'weighted_f1': _get_metric_for_model('mlp_keras', 'weighted_f1'),
            'available_routes': sorted(KERAS_MODELS.keys()),
            'routing': 'automatic_by_detected_hand_count',
        }

    return result



@app.get('/signs-list')
def signs_list():
    """Return all available sign reference PNG filenames for the frontend gallery."""
    if not SIGNS_DIR.exists():
        return {
            'count': 0,
            'signs': [],
            'message': 'Sign reference directory not found'
        }

    sign_files = sorted(SIGNS_DIR.glob('*.png'), key=_sign_sort_key)

    return {
        'count': len(sign_files),
        'signs': [p.name for p in sign_files]
    }


@app.post('/predict')
def predict(req: PredictRequest):
    feats = np.array(req.features, dtype=np.float32).reshape(1, -1)

    hand_group, hand_count = infer_hand_group_from_features(feats)
    key = req.model_key

    # ── Keras routed prediction ───────────────────────────────────────────────
    if key == 'mlp_keras':
        if hand_group not in KERAS_MODELS:
            raise HTTPException(
                status_code=503,
                detail=f'Keras model for {hand_group} not loaded'
            )

        scaler = KERAS_SCALERS[hand_group]
        model = KERAS_MODELS[hand_group]
        classes = KERAS_LABELS[hand_group]

        scaled = scaler.transform(feats)
        probs = model.predict(scaled, verbose=0)[0]
        idx = int(np.argmax(probs))

        return {
            'label': classes[idx],
            'confidence': round(float(probs[idx]), 4),
            'model_key': key,
            'hand_count': hand_count,
            'hand_group': hand_group,
            'routed_model_used': f'{key}_{hand_group}',
        }

    # ── Sklearn routed prediction ─────────────────────────────────────────────
    if key not in ROUTED_SKLEARN_MODELS:
        raise HTTPException(status_code=400, detail=f"Model '{key}' not loaded")

    if hand_group not in ROUTED_SKLEARN_MODELS[key]:
        raise HTTPException(
            status_code=503,
            detail=f"Model '{key}' does not have a loaded {hand_group} checkpoint"
        )

    bundle = ROUTED_SKLEARN_MODELS[key][hand_group]

    clf = bundle['model']
    classes = bundle['classes']

    pred = clf.predict(feats)[0]

    label = classes[int(pred)] if isinstance(pred, (int, np.integer)) else str(pred)

    if hasattr(clf, 'predict_proba'):
        conf = float(np.max(clf.predict_proba(feats)))
    else:
        conf = 1.0

    return {
        'label': label,
        'confidence': round(conf, 4),
        'model_key': key,
        'hand_count': hand_count,
        'hand_group': hand_group,
        'routed_model_used': f'{key}_{hand_group}',
    }