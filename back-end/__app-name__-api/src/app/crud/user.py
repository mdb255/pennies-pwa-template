"""User CRUD operations."""

from typing import Optional
from sqlmodel import Session, select
from ..models.user import User, UserCreate, UserUpdate
from .base import CRUDBase


class UserCRUD(CRUDBase[User, UserCreate, UserUpdate]):
    """User CRUD operations."""
    
    def get_by_email(self, db: Session, *, email: str) -> Optional[User]:
        """Get user by email."""
        statement = select(User).where(User.email == email)
        return db.exec(statement).first()
    
    def get_by_cognito_sub(self, db: Session, *, cognito_sub: str) -> Optional[User]:
        """Get user by Cognito sub."""
        statement = select(User).where(User.cognito_sub == cognito_sub)
        return db.exec(statement).first()
    
    def upsert_by_email(self, db: Session, *, user_in: UserCreate) -> User:
        """Upsert user by email (create if not exists, return existing otherwise)."""
        existing_user = self.get_by_email(db, email=user_in.email)
        
        if existing_user:
            # Update if needed
            update_data = UserUpdate(**user_in.model_dump())
            return self.update(db, db_obj=existing_user, obj_in=update_data)
        else:
            # Create new
            return self.create(db, obj_in=user_in)


# Create instance
user = UserCRUD(User)
