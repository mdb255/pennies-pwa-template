from typing import List, Optional
from fastapi import APIRouter, HTTPException, Depends, Query
from sqlmodel import Session
from ..db import get_session
from ..models.todo import Todo, TodoCreate, TodoUpdate, TodoRead
from ..crud.todo import todo
from ..crud.user import user as user_crud
from ..auth import get_current_user

router = APIRouter(prefix="/todos", tags=["todos"])


def _get_db_user(db: Session, current_user: dict):
    db_user = user_crud.get_by_cognito_sub(db, cognito_sub=current_user.get("sub"))
    if not db_user:
        raise HTTPException(status_code=401, detail="User not found")
    return db_user


@router.post("/", response_model=TodoRead, status_code=201)
def create_todo(
    todo_data: TodoCreate,
    db: Session = Depends(get_session),
    current_user: dict = Depends(get_current_user),
):
    db_user = _get_db_user(db, current_user)
    return todo.create_for_user(db=db, obj_in=todo_data, user_id=db_user.id)


@router.get("/", response_model=List[TodoRead])
def list_todos(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    is_completed: Optional[bool] = Query(None),
    db: Session = Depends(get_session),
    current_user: dict = Depends(get_current_user),
):
    db_user = _get_db_user(db, current_user)
    return todo.get_multi_for_user(db=db, user_id=db_user.id, is_completed=is_completed, skip=skip, limit=limit)


@router.get("/{todo_id}/", response_model=TodoRead)
def get_todo(
    todo_id: int,
    db: Session = Depends(get_session),
    current_user: dict = Depends(get_current_user),
):
    db_user = _get_db_user(db, current_user)
    todo_obj = todo.get_for_user(db=db, id=todo_id, user_id=db_user.id)
    if not todo_obj:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo_obj


@router.patch("/{todo_id}/", response_model=TodoRead)
def update_todo(
    todo_id: int,
    todo_data: TodoUpdate,
    db: Session = Depends(get_session),
    current_user: dict = Depends(get_current_user),
):
    db_user = _get_db_user(db, current_user)
    todo_obj = todo.get_for_user(db=db, id=todo_id, user_id=db_user.id)
    if not todo_obj:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo.update(db=db, db_obj=todo_obj, obj_in=todo_data)


@router.delete("/{todo_id}/", status_code=204)
def delete_todo(
    todo_id: int,
    db: Session = Depends(get_session),
    current_user: dict = Depends(get_current_user),
):
    db_user = _get_db_user(db, current_user)
    todo_obj = todo.get_for_user(db=db, id=todo_id, user_id=db_user.id)
    if not todo_obj:
        raise HTTPException(status_code=404, detail="Todo not found")
    todo.remove(db=db, id=todo_id)
