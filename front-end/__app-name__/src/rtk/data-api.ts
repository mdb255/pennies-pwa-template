import { createApi, fetchBaseQuery, BaseQueryFn, FetchArgs, FetchBaseQueryError } from '@reduxjs/toolkit/query/react'
import { getTodoEndpoints } from './todos/todo-endpoints'
import { authApi } from './auth-api'
import { setAuthenticated, clearAuth } from './auth/auth-slice'

// Cross-origin data API: public Lambda Function URL, authenticated with a Bearer access
// token. No cookies (credentials: 'omit') — the session cookie belongs to authApi's origin.
const rawBaseQuery = fetchBaseQuery({
    baseUrl: import.meta.env.VITE_API_BASE || 'http://localhost:8000',
    credentials: 'omit',
    prepareHeaders: (headers, { getState }) => {
        const token = (getState() as any)?.auth?.accessToken
        if (token) {
            headers.set('authorization', `Bearer ${token}`)
        }
        return headers
    },
})

// The access token is short-lived (15 min). Once it expires, every dataApi call 401s until
// something calls authApi's resume endpoint — otherwise that only happens on a hard reload.
// This wrapper does the same resume() call transparently on a 401, retries once, and logs out
// if the session cookie is also gone. Concurrent 401s share one in-flight resume so a burst of
// requests doesn't fire a refresh storm.
let refreshPromise: Promise<string | null> | null = null

const baseQueryWithReauth: BaseQueryFn<string | FetchArgs, unknown, FetchBaseQueryError> = async (args, api, extraOptions) => {
    let result = await rawBaseQuery(args, api, extraOptions)

    if (result.error?.status === 401) {
        if (!refreshPromise) {
            refreshPromise = api
                .dispatch(authApi.endpoints.resume.initiate())
                .unwrap()
                .then((resumed) => {
                    api.dispatch(setAuthenticated({ accessToken: resumed.access_token }))
                    return resumed.access_token
                })
                .catch(() => {
                    api.dispatch(clearAuth())
                    return null
                })
                .finally(() => {
                    refreshPromise = null
                })
        }

        const newToken = await refreshPromise
        if (newToken) {
            result = await rawBaseQuery(args, api, extraOptions)
        }
    }

    return result
}

export const dataApi = createApi({
    reducerPath: 'dataApi',
    baseQuery: baseQueryWithReauth,
    tagTypes: ['Todo'],
    endpoints: (builder) => ({
        ...getTodoEndpoints(builder),
    }),
})
