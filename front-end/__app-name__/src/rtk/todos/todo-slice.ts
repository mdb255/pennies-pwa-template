import { createSlice } from '@reduxjs/toolkit'
import type { Todo } from './todo-model'
import { appApi } from '../app-api'

export interface TodoState {
    todosById: Record<number, Todo>
}

const initialState: TodoState = { todosById: {} }

export const todoSlice = createSlice({
    name: 'todos',
    initialState,
    reducers: {},
    extraReducers: (builder) => {
        builder
            .addMatcher(appApi.endpoints.getTodos.matchFulfilled, (state, action) => {
                action.payload.forEach((t) => { state.todosById[t.id] = t })
            })
            .addMatcher(appApi.endpoints.getTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(appApi.endpoints.createTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(appApi.endpoints.updateTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(appApi.endpoints.deleteTodo.matchFulfilled, (state, action) => {
                const id = action.meta.arg.originalArgs
                if (id) delete state.todosById[id]
            })
    },
})

export default todoSlice.reducer

export const selectTodosById = (state: { todos: TodoState }) => state.todos.todosById
export const selectTodos = (state: { todos: TodoState }) => Object.values(state.todos.todosById)
export const selectTodoById = (state: { todos: TodoState }, id: number) => state.todos.todosById[id]
