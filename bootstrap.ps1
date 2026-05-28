<#
.SYNOPSIS
    Bootstrap and launch the NZSL Fingerspelling demo on your local machine.

.DESCRIPTION
    First run  : creates the 'nzsl-env' conda environment from environment.yml,
                 installs backend/requirements.txt, then starts the API server.
    Subsequent : verifies the environment and dependencies are healthy, then
                 starts the server directly -- skipping the creation steps.

    Run this script from the project root (the folder containing environment.yml).
    Usage: .\bootstrap.ps1

.NOTES
    Requires: conda (Miniconda3 or Anaconda), conda >= 4.9
    Port:     8000 (edit $PORT below to change)
#>

# -- Configuration -------------------------------------------------------------
$ENV_NAME = "nzsl-env"
$PORT     = 8000

# -- Helpers -------------------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host "`n  [>>] $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg"   -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [!!] $Msg"   -ForegroundColor Yellow }
function Fail {
    param([string]$Msg)
    Write-Host "`n  [ERROR] $Msg`n" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host "   NZSL Fingerspelling -- Bootstrap" -ForegroundColor White
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host ""

# -- 1. Working directory -------------------------------------------------------
Write-Step "Checking working directory..."
$required = @("environment.yml", "nzsl_frontend.html", "backend", "checkpoints")
$notFound = $required | Where-Object { -not (Test-Path $_) }
if ($notFound) {
    Fail ("Missing expected project items: $($notFound -join ', ')." +
          "`n       Run this script from the project root -- the folder that contains environment.yml." +
          "`n       Example: cd 'C:\path\to\nzsl-fingerspelling'; .\bootstrap.ps1")
}
Write-OK "Project root confirmed."

# -- 2. conda availability -----------------------------------------------------
Write-Step "Checking conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    Fail ("conda not found on PATH.`n" +
          "       Install Miniconda3 from https://docs.conda.io/en/latest/miniconda.html" +
          "`n       After installing, reopen this terminal and try again.")
}
$condaVersion = (conda --version 2>&1).ToString().Trim()
Write-OK $condaVersion

# -- 3. Conda environment setup ------------------------------------------------
Write-Step "Checking conda environment '$ENV_NAME'..."

$envList   = conda env list 2>&1
$envExists = [bool]($envList | Select-String "^$([regex]::Escape($ENV_NAME))\s")

if (-not $envExists) {

    # -- First-run path --------------------------------------------------------
    Write-Host ""
    Write-Host "  First run detected -- setting up '$ENV_NAME'." -ForegroundColor White
    Write-Host "  This may take several minutes depending on your internet speed." -ForegroundColor DarkGray
    Write-Host ""

    Write-Step "Creating conda environment from environment.yml..."
    conda env create -f environment.yml
    if ($LASTEXITCODE -ne 0) {
        Fail ("'conda env create' failed (exit code $LASTEXITCODE).`n" +
              "       Check the output above for details.`n" +
              "       Common causes: network issues, solver conflicts, or a corrupt environment.yml.")
    }
    Write-OK "Conda environment '$ENV_NAME' created."

    Write-Step "Installing backend API dependencies from backend\requirements.txt..."
    conda run -n $ENV_NAME pip install -r backend\requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Fail ("'pip install -r backend\requirements.txt' failed (exit code $LASTEXITCODE).`n" +
              "       Check the output above for details.")
    }
    Write-OK "Backend dependencies installed."

} else {

    # -- Subsequent-run path ---------------------------------------------------
    Write-OK "Environment '$ENV_NAME' already exists -- skipping creation."

    Write-Step "Verifying key packages..."

    # Conda and pip packages to check (as they appear in 'conda list' Name column)
    $corePackages    = @("numpy", "scikit-learn", "tensorflow", "mediapipe", "opencv-python")
    $backendPackages = @("fastapi", "uvicorn", "huggingface-hub")
    $allPackages     = $corePackages + $backendPackages

    $installedList = conda list -n $ENV_NAME 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "Could not query packages in environment '$ENV_NAME'. Is the environment healthy?"
    }

    $missing = @()
    foreach ($pkg in $allPackages) {
        $hit = $installedList | Select-String "^$([regex]::Escape($pkg))\s"
        if ($hit) {
            Write-OK "  $pkg"
        } else {
            Write-Warn "  $pkg -- not found in environment"
            $missing += $pkg
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Warn "Missing packages detected: $($missing -join ', ')"
        Write-Host "  Attempting to repair the environment..." -ForegroundColor Yellow
        Write-Host ""

        conda env update -n $ENV_NAME -f environment.yml --prune
        if ($LASTEXITCODE -ne 0) {
            Fail ("'conda env update' failed during repair.`n" +
                  "       To fully reset: conda env remove -n $ENV_NAME`n" +
                  "       Then rerun this script.")
        }
        conda run -n $ENV_NAME pip install -r backend\requirements.txt
        if ($LASTEXITCODE -ne 0) {
            Fail "pip install failed during repair. See output above."
        }
        Write-OK "Environment repaired successfully."
    }
}

# -- 4. Hugging Face token -----------------------------------------------------
Write-Step "Checking Hugging Face token..."

# Load .env file into current process environment if present
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $val = $parts[1].Trim()
                if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                    [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
                }
            }
        }
    }
    Write-OK ".env file loaded."
}

$hfToken = $env:HF_TOKEN
if (-not $hfToken) { $hfToken = $env:HUGGINGFACE_HUB_TOKEN }

