"""Authentication module for AWS Cognito JWT validation."""

import time
from typing import Optional, Dict, Any
import requests
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWSError, ExpiredSignatureError
from boto3 import client
from botocore.exceptions import ClientError
from .settings import settings

# HTTPBearer scheme for extracting Bearer tokens
security = HTTPBearer()

# JWKs cache with TTL
_jwks_cache: Optional[Dict[str, Any]] = None
_jwks_cache_timestamp: float = 0


def get_jwks_url() -> str:
    """Construct the JWKs URL from Cognito settings."""
    return f"https://cognito-idp.{settings.aws_region}.amazonaws.com/{settings.user_pool_id}/.well-known/jwks.json"


def fetch_jwks() -> Dict[str, Any]:
    """Fetch and cache JWKs from Cognito with TTL."""
    global _jwks_cache, _jwks_cache_timestamp
    
    current_time = time.time()
    
    # Return cached JWKs if still valid
    if _jwks_cache is not None and (current_time - _jwks_cache_timestamp) < settings.jwks_cache_ttl:
        return _jwks_cache
    
    # Fetch fresh JWKs
    try:
        response = requests.get(get_jwks_url(), timeout=10)
        response.raise_for_status()
        _jwks_cache = response.json()
        _jwks_cache_timestamp = current_time
        return _jwks_cache
    except requests.RequestException as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to fetch JWKs: {str(e)}"
        )


def get_rsa_key(token: str) -> Dict[str, Any]:
    """Get the RSA public key for the token's kid."""
    unverified_header = jwt.get_unverified_header(token)
    kid = unverified_header.get("kid")
    
    if kid is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing kid in header"
        )
    
    jwks = fetch_jwks()
    rsa_key = None
    
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            rsa_key = {
                "kty": key["kty"],
                "kid": key["kid"],
                "use": key.get("use"),
                "n": key["n"],
                "e": key["e"]
            }
            break
    
    if rsa_key is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to find appropriate key for token"
        )
    
    return rsa_key


def verify_token(token: str) -> Dict[str, Any]:
    """Verify JWT access token against Cognito JWKs."""
    try:
        # Get RSA key
        rsa_key = get_rsa_key(token)
        
        # Verify and decode token
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],
            audience=settings.app_client_id,
            issuer=f"https://cognito-idp.{settings.aws_region}.amazonaws.com/{settings.user_pool_id}",
            options={
                "verify_signature": True,
                "verify_aud": True,
                "verify_iss": True,
                "verify_exp": True,
                "verify_nbf": False,
                "verify_iat": True,
            }
        )
        
        return payload
        
    except ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired"
        )
    except JWSError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token verification failed: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token validation error: {str(e)}"
        )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Dict[str, Any]:
    """
    FastAPI dependency to get current authenticated user.
    
    Extracts Bearer token from Authorization header and verifies it.
    Returns the decoded token claims.
    
    Raises 401 HTTPException for invalid/missing tokens.
    """
    token = credentials.credentials
    return verify_token(token)


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(
        HTTPBearer(auto_error=False)
    )
) -> Optional[Dict[str, Any]]:
    """
    FastAPI dependency to optionally get current authenticated user.
    
    For public endpoints that may or may not have authentication.
    Returns None if no token is provided, otherwise returns decoded claims.
    """
    if credentials is None:
        return None
    
    try:
        token = credentials.credentials
        return verify_token(token)
    except HTTPException:
        return None


# Cognito client initialization
cognito_client = client('cognito-idp', region_name=settings.aws_region)


def get_cookie_kwargs() -> Dict[str, Any]:
    """Get cookie configuration kwargs based on environment."""
    is_local = settings.app_env == "local"
    
    cookie_kwargs = {
        "httponly": True,
        "secure": not is_local,
        "samesite": "lax",
        "max_age": settings.session_resume_cookie_ttl,
    }
    
    if not is_local and settings.app_domain:
        cookie_kwargs["domain"] = f".{settings.app_domain}"
    
    return cookie_kwargs


def cognito_signup(email: str, password: str) -> Dict[str, Any]:
    """Sign up a new user in Cognito."""
    try:
        response = cognito_client.sign_up(
            ClientId=settings.app_client_id,
            Username=email,
            Password=password,
            UserAttributes=[
                {"Name": "email", "Value": email}
            ]
        )
        return response
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        raise HTTPException(
            status_code=400,
            detail=f"Cognito signup error ({error_code}): {error_message}"
        )


def cognito_confirm_signup(email: str, confirmation_code: str) -> None:
    """Confirm user signup in Cognito."""
    try:
        cognito_client.confirm_sign_up(
            ClientId=settings.app_client_id,
            Username=email,
            ConfirmationCode=confirmation_code
        )
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        raise HTTPException(
            status_code=400,
            detail=f"Cognito confirm signup error ({error_code}): {error_message}"
        )


def cognito_login(email: str, password: str) -> Dict[str, Any]:
    """Authenticate user with Cognito using USER_PASSWORD_AUTH."""
    try:
        response = cognito_client.admin_initiate_auth(
            UserPoolId=settings.user_pool_id,
            ClientId=settings.app_client_id,
            AuthFlow="ADMIN_NO_SRP_AUTH",
            AuthParameters={
                "USERNAME": email,
                "PASSWORD": password,
            }
        )
        return response
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        raise HTTPException(
            status_code=401,
            detail=f"Cognito login error ({error_code}): {error_message}"
        )


def cognito_refresh_session(refresh_token: str) -> Dict[str, Any]:
    """Get new tokens using refresh token."""
    try:
        response = cognito_client.initiate_auth(
            ClientId=settings.app_client_id,
            AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={
                "REFRESH_TOKEN": refresh_token
            }
        )
        return response
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        raise HTTPException(
            status_code=401,
            detail=f"Cognito refresh error ({error_code}): {error_message}"
        )


def decode_id_token(id_token: str) -> Dict[str, Any]:
    """Decode ID token to extract claims (no verification needed)."""
    try:
        decoded = jwt.get_unverified_claims(id_token)
        return decoded
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to decode ID token: {str(e)}"
        )
