"""Test todo endpoints."""

import pytest
from fastapi.testclient import TestClient


def test_list_todos_empty_or_existing(client: TestClient):
    response = client.get("/todos/")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_todo(client: TestClient):
    response = client.post("/todos/", json={"title": "Buy groceries", "description": "Milk and eggs"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Buy groceries"
    assert data["description"] == "Milk and eggs"
    assert data["is_completed"] is False
    assert "id" in data
    assert "created_at" in data
    assert "updated_at" in data

    client.delete(f"/todos/{data['id']}/")


def test_create_todo_title_only(client: TestClient):
    response = client.post("/todos/", json={"title": "Simple task"})
    assert response.status_code == 201
    data = response.json()
    assert data["description"] is None
    assert data["is_completed"] is False

    client.delete(f"/todos/{data['id']}/")


def test_get_todo(client: TestClient):
    created = client.post("/todos/", json={"title": "Get me"}).json()
    todo_id = created["id"]

    response = client.get(f"/todos/{todo_id}/")
    assert response.status_code == 200
    assert response.json()["title"] == "Get me"

    client.delete(f"/todos/{todo_id}/")


def test_get_todo_not_found(client: TestClient):
    response = client.get("/todos/999999/")
    assert response.status_code == 404


def test_update_todo_title(client: TestClient):
    created = client.post("/todos/", json={"title": "Original"}).json()
    todo_id = created["id"]

    response = client.patch(f"/todos/{todo_id}/", json={"title": "Updated"})
    assert response.status_code == 200
    assert response.json()["title"] == "Updated"

    client.delete(f"/todos/{todo_id}/")


def test_update_todo_is_completed(client: TestClient):
    created = client.post("/todos/", json={"title": "Complete me"}).json()
    todo_id = created["id"]

    response = client.patch(f"/todos/{todo_id}/", json={"is_completed": True})
    assert response.status_code == 200
    assert response.json()["is_completed"] is True

    client.delete(f"/todos/{todo_id}/")


def test_update_todo_not_found(client: TestClient):
    response = client.patch("/todos/999999/", json={"title": "Ghost"})
    assert response.status_code == 404


def test_delete_todo(client: TestClient):
    created = client.post("/todos/", json={"title": "Delete me"}).json()
    todo_id = created["id"]

    response = client.delete(f"/todos/{todo_id}/")
    assert response.status_code == 204

    assert client.get(f"/todos/{todo_id}/").status_code == 404


def test_delete_todo_not_found(client: TestClient):
    response = client.delete("/todos/999999/")
    assert response.status_code == 404


def test_list_todos_filter_completed(client: TestClient):
    todo1 = client.post("/todos/", json={"title": "Active"}).json()
    todo2_resp = client.post("/todos/", json={"title": "Done"})
    todo2 = client.patch(f"/todos/{todo2_resp.json()['id']}/", json={"is_completed": True}).json()

    incomplete = client.get("/todos/?is_completed=false").json()
    complete = client.get("/todos/?is_completed=true").json()

    assert all(not t["is_completed"] for t in incomplete)
    assert all(t["is_completed"] for t in complete)

    client.delete(f"/todos/{todo1['id']}/")
    client.delete(f"/todos/{todo2['id']}/")


def test_list_todos_pagination(client: TestClient):
    response = client.get("/todos/?skip=0&limit=5")
    assert response.status_code == 200
    assert len(response.json()) <= 5