if (-not $hfToken -or $hfToken -eq "hf_xxxxxxxxxxxxxxxxxxxx") {
    Write-Host ""
    Write-Host "  Hugging Face token (HF_TOKEN) is not set." -ForegroundColor Yellow
    Write-Host "  This token may be required to download model checkpoints from Hugging Face." -ForegroundColor DarkGray
    Write-Host "  (You can get a free token with Read access at https://huggingface.co/settings/tokens)" -ForegroundColor DarkGray
    Write-Host ""
    $inputToken = Read-Host "  Enter your Hugging Face Token (leave empty if the repo is public)"
    $inputToken = $inputToken.Trim()

    if ($inputToken) {
        $hfToken = $inputToken
        [System.Environment]::SetEnvironmentVariable("HF_TOKEN", $hfToken, "Process")
        $env:HF_TOKEN = $hfToken
        if (Test-Path ".env") {
            $content = Get-Content ".env"
            $hasToken = $false
            for ($i = 0; $i -lt $content.Count; $i++) {
                if ($content[$i] -match "^HF_TOKEN=") {
                    $content[$i] = "HF_TOKEN=$hfToken"
                    $hasToken = $true
                    break
                }
            }
            if ($hasToken) {
                $content | Set-Content ".env"
            } else {
                Add-Content -Path ".env" -Value "`nHF_TOKEN=$hfToken"
            }
        } else {
            Set-Content -Path ".env" -Value "HF_TOKEN=$hfToken"
        }
        Write-OK "Token saved to .env file and set for this session."
    }
}

if (-not $hfToken -or $hfToken -eq "hf_xxxxxxxxxxxxxxxxxxxx") {
    Write-Warn "HF_TOKEN is not set or is placeholder -- anonymous download fallback mode active."
} else {
    Write-OK "HF_TOKEN is set -- checkpoints will download using token."
}

# -- 5. Model checkpoint files -------------------------------------------------
Write-Step "Checking model checkpoints..."

$checkpoints = @(
    "checkpoints\svm_rbf_one_hand.joblib",
    "checkpoints\svm_rbf_two_hand.joblib",
    "checkpoints\random_forest_one_hand.joblib",
    "checkpoints\random_forest_two_hand.joblib",
    "checkpoints\knn_one_hand.joblib",
    "checkpoints\knn_two_hand.joblib",
    "checkpoints\mlp_sklearn_one_hand.joblib",
    "checkpoints\mlp_sklearn_two_hand.joblib",
    "checkpoints\mlp_keras_one_hand.h5",
    "checkpoints\mlp_keras_two_hand.h5",
    "checkpoints\keras_scaler_one_hand.pkl",
    "checkpoints\keras_scaler_two_hand.pkl",
    "checkpoints\label_classes_one_hand.npy",
    "checkpoints\label_classes_two_hand.npy"
)

$missingCp = $checkpoints | Where-Object { -not (Test-Path $_) }
if ($missingCp) {
    $list = ($missingCp | ForEach-Object { "         $_" }) -join "`n"
    Write-Warn "Missing checkpoint file(s):`n$list"
    Write-Warn "They will be downloaded from huggingface.co/harmandeeppal/nzsl-fingerspelling-recognition"
    Write-Warn "on first server start -- this may take a few minutes."
} else {
    Write-OK "All $($checkpoints.Count) checkpoint files present."
}

# -- 5. Sign reference images (non-fatal warning) -------------------------------
Write-Step "Checking sign reference images..."
$signsDir = "backend\static\signs"
if (-not (Test-Path $signsDir)) {
    Write-Warn "backend\static\signs\ folder not found."
    Write-Warn "The sign reference panel in the UI will be empty."
    Write-Warn "Rerun notebook\visuals_generation.ipynb to generate reference images."
} else {
    $pngCount = @(Get-ChildItem "$signsDir\*.png" -ErrorAction SilentlyContinue).Count
    if ($pngCount -eq 0) {
        Write-Warn "backend\static\signs\ is empty -- sign reference panel will be blank."
        Write-Warn "Rerun notebook\visuals_generation.ipynb to generate reference images."
    } else {
        Write-OK "$pngCount sign reference PNG(s) found."
    }
}

# -- 6. Port availability (non-fatal warning) ----------------------------------
Write-Step "Checking port $PORT..."
$portCheck = netstat -ano 2>$null | Select-String "[:.]$PORT\s"
if ($portCheck) {
    Write-Warn "Port $PORT may already be in use. Uvicorn might fail to bind."
    Write-Warn "Kill the conflicting process or change `$PORT at the top of this script."
} else {
    Write-OK "Port $PORT is available."
}

# -- 7. Launch the server ------------------------------------------------------
Write-Host ""
Write-Host "  --------------------------------------------" -ForegroundColor DarkGray
Write-Host "  All checks passed. Starting the server..." -ForegroundColor White
Write-Host ""
Write-Host "  Once you see 'Application startup complete.' below," -ForegroundColor DarkGray
Write-Host "  open this link in your browser:" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    http://localhost:$PORT" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Press CTRL+C to stop." -ForegroundColor DarkGray
Write-Host "  --------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# --no-capture-output streams uvicorn directly to this terminal in real time.
# Piping (2>&1 | ForEach-Object) silently buffers all output until exit -- do not use it.
conda run --no-capture-output -n $ENV_NAME `
    uvicorn backend.nzsl_api:app --reload --port $PORT

