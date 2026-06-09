"""User model definitions."""

from datetime import datetime
from typing import Optional
from sqlmodel import SQLModel, Field
from .base import BaseModel


class UserBase(SQLModel):
    """Base user model with common fields."""
    email: str = Field(unique=True, index=True)
    cognito_sub: str = Field(unique=True, index=True)
    name: str


class User(UserBase, BaseModel, table=True):
    """User database model."""
    pass


class UserCreate(UserBase):
    """User creation model."""
    pass


class UserUpdate(SQLModel):
    """User update model."""
    email: Optional[str] = None
    cognito_sub: Optional[str] = None
    name: Optional[str] = None


class UserRead(UserBase):
    """User read model."""
    id: int
    created_at: datetime
    updated_at: datetime
