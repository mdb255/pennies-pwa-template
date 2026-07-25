import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'
import { getAuthEndpoints } from './auth/auth-endpoints'

// Same-origin auth API: '/auth/*' is served on the PWA's own origin (via CloudFront in
// prod, the Vite dev proxy locally). credentials: 'include' sends the opaque session cookie.
export const authApi = createApi({
    reducerPath: 'authApi',
    baseQuery: fetchBaseQuery({
        baseUrl: '/auth',
        credentials: 'include',
    }),
    endpoints: (builder) => ({
        ...getAuthEndpoints(builder),
    }),
})
