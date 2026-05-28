#!/usr/bin/env bash

# ── Configuration ─────────────────────────────────────────────────────────────
ENV_NAME="nzsl-env"
PORT=8000

# Colors for terminal output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}  ════════════════════════════════════════════${NC}"
echo -e "   NZSL Fingerspelling — Linux/Codespaces Bootstrap"
echo -e "${CYAN}  ════════════════════════════════════════════${NC}"
echo ""

# Helper functions
write_step() { echo -e "\n  [>>] $1"; }
write_ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
write_warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
fail() {
    echo -e "\n  ${RED}[ERROR]${NC} $1\n"
    exit 1
}

# ── 1. Working directory check ──────────────────────────────────────────────────
write_step "Checking working directory..."
required=("environment.yml" "nzsl_frontend.html" "backend" "model_manifest.json")
missing=()
for item in "${required[@]}"; do
    if [ ! -e "$item" ]; then
        missing+=("$item")
    fi
done

if [ ${#missing[@]} -ne 0 ]; then
    fail "Missing expected project items: ${missing[*]}
       Run this script from the project root — the folder containing environment.yml.
       Example: cd /workspace/nzsl-fingerspelling && ./bootstrap.sh"
fi
write_ok "Project root confirmed."

# ── 2. Conda availability check ───────────────────────────────────────────────
write_step "Checking conda..."
if ! command -v conda &> /dev/null; then
    fail "conda not found on PATH.
       Please install conda (Miniconda/Anaconda) and ensure it is activated before running this script."
fi
conda_version=$(conda --version 2>&1)
write_ok "$conda_version"

# ── 3. Conda environment setup ────────────────────────────────────────────────
write_step "Checking conda environment '$ENV_NAME'..."
if ! conda env list | grep -q "^$ENV_NAME[[:space:]]"; then
    # First-run path
    echo ""
    echo -e "  First run detected — setting up '$ENV_NAME'."
    echo -e "  This may take several minutes depending on your connection speed."
    echo ""

    write_step "Creating conda environment from environment.yml..."
    conda env create -f environment.yml
    if [ $? -ne 0 ]; then
        fail "'conda env create' failed. Check output above for details."
    fi
    write_ok "Conda environment '$ENV_NAME' created."

    write_step "Installing backend API dependencies from backend/requirements.txt..."
    conda run -n "$ENV_NAME" pip install -r backend/requirements.txt
    if [ $? -ne 0 ]; then
        fail "'pip install -r backend/requirements.txt' failed."
    fi
    write_ok "Backend API dependencies installed."
else
    # Subsequent-run path
    write_ok "Environment '$ENV_NAME' already exists — skipping creation."

    write_step "Verifying key packages..."
    all_packages=("numpy" "scikit-learn" "tensorflow" "mediapipe" "fastapi" "uvicorn" "huggingface-hub")
    missing_pkgs=()

    installed_list=$(conda list -n "$ENV_NAME")
    for pkg in "${all_packages[@]}"; do
        if echo "$installed_list" | grep -q "^$pkg[[:space:]]"; then
            write_ok "  $pkg"
        else
            write_warn "  $pkg — not found in environment"
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        echo ""
        write_warn "Missing packages detected: ${missing_pkgs[*]}"
        echo "  Attempting to repair the environment..."
        echo ""

        conda env update -n "$ENV_NAME" -f environment.yml --prune
        if [ $? -ne 0 ]; then
            fail "'conda env update' failed. Fully reset via 'conda env remove -n $ENV_NAME' and retry."
        fi
        conda run -n "$ENV_NAME" pip install -r backend/requirements.txt
        if [ $? -ne 0 ]; then
            fail "pip install failed during repair."
        fi
        write_ok "Environment repaired successfully."
    fi
fi

# ── 3.5 OpenCV import verification ────────────────────────────────────────────
write_step "Verifying OpenCV import..."
if ! conda run -n "$ENV_NAME" python -c "import cv2" >/dev/null 2>&1; then
    write_warn "OpenCV import failed. This is common in headless environments (like Codespaces)."
    write_step "Reinstalling headless OpenCV to resolve conflicts..."
    conda run -n "$ENV_NAME" pip uninstall -y opencv-python opencv-python-headless >/dev/null 2>&1
    conda run -n "$ENV_NAME" pip install opencv-python-headless
    
    if conda run -n "$ENV_NAME" python -c "import cv2" >/dev/null 2>&1; then
        write_ok "OpenCV imported successfully after headless installation."
    else
        write_warn "OpenCV import still failing. Attempting to install system GL dependencies (libgl1)..."
        if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y libgl1
        else
            apt-get update && apt-get install -y libgl1
        fi
        
        if conda run -n "$ENV_NAME" python -c "import cv2" >/dev/null 2>&1; then
            write_ok "OpenCV imported successfully after installing system dependencies."
        else
            fail "Unable to import OpenCV (cv2). Please check the error messages above."
        fi
    fi
else
    write_ok "OpenCV import verified."
fi

# ── 4. Hugging Face token check & prompting ───────────────────────────────────
write_step "Checking Hugging Face token..."

# Load .env file if present
if [ -f .env ]; then
    # Load vars ignoring comment lines
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip comments and whitespace
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$clean_line" ]; then
            key=$(echo "$clean_line" | cut -d= -f1 | xargs)
            val=$(echo "$clean_line" | cut -d= -f2- | xargs)
            if [ -z "${!key}" ]; then
                export "$key=$val"
            fi
        fi
    done < .env
    write_ok ".env file loaded."
fi

hf_token="${HF_TOKEN:-$HUGGINGFACE_HUB_TOKEN}"

if [ -z "$hf_token" ] || [ "$hf_token" = "hf_xxxxxxxxxxxxxxxxxxxx" ]; then
    echo ""
    echo -e "${YELLOW}  Hugging Face token (HF_TOKEN) is not set.${NC}"
    echo -e "  This token may be required to download model checkpoints from Hugging Face."
    echo -e "  (You can get a free token with Read access at https://huggingface.co/settings/tokens)"
    echo ""
    read -r -p "  Enter your Hugging Face Token (leave empty if the repo is public): " input_token
    input_token=$(echo "$input_token" | xargs)

    if [ -n "$input_token" ]; then
        hf_token="$input_token"
        export HF_TOKEN="$hf_token"
        if [ -f .env ]; then
            if grep -q "^HF_TOKEN=" .env; then
                # Use sed to replace in-place
                sed -i 's/^HF_TOKEN=.*/HF_TOKEN='"$hf_token"'/' .env
            else
                echo "HF_TOKEN=$hf_token" >> .env
            fi
        else
            echo "HF_TOKEN=$hf_token" > .env
        fi
        write_ok "Token saved to .env file and set for this session."
    fi
fi

if [ -z "$hf_token" ] || [ "$hf_token" = "hf_xxxxxxxxxxxxxxxxxxxx" ]; then
    write_warn "HF_TOKEN is not set or is placeholder — anonymous download fallback mode active."
else
    write_ok "HF_TOKEN is set — checkpoints will download using token."
fi

# ── 5. Checkpoints check ──────────────────────────────────────────────────────
write_step "Checking model checkpoints..."
checkpoints=(
    "checkpoints/svm_rbf_one_hand.joblib"
    "checkpoints/svm_rbf_two_hand.joblib"
    "checkpoints/random_forest_one_hand.joblib"
    "checkpoints/random_forest_two_hand.joblib"
    "checkpoints/knn_one_hand.joblib"
    "checkpoints/knn_two_hand.joblib"
    "checkpoints/mlp_sklearn_one_hand.joblib"
    "checkpoints/mlp_sklearn_two_hand.joblib"
    "checkpoints/mlp_keras_one_hand.h5"
    "checkpoints/mlp_keras_two_hand.h5"
    "checkpoints/keras_scaler_one_hand.pkl"
    "checkpoints/keras_scaler_two_hand.pkl"
    "checkpoints/label_classes_one_hand.npy"
    "checkpoints/label_classes_two_hand.npy"
)

missing_cp=()
for cp in "${checkpoints[@]}"; do
    if [ ! -f "$cp" ]; then
        missing_cp+=("$cp")
    fi
done

if [ ${#missing_cp[@]} -ne 0 ]; then
    echo "  Missing checkpoint file(s):"
    for m in "${missing_cp[@]}"; do
        echo "         $m"
    done
    write_warn "They will be downloaded from huggingface.co/harmandeeppal/nzsl-fingerspelling-recognition"
    write_warn "on first server start — this may take a few minutes."
else
    write_ok "All ${#checkpoints[@]} checkpoint files present."
fi

# ── 6. Port check (non-fatal warning) ─────────────────────────────────────────
write_step "Checking port $PORT..."
port_in_use=false
if command -v lsof &> /dev/null; then
    if lsof -i :$PORT &> /dev/null; then
        port_in_use=true
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":$PORT "; then
        port_in_use=true
    fi
fi

if [ "$port_in_use" = true ]; then
    write_warn "Port $PORT may already be in use. Uvicorn might fail to bind."
    write_warn "Kill the conflicting process or free up the port before continuing."
else
    write_ok "Port $PORT is available."
fi

# ── 7. Launch server ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${GRAY}────────────────────────────────────────────${NC}"
echo -e "  All checks passed. Starting the server..."
echo ""
echo -e "  On first run, missing checkpoints are downloaded from Hugging Face."
echo -e "  Once you see 'Application startup complete.' below,"
echo -e "  open this link in your browser:"
echo ""
if [ -n "$CODESPACES" ]; then
    echo -e "    ${CYAN}Open the forwarded port 8000 via GitHub Codespaces pop-up / Ports tab${NC}"
else
    echo -e "    ${CYAN}http://localhost:$PORT${NC}"
fi
echo ""
echo -e "  Press CTRL+C to stop."
echo -e "  ${GRAY}────────────────────────────────────────────${NC}"
echo ""

# Run Uvicorn through conda
conda run --no-capture-output -n "$ENV_NAME" \
    uvicorn backend.nzsl_api:app --host 0.0.0.0 --port "$PORT"
