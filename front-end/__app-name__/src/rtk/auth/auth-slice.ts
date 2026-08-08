import { createSlice, PayloadAction } from '@reduxjs/toolkit'

interface AuthState {
    isAuthenticated: boolean
    isInitialized: boolean
    accessToken: string | null
    email: string | null
}

const initialState: AuthState = {
    isAuthenticated: false,
    isInitialized: false,
    accessToken: null,
    email: null,
}

const authSlice = createSlice({
    name: 'auth',
    initialState,
    reducers: {
        setAuthenticated: (state, action: PayloadAction<{ accessToken: string; email?: string }>) => {
            state.isAuthenticated = true
            state.accessToken = action.payload.accessToken
            // Silent token refreshes (see dataApi's reauth wrapper) omit email — keep the
            // existing one rather than wiping it.
            if (action.payload.email !== undefined) {
                state.email = action.payload.email
            }
        },
        setInitialized: (state) => {
            state.isInitialized = true
        },
        clearAuth: (state) => {
            state.isAuthenticated = false
            state.accessToken = null
            state.email = null
        },
    },
})

export const { setAuthenticated, setInitialized, clearAuth } = authSlice.actions
export default authSlice.reducer
