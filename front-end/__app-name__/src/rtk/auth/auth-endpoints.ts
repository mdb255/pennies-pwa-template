import { EndpointBuilder } from '@reduxjs/toolkit/query/react'

export function getAuthEndpoints(builder: EndpointBuilder<any, any, any>) {
    return {
        login: builder.mutation<{ access_token: string; access_token_expires_in_ms: number }, { email: string; password: string }>({
            query: (credentials) => ({
                url: 'auth/login/',
                method: 'POST',
                body: credentials,
            }),
        }),
        signup: builder.mutation<{ message: string }, { email: string; password: string }>({
            query: (payload) => ({
                url: 'auth/signup/',
                method: 'POST',
                body: payload,
            }),
        }),
        confirmSignup: builder.mutation<{ message: string }, { email: string; confirmation_code: string }>({
            query: (payload) => ({
                url: 'auth/confirm-signup/',
                method: 'POST',
                body: payload,
            }),
        }),
        resume: builder.mutation<{ access_token: string; access_token_expires_in_ms: number }, void>({
            query: () => ({
                url: 'auth/resume/',
                method: 'POST',
            }),
        }),
        logout: builder.mutation<{ message: string }, void>({
            query: () => ({
                url: 'auth/logout/',
                method: 'POST',
            }),
        }),
    }
}
