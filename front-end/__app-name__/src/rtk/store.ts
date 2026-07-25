import { configureStore } from '@reduxjs/toolkit'
import { dataApi } from './data-api'
import { authApi } from './auth-api'
import todoSlice from './todos/todo-slice'
import authSlice from './auth/auth-slice'

export const store = configureStore({
    reducer: {
        [dataApi.reducerPath]: dataApi.reducer,
        [authApi.reducerPath]: authApi.reducer,
        todos: todoSlice,
        auth: authSlice,
    },
    middleware: (getDefaultMiddleware) =>
        getDefaultMiddleware().concat(dataApi.middleware, authApi.middleware),
})

export type RootState = ReturnType<typeof store.getState>
export type AppDispatch = typeof store.dispatch
