import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'
import { getTodoEndpoints } from './todos/todo-endpoints'
import { getAuthEndpoints } from './auth/auth-endpoints'

export const appApi = createApi({
    reducerPath: 'appApi',
    baseQuery: fetchBaseQuery({
        baseUrl: import.meta.env.VITE_API_BASE || 'http://localhost:8000',
        credentials: 'include',
        prepareHeaders: (headers, { getState }) => {
            const token = (getState() as any)?.auth?.accessToken
            if (token) {
                headers.set('authorization', `Bearer ${token}`)
            }
            return headers
        },
    }),
    tagTypes: ['Todo'],
    endpoints: (builder) => ({
        ...getTodoEndpoints(builder),
        ...getAuthEndpoints(builder),
    }),
})
