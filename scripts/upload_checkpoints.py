#!/usr/bin/env python3
"""
Upload local checkpoints to Hugging Face Hub.
Requires the huggingface_hub library and a write token.
"""

import os
import json
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
CHECKPOINTS = ROOT_DIR / "checkpoints"
MANIFEST_PATH = ROOT_DIR / "model_manifest.json"

def main():
    print("\n==============================================")
    print("      NZSL Fingerspelling - HF Uploader")
    print("==============================================\n")

    # 1. Load model manifest
    if not MANIFEST_PATH.exists():
        print(f"[ERROR] model_manifest.json not found at {MANIFEST_PATH}")
        sys.exit(1)

    try:
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            manifest = json.load(f)
    except Exception as e:
        print(f"[ERROR] Could not parse model_manifest.json: {e}")
        sys.exit(1)

    repo_id = manifest.get("repo_id")
    files_to_upload = manifest.get("files", [])

    if not repo_id:
        print("[ERROR] repo_id not specified in model_manifest.json")
        sys.exit(1)

    if not files_to_upload:
        print("[ERROR] No files specified in model_manifest.json")
        sys.exit(1)

    # 2. Verify files exist locally
    missing_files = []
    for filename in files_to_upload:
        local_path = CHECKPOINTS / filename
        if not local_path.exists():
            missing_files.append(filename)

    if missing_files:
        print("[ERROR] The following files are missing in checkpoints/:")
        for f in missing_files:
            print(f"  - {f}")
        print("\nPlease run the training notebook or pull them via Git LFS before uploading.")
        sys.exit(1)

    print(f"Target Repository: huggingface.co/{repo_id}")
    print(f"Number of Files:   {len(files_to_upload)}")
    print("Files to upload:")
    for f in files_to_upload:
        print(f"  - checkpoints/{f} ({os.path.getsize(CHECKPOINTS / f) / (1024*1024):.2f} MB)")
    print()

    # 3. Check for HF Token
    hf_token = os.getenv("HF_TOKEN") or os.getenv("HUGGINGFACE_HUB_TOKEN")
    if not hf_token:
        env_path = ROOT_DIR / ".env"
        if env_path.exists():
            try:
                with open(env_path, encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            if k.strip() in ("HF_TOKEN", "HUGGINGFACE_HUB_TOKEN"):
                                hf_token = v.strip()
                                break
            except Exception as e:
                print(f"[WARNING] Could not read .env file: {e}")

    if not hf_token:
        print("HF_TOKEN is not set in the environment.")
        print("Please obtain a token with WRITE access from https://huggingface.co/settings/tokens")
        try:
            hf_token = input("Enter your Hugging Face Token (WRITE access required): ").strip()
        except KeyboardInterrupt:
            print("\nUpload cancelled.")
            sys.exit(0)

    if not hf_token:
        print("[ERROR] No Hugging Face token provided. Upload aborted.")
        sys.exit(1)

    # 4. Perform upload using HfApi
    try:
        from huggingface_hub import HfApi
        api = HfApi(token=hf_token)
        
        # Verify repository exists or create it
        try:
            api.repo_info(repo_id=repo_id, repo_type="model")
            print(f"[OK]  Repository '{repo_id}' already exists.")
        except Exception:
            print(f"[INFO] Repository '{repo_id}' not found. Creating new model repository...")
            api.create_repo(repo_id=repo_id, repo_type="model", private=False)
            print(f"[OK]  Repository '{repo_id}' created successfully.")

        # Upload files in loop
        print("\nUploading checkpoints to Hugging Face Hub (this may take a few minutes)...")
        for filename in files_to_upload:
            local_path = CHECKPOINTS / filename
            print(f"Uploading {filename}...")
            api.upload_file(
                path_or_fileobj=str(local_path),
                path_in_repo=filename,
                repo_id=repo_id,
                repo_type="model"
            )
            print(f"✅ Uploaded {filename} successfully.")

        print("\n==============================================")
        print("🎉 All checkpoints uploaded successfully!")
        print(f"View models at: https://huggingface.co/{repo_id}")
        print("==============================================")

    except ImportError:
        print("[ERROR] huggingface_hub library is not installed. Please run:")
        print("  pip install huggingface-hub")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Upload failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
