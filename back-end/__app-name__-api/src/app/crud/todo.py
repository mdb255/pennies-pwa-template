from typing import List, Optional
from sqlmodel import Session, select
from ..models.todo import Todo, TodoCreate, TodoUpdate
from .base import CRUDBase


class TodoCRUD(CRUDBase[Todo, TodoCreate, TodoUpdate]):
    def get_for_user(self, db: Session, *, id: int, user_id: int) -> Optional[Todo]:
        statement = select(Todo).where(Todo.id == id, Todo.user_id == user_id)
        return db.exec(statement).first()

    def get_multi_for_user(
        self,
        db: Session,
        *,
        user_id: int,
        is_completed: Optional[bool] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[Todo]:
        statement = select(Todo).where(Todo.user_id == user_id)
        if is_completed is not None:
            statement = statement.where(Todo.is_completed == is_completed)
        return db.exec(statement.offset(skip).limit(limit)).all()

    def create_for_user(self, db: Session, *, obj_in: TodoCreate, user_id: int) -> Todo:
        obj_in_data = obj_in.model_dump()
        obj_in_data["user_id"] = user_id
        db_obj = Todo(**obj_in_data)
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj


todo = TodoCRUD(Todo)
