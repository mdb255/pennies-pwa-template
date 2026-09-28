import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'
import { getAuthEndpoints } from './auth/auth-endpoints'

// CloudFront fronts '/auth/*' with Origin Access Control against the auth Lambda's Function
// URL, which requires AWS_IAM-signed origin requests. CloudFront only signs the payload hash
// it's given — for POST/PUT/PATCH/DELETE it does not hash the body itself, so without this the
// signature it computes doesn't match what Lambda receives and every non-GET request 403s.
// https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-lambda.html
//
// RTK Query's fetchBaseQuery calls fetchFn with a single already-built Request object (not
// separate url/init args, despite the type signature allowing for it) — `init` is always
// undefined here. The body has to be read off `input` itself, and since a Request body can
// only be read once, a clone is used for hashing so the original is still intact to send.
async function fetchWithContentSha256(input: RequestInfo, init?: RequestInit): Promise<Response> {
    const request = new Request(input, init)
    const bodyText = await request.clone().text()
    const bytes = new TextEncoder().encode(bodyText)
    const digest = await crypto.subtle.digest('SHA-256', bytes)
    const hashHex = Array.from(new Uint8Array(digest))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')

    const headers = new Headers(request.headers)
    headers.set('x-amz-content-sha256', hashHex)

    return fetch(new Request(request, { headers }))
}

// Same-origin auth API: '/auth/*' is served on the PWA's own origin (via CloudFront in
// prod, the Vite dev proxy locally). credentials: 'include' sends the opaque session cookie.
export const authApi = createApi({
    reducerPath: 'authApi',
    baseQuery: fetchBaseQuery({
        baseUrl: '/auth',
        credentials: 'include',
        fetchFn: fetchWithContentSha256,
    }),
    endpoints: (builder) => ({
        ...getAuthEndpoints(builder),
    }),
})
