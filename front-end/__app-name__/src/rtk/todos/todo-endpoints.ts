import type { EndpointBuilder } from '@reduxjs/toolkit/query/react'
import type { Todo, TodoCreate, TodoUpdate, TodosQueryParams } from './todo-model'

export const getTodoEndpoints = (builder: EndpointBuilder<any, any, any>) => ({
    getTodos: builder.query<Todo[], TodosQueryParams>({
        query: (params) => ({ url: 'todos/', params }),
        providesTags: (result) =>
            result
                ? [...result.map(({ id }) => ({ type: 'Todo' as const, id })), { type: 'Todo', id: 'LIST' }]
                : [{ type: 'Todo', id: 'LIST' }],
    }),

    getTodo: builder.query<Todo, number>({
        query: (id) => `todos/${id}/`,
        providesTags: (result, error, id) => { void result; void error; return [{ type: 'Todo', id }] },
    }),

    createTodo: builder.mutation<Todo, TodoCreate>({
        query: (body) => ({ url: 'todos/', method: 'POST', body }),
        invalidatesTags: [{ type: 'Todo', id: 'LIST' }],
    }),

    updateTodo: builder.mutation<Todo, { id: number; updates: TodoUpdate }>({
        query: ({ id, updates }) => ({ url: `todos/${id}/`, method: 'PATCH', body: updates }),
        invalidatesTags: (result, error, { id }) => { void result; void error; return [{ type: 'Todo', id }] },
    }),

    deleteTodo: builder.mutation<void, number>({
        query: (id) => ({ url: `todos/${id}/`, method: 'DELETE' }),
        invalidatesTags: (result, error, id) => {
            void result; void error
            return [{ type: 'Todo', id }, { type: 'Todo', id: 'LIST' }]
        },
    }),
})
