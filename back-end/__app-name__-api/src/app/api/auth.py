"""Authentication API routes (Token-Mediating Backend).

Served same-origin with the PWA (via CloudFront `/auth/*`). The refresh token stays
server-side in the `sessions` table; the browser holds only an opaque session id in a
host-only HttpOnly cookie. Access tokens are returned in the response body.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session
from pydantic import BaseModel
from ..db import get_session
from ..auth import (
    cognito_signup,
    cognito_confirm_signup,
    cognito_login,
    cognito_refresh_session,
    cognito_revoke,
    decode_id_token,
    get_cookie_kwargs,
    settings,
)
from ..crud.user import user
from ..crud.session import session as session_store
from ..models.user import UserCreate

router = APIRouter(
    prefix="/auth",
    tags=["auth"],
)


class SignupRequest(BaseModel):
    email: str
    password: str


class ConfirmSignupRequest(BaseModel):
    email: str
    confirmation_code: str


class LoginRequest(BaseModel):
    email: str
    password: str


class AuthResponse(BaseModel):
    access_token: str
    access_token_expires_in_ms: int


@router.post("/signup/")
def signup(request: SignupRequest):
    """Sign up a new user."""
    cognito_signup(request.email, request.password)
    return {"message": "Registration email sent"}


@router.post("/confirm-signup/")
def confirm_signup(request: ConfirmSignupRequest):
    """Confirm user signup with verification code."""
    cognito_confirm_signup(request.email, request.confirmation_code)
    return {"message": "User confirmed successfully. You can now log in."}


@router.post("/login/", response_model=AuthResponse)
def login(request: LoginRequest, response: Response, db: Session = Depends(get_session)):
    """Authenticate, store the refresh token server-side, set an opaque session cookie."""
    cognito_response = cognito_login(request.email, request.password)

    auth_result = cognito_response.get("AuthenticationResult", {}) or {}
    id_token = auth_result.get("IdToken")
    access_token = auth_result.get("AccessToken")
    refresh_token = auth_result.get("RefreshToken")
    expires_in = auth_result.get("ExpiresIn", 3600)

    if not id_token or not access_token or not refresh_token:
        raise HTTPException(status_code=500, detail="Failed to get tokens from Cognito")

    decoded_token = decode_id_token(id_token)
    cognito_sub = decoded_token.get("sub")

    if not cognito_sub:
        raise HTTPException(status_code=500, detail="Failed to get Cognito sub from ID token")

    # Upsert user in database
    user_data = UserCreate(
        email=request.email,
        cognito_sub=cognito_sub,
        name=request.email.split("@")[0],  # Use email prefix as name
    )
    user.upsert_by_email(db, user_in=user_data)

    # Store the refresh token server-side; the cookie carries only the opaque session id.
    auth_session = session_store.create(
        db,
        cognito_sub=cognito_sub,
        refresh_token=refresh_token,
        ttl=settings.session_resume_cookie_ttl,
    )
    response.set_cookie(
        key=settings.session_resume_cookie_name,
        value=auth_session.id,
        **get_cookie_kwargs(),
    )

    return AuthResponse(access_token=access_token, access_token_expires_in_ms=expires_in * 1000)


@router.post("/resume/", response_model=AuthResponse)
def resume(request: Request, db: Session = Depends(get_session)):
    """Resume a session: look up the stored refresh token by session id, mint a new access token."""
    session_id = request.cookies.get(settings.session_resume_cookie_name)
    if not session_id:
        raise HTTPException(status_code=401, detail="No session cookie found")

    auth_session = session_store.get(db, session_id)
    if auth_session is None:
        raise HTTPException(status_code=401, detail="Session not found or expired")

    cognito_response = cognito_refresh_session(auth_session.refresh_token)

    auth_result = cognito_response.get("AuthenticationResult", {}) or {}
    access_token = auth_result.get("AccessToken")
    new_refresh_token = auth_result.get("RefreshToken")
    expires_in = auth_result.get("ExpiresIn", 3600)

    if not access_token:
        raise HTTPException(status_code=500, detail="Failed to get access token from Cognito")

    # If Cognito rotated the refresh token, persist the new one server-side.
    if new_refresh_token and new_refresh_token != auth_session.refresh_token:
        session_store.rotate(db, session_id=session_id, new_refresh_token=new_refresh_token)

    return AuthResponse(access_token=access_token, access_token_expires_in_ms=expires_in * 1000)


@router.post("/logout/")
def logout(request: Request, response: Response, db: Session = Depends(get_session)):
    """Delete the server-side session, best-effort revoke at Cognito, and clear the cookie."""
    session_id = request.cookies.get(settings.session_resume_cookie_name)
    if session_id:
        auth_session = session_store.get(db, session_id)
        refresh_token = auth_session.refresh_token if auth_session else None
        session_store.delete(db, session_id)
        if refresh_token:
            try:
                cognito_revoke(refresh_token)
            except HTTPException:
                pass  # best-effort; the session row is already gone

    response.delete_cookie(key=settings.session_resume_cookie_name, path="/")
    return {"message": "Logged out successfully"}
