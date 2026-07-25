import { useEffect, useRef, ReactNode } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import { IonSpinner } from '@ionic/react'
import { authApi } from '../../rtk/auth-api'
import { setAuthenticated, setInitialized, clearAuth } from '../../rtk/auth/auth-slice'
import { RootState } from '../../rtk/store'

const getEmailFromToken = (token: string): string | null => {
    try {
        const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')))
        return payload.email || payload.username || null
    } catch {
        return null
    }
}

interface AuthInitializerProps {
    children: ReactNode
}

function AuthInitializer({ children }: AuthInitializerProps) {
    const dispatch = useDispatch()
    const { isInitialized } = useSelector((state: RootState) => state.auth)

    const [resume] = authApi.useResumeMutation()
    const hasInitializedRef = useRef(false)

    useEffect(() => {
        if (hasInitializedRef.current) {
            return
        }
        hasInitializedRef.current = true

        const initializeAuth = async () => {
            try {
                const result = await resume().unwrap()
                const email = getEmailFromToken(result.access_token)
                dispatch(setAuthenticated({ accessToken: result.access_token, email: email ?? undefined }))
            } catch {
                dispatch(clearAuth())
            } finally {
                dispatch(setInitialized())
            }
        }

        initializeAuth()
    }, [dispatch, resume])

    if (!isInitialized) {
        return (
            <div className="flex justify-center items-center min-h-screen">
                <IonSpinner name="crescent" />
            </div>
        )
    }

    return <>{children}</>
}

export default AuthInitializer
