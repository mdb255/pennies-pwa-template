import { createSlice } from '@reduxjs/toolkit'
import type { Todo } from './todo-model'
import { dataApi } from '../data-api'

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
            .addMatcher(dataApi.endpoints.getTodos.matchFulfilled, (state, action) => {
                action.payload.forEach((t) => { state.todosById[t.id] = t })
            })
            .addMatcher(dataApi.endpoints.getTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(dataApi.endpoints.createTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(dataApi.endpoints.updateTodo.matchFulfilled, (state, action) => {
                state.todosById[action.payload.id] = action.payload
            })
            .addMatcher(dataApi.endpoints.deleteTodo.matchFulfilled, (state, action) => {
                const id = action.meta.arg.originalArgs
                if (id) delete state.todosById[id]
            })
    },
})

export default todoSlice.reducer

export const selectTodosById = (state: { todos: TodoState }) => state.todos.todosById
export const selectTodos = (state: { todos: TodoState }) => Object.values(state.todos.todosById)
export const selectTodoById = (state: { todos: TodoState }, id: number) => state.todos.todosById[id]
