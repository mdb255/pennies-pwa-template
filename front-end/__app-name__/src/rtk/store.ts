import { configureStore } from '@reduxjs/toolkit'
import { appApi } from './app-api'
import todoSlice from './todos/todo-slice'
import authSlice from './auth/auth-slice'

export const store = configureStore({
    reducer: {
        [appApi.reducerPath]: appApi.reducer,
        todos: todoSlice,
        auth: authSlice,
    },
    middleware: (getDefaultMiddleware) =>
        getDefaultMiddleware().concat(appApi.middleware),
})

export type RootState = ReturnType<typeof store.getState>
export type AppDispatch = typeof store.dispatch

