from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .db import init_db
from .api import todos_router, auth_router
from .settings import settings

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

def create_app() -> FastAPI:
    app = FastAPI(
        title="<{{ app_name }}> API",
        version="1.0.0",
        lifespan=lifespan
    )

    # Router topology depends on which component this process is (see settings.app_component).
    # Local dev mounts both so a single uvicorn serves everything.
    is_local = settings.app_env == "local"

    if is_local or settings.app_component == "auth":
        # Auth component is served same-origin with the PWA (CloudFront /auth/*) — no CORS.
        app.include_router(auth_router)

    if is_local or settings.app_component != "auth":
        # API component is a public Function URL; the browser sends a Bearer token, never a
        # cookie.
        app.include_router(todos_router)

    if is_local:
        # Deployed, the api component's CORS is owned by its Lambda Function URL config
        # (infra/lambda.tf) — that layer answers preflights without invoking the function and
        # attaches the response headers itself, so adding the middleware here as well would be
        # a second, divergent source of truth. Local dev has no Function URL in front of it,
        # so the middleware is what lets the Vite dev server call the API cross-origin.
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins_list,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    @app.get("/")
    def root():
        return {
            "message": "Welcome to the <{{ app_name }}> API",
            "version": "1.0.0",
            "docs": "/docs"
        }

    return app

app = create_app()
