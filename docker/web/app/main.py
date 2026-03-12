"""
LLM Web Frontend
FastAPI application that provides a web interface for Ollama LLM
with PostgreSQL/pgvector for conversation history and semantic search.
"""

import os
import time
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from pydantic import BaseModel
from sqlalchemy import create_engine, text
from starlette.responses import Response

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Config ───────────────────────────────────────────────────
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://ollama:11434")
DB_HOST        = os.getenv("DB_HOST", "localhost")
DB_PORT        = os.getenv("DB_PORT", "5432")
DB_NAME        = os.getenv("DB_NAME", "vectordb")
DB_USER        = os.getenv("DB_USER", "postgres")
DB_PASSWORD    = os.getenv("DB_PASSWORD", "")
PORT           = int(os.getenv("PORT", "8080"))

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# ── Prometheus metrics ────────────────────────────────────────
REQUEST_COUNT = Counter(
    "web_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status_code"],
)
REQUEST_LATENCY = Histogram(
    "web_request_duration_seconds",
    "Request latency",
    ["endpoint"],
)
LLM_REQUEST_COUNT = Counter(
    "llm_requests_total",
    "Total LLM inference requests",
    ["model", "status"],
)
LLM_LATENCY = Histogram(
    "llm_request_duration_seconds",
    "LLM inference latency in seconds",
    ["model"],
    buckets=[1, 5, 10, 30, 60, 120, 300],
)
ACTIVE_CONNECTIONS = Gauge("web_active_connections", "Active WebSocket connections")

# ── DB engine ─────────────────────────────────────────────────
engine = None

def get_engine():
    global engine
    if engine is None:
        engine = create_engine(
            DATABASE_URL,
            pool_size=5,
            max_overflow=10,
            pool_pre_ping=True,
        )
    return engine

# ── Lifespan ──────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up — connecting to database...")
    try:
        eng = get_engine()
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
        logger.info("Database connection OK")
    except Exception as e:
        logger.warning(f"Database not yet available: {e}")
    yield
    logger.info("Shutting down...")

# ── App ───────────────────────────────────────────────────────
app = FastAPI(title="LLM Web Interface", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

try:
    app.mount("/static", StaticFiles(directory="static"), name="static")
except Exception:
    pass

# ── Models ────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    model: str = "llama3.2:1b"
    message: str
    stream: bool = False


class ChatResponse(BaseModel):
    response: str
    model: str
    duration_ms: float


# ── Endpoints ─────────────────────────────────────────────────

@app.get("/health")
async def health():
    """Health check for ALB."""
    return {"status": "ok", "service": "web"}


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/", response_class=HTMLResponse)
async def index():
    """Simple chat UI."""
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>LLM Chat</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: system-ui, sans-serif; background: #0f0f10; color: #e2e8f0; height: 100vh; display: flex; flex-direction: column; }
        header { padding: 1rem 2rem; background: #1a1a2e; border-bottom: 1px solid #2d2d44; }
        header h1 { font-size: 1.25rem; color: #a78bfa; }
        #chat { flex: 1; overflow-y: auto; padding: 1.5rem 2rem; display: flex; flex-direction: column; gap: 1rem; }
        .msg { max-width: 75%; padding: 0.75rem 1rem; border-radius: 12px; line-height: 1.5; }
        .user { background: #4c1d95; align-self: flex-end; border-bottom-right-radius: 4px; }
        .assistant { background: #1e293b; align-self: flex-start; border-bottom-left-radius: 4px; }
        form { display: flex; padding: 1rem 2rem; gap: 0.75rem; background: #1a1a2e; border-top: 1px solid #2d2d44; }
        input { flex: 1; padding: 0.75rem 1rem; border-radius: 8px; border: 1px solid #4c1d95; background: #0f0f10; color: #e2e8f0; font-size: 1rem; }
        button { padding: 0.75rem 1.5rem; border-radius: 8px; background: #7c3aed; color: white; border: none; cursor: pointer; font-size: 1rem; }
        button:disabled { opacity: 0.5; cursor: not-allowed; }
        select { padding: 0.75rem; border-radius: 8px; border: 1px solid #4c1d95; background: #0f0f10; color: #e2e8f0; }
      </style>
    </head>
    <body>
      <header><h1>🤖 LLM Chat Interface</h1></header>
      <div id="chat"></div>
      <form id="form">
        <select id="model">
          <option value="llama3.2:1b">llama3.2:1b</option>
          <option value="llama3.2:3b">llama3.2:3b</option>
          <option value="mistral:7b">mistral:7b</option>
        </select>
        <input id="msg" placeholder="Ask anything..." autocomplete="off"/>
        <button type="submit" id="btn">Send</button>
      </form>
      <script>
        const chat = document.getElementById('chat');
        const form = document.getElementById('form');
        const input = document.getElementById('msg');
        const btn = document.getElementById('btn');
        const modelSel = document.getElementById('model');

        function addMsg(text, role) {
          const d = document.createElement('div');
          d.className = 'msg ' + role;
          d.textContent = text;
          chat.appendChild(d);
          chat.scrollTop = chat.scrollHeight;
          return d;
        }

        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const msg = input.value.trim();
          if (!msg) return;
          input.value = '';
          btn.disabled = true;
          addMsg(msg, 'user');
          const placeholder = addMsg('Thinking…', 'assistant');
          try {
            const res = await fetch('/chat', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ model: modelSel.value, message: msg })
            });
            const data = await res.json();
            placeholder.textContent = data.response || data.detail || 'Error';
          } catch (err) {
            placeholder.textContent = 'Connection error: ' + err.message;
          } finally {
            btn.disabled = false;
            input.focus();
          }
        });
      </script>
    </body>
    </html>
    """


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """Forward chat request to Ollama."""
    start = time.time()
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{OLLAMA_API_URL}/api/generate",
                json={
                    "model": req.model,
                    "prompt": req.message,
                    "stream": False,
                },
            )
            resp.raise_for_status()
            data = resp.json()

        duration_ms = (time.time() - start) * 1000
        LLM_REQUEST_COUNT.labels(model=req.model, status="success").inc()
        LLM_LATENCY.labels(model=req.model).observe(time.time() - start)

        return ChatResponse(
            response=data.get("response", ""),
            model=req.model,
            duration_ms=round(duration_ms, 2),
        )
    except httpx.HTTPError as e:
        LLM_REQUEST_COUNT.labels(model=req.model, status="error").inc()
        raise HTTPException(status_code=502, detail=f"Ollama error: {str(e)}")


@app.get("/api/models")
async def list_models():
    """List available Ollama models."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(f"{OLLAMA_API_URL}/api/tags")
        resp.raise_for_status()
        return resp.json()


# ── Metrics middleware ────────────────────────────────────────
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status_code=response.status_code,
    ).inc()
    REQUEST_LATENCY.labels(endpoint=request.url.path).observe(duration)
    return response
