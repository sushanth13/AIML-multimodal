# fastapi app for image captioning

from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from uuid import uuid4
import json
import os
import shutil

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="Image Captioning API")


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATHS = []
UPLOAD_DIR = BASE_DIR / "uploads"
DATA_DIR = BASE_DIR / "app_data"
HISTORY_FILE = DATA_DIR / "history.json"

UPLOAD_DIR.mkdir(exist_ok=True)
DATA_DIR.mkdir(exist_ok=True)

history_lock = Lock()


model = None
model_load_error = None
active_model_path = None
generate_caption = None
load_model = None

custom_model_path = os.getenv("CAPTION_MODEL_PATH")
if custom_model_path:
    custom_model_candidate = Path(custom_model_path)
    if not custom_model_candidate.is_absolute():
        custom_model_candidate = BASE_DIR / custom_model_candidate
    MODEL_PATHS.append(custom_model_candidate)

MODEL_PATHS.extend([
    BASE_DIR / "final_model_clean.pth",
    BASE_DIR / "final_model.pth",
])

try:
    from model import generate_caption, load_model
except Exception as exc:  # pragma: no cover - UI should still load
    model_load_error = str(exc)


def load_first_available_model():
    attempted = []

    for candidate in MODEL_PATHS:
        candidate_name = candidate.name if candidate.parent == BASE_DIR else str(candidate)

        if not candidate.exists():
            attempted.append(f"{candidate_name}: missing")
            continue

        try:
            loaded_model = load_model(str(candidate))
            return loaded_model, candidate_name, None
        except Exception as exc:
            attempted.append(f"{candidate_name}: {exc}")

    return None, None, " | ".join(attempted)


if load_model is not None and model_load_error is None:
    model, active_model_path, model_load_error = load_first_available_model()


app.mount("/uploads", StaticFiles(directory=str(UPLOAD_DIR)), name="uploads")


def load_history():
    if not HISTORY_FILE.exists():
        return []

    try:
        return json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []


def save_history(items) -> None:
    HISTORY_FILE.write_text(json.dumps(items, indent=2), encoding="utf-8")


def build_saved_name(filename: str) -> str:
    safe_name = Path(filename or "upload").name
    suffix = Path(safe_name).suffix or ".jpg"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    return f"{timestamp}_{uuid4().hex}{suffix}"


@app.get("/")
def home():
    return FileResponse(BASE_DIR / "index.html")


@app.get("/history")
def history_page():
    return FileResponse(BASE_DIR / "history.html")


@app.get("/api/history")
def history_data():
    return {"items": load_history()}


@app.get("/health")
def health():
    return {
        "message": "Image Captioning API is running",
        "model_ready": model is not None and model_load_error is None,
        "model_path": active_model_path,
        "model_error": model_load_error,
    }


@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    original_name = Path(file.filename or "upload").name
    saved_name = build_saved_name(original_name)
    file_path = UPLOAD_DIR / saved_name

    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    if model_load_error or model is None:
        try:
            file_path.unlink()
        except OSError:
            pass

        raise HTTPException(
            status_code=503,
            detail=f"Model is unavailable right now. {model_load_error}",
        )

    try:
        caption = generate_caption(model, str(file_path))
    except Exception as exc:
        try:
            file_path.unlink()
        except OSError:
            pass

        raise HTTPException(
            status_code=500,
            detail=f"Caption generation failed: {exc}",
        ) from exc

    history_item = {
        "id": uuid4().hex,
        "filename": original_name,
        "saved_name": saved_name,
        "image_url": f"/uploads/{saved_name}",
        "caption": caption,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    with history_lock:
        items = load_history()
        items.insert(0, history_item)
        save_history(items)

    return history_item


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="127.0.0.1",
        port=8765,
        reload=True,
    )
