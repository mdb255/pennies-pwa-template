import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'
import { getTodoEndpoints } from './todos/todo-endpoints'

// Cross-origin data API: public Lambda Function URL, authenticated with a Bearer access
// token. No cookies (credentials: 'omit') — the session cookie belongs to authApi's origin.
export const dataApi = createApi({
    reducerPath: 'dataApi',
    baseQuery: fetchBaseQuery({
        baseUrl: import.meta.env.VITE_API_BASE || 'http://localhost:8000',
        credentials: 'omit',
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
    }),
})
