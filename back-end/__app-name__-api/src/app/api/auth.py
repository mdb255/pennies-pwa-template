"""Authentication API routes."""

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.security import HTTPBearer
from sqlmodel import Session
from pydantic import BaseModel
from ..db import get_session
from ..auth import (
    cognito_signup,
    cognito_confirm_signup,
    cognito_login,
    cognito_refresh_session,
    decode_id_token,
    get_cookie_kwargs,
    settings,
)
from ..crud.user import user
from ..models.user import UserCreate

router = APIRouter(
    prefix="/auth",
    tags=["auth"],
)

security = HTTPBearer(auto_error=False)


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
def login(request: LoginRequest, db: Session = Depends(get_session)):
    """Authenticate user and create session."""
    # Authenticate with Cognito
    cognito_response = cognito_login(request.email, request.password)
    
    id_token = cognito_response.get("AuthenticationResult", {}).get("IdToken")
    access_token = cognito_response.get("AuthenticationResult", {}).get("AccessToken")
    refresh_token = cognito_response.get("AuthenticationResult", {}).get("RefreshToken")
    expires_in = cognito_response.get("AuthenticationResult", {}).get("ExpiresIn", 3600)
    
    if not id_token or not access_token or not refresh_token:
        raise HTTPException(status_code=500, detail="Failed to get tokens from Cognito")
    
    # Decode ID token to get user info
    decoded_token = decode_id_token(id_token)
    cognito_sub = decoded_token.get("sub")
    
    if not cognito_sub:
        raise HTTPException(status_code=500, detail="Failed to get Cognito sub from ID token")
    
    # Upsert user in database
    user_data = UserCreate(
        email=request.email,
        cognito_sub=cognito_sub,
        name=request.email.split("@")[0]  # Use email prefix as name
    )
    user.upsert_by_email(db, user_in=user_data)
    
    # Create response
    response = Response(content=f'{{"access_token":"{access_token}","access_token_expires_in_ms":{expires_in * 1000}}}')
    response.headers["Content-Type"] = "application/json"
    
    # Set session-resume cookie (contains refresh token)
    response.set_cookie(
        key=settings.session_resume_cookie_name,
        value=refresh_token,
        **get_cookie_kwargs()
    )
    
    # Return access token in response body
    return response


@router.post("/resume/", response_model=AuthResponse)
def resume(db: Session = Depends(get_session), request: Request = None):
    """Resume session using session-resume cookie."""
    # Get refresh token from cookie
    refresh_token = request.cookies.get(settings.session_resume_cookie_name)
    
    if not refresh_token:
        raise HTTPException(status_code=401, detail="No session cookie found")
    
    # Use refresh token to get new tokens
    cognito_response = cognito_refresh_session(refresh_token)

    auth_result = cognito_response.get("AuthenticationResult", {}) or {}
    access_token = auth_result.get("AccessToken")
    new_refresh_token = auth_result.get("RefreshToken")
    expires_in = auth_result.get("ExpiresIn", 3600)

    if not access_token:
        raise HTTPException(status_code=500, detail="Failed to get access token from Cognito")

    # Create response
    response = Response(content=f'{{"access_token":"{access_token}","access_token_expires_in_ms":{expires_in * 1000}}}')
    response.headers["Content-Type"] = "application/json"
    
    # Only update the cookie if Cognito returned a new refresh token; otherwise keep the existing one
    if new_refresh_token:
        response.set_cookie(
            key=settings.session_resume_cookie_name,
            value=new_refresh_token,
            **get_cookie_kwargs()
        )
    
    return response


@router.post("/logout/")
def logout(response: Response):
    """Logout user by clearing session-resume cookie."""
    cookie_kwargs = {}
    if settings.app_env != "local" and settings.app_domain:
        cookie_kwargs["domain"] = f".{settings.app_domain}"
    response.delete_cookie(
        key=settings.session_resume_cookie_name,
        path="/",
        **cookie_kwargs,
    )
    return {"message": "Logged out successfully"}
