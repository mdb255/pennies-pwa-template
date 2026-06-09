from datetime import datetime
from typing import Optional
from sqlmodel import SQLModel, Field
from .base import BaseModel


class TodoBase(SQLModel):
    title: str
    description: Optional[str] = None
    is_completed: bool = False


class Todo(TodoBase, BaseModel, table=True):
    user_id: int = Field(foreign_key="user.id", index=True)


class TodoCreate(TodoBase):
    pass


class TodoUpdate(SQLModel):
    title: Optional[str] = None
    description: Optional[str] = None
    is_completed: Optional[bool] = None


class TodoRead(TodoBase):
    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime
