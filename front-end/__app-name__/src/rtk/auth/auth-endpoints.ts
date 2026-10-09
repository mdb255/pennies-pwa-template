import type { EndpointBuilder, fetchBaseQuery } from '@reduxjs/toolkit/query/react'

type AuthBuilder = EndpointBuilder<ReturnType<typeof fetchBaseQuery>, never, 'authApi'>

export function getAuthEndpoints(builder: AuthBuilder) {
    return {
        login: builder.mutation<{ access_token: string; access_token_expires_in_ms: number }, { email: string; password: string }>({
            query: (credentials) => ({
                url: 'login/',
                method: 'POST',
                body: credentials,
            }),
        }),
        signup: builder.mutation<{ message: string }, { email: string; password: string }>({
            query: (payload) => ({
                url: 'signup/',
                method: 'POST',
                body: payload,
            }),
        }),
        confirmSignup: builder.mutation<{ message: string }, { email: string; confirmation_code: string }>({
            query: (payload) => ({
                url: 'confirm-signup/',
                method: 'POST',
                body: payload,
            }),
        }),
        resume: builder.mutation<{ access_token: string; access_token_expires_in_ms: number }, void>({
            query: () => ({
                url: 'resume/',
                method: 'POST',
            }),
        }),
        logout: builder.mutation<{ message: string }, void>({
            query: () => ({
                url: 'logout/',
                method: 'POST',
            }),
        }),
    }
}
