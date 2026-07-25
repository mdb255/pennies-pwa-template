import { useState } from 'react'
import { useHistory, Link } from 'react-router-dom'
import { useDispatch } from 'react-redux'
import { IonPage, IonContent, IonItem, IonInput, IonLabel, IonButton, IonSpinner, IonText } from '@ionic/react'
import { authApi } from '../../rtk/auth-api'
import { setAuthenticated } from '../../rtk/auth/auth-slice'
import TopNavBar from '../design-system/top-nav-bar'

function LoginScreen() {
    const history = useHistory()
    const dispatch = useDispatch()

    const [email, setEmail] = useState('')
    const [password, setPassword] = useState('')
    const [error, setError] = useState('')

    const [login, { isLoading }] = authApi.useLoginMutation()

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        setError('')

        if (!email.trim() || !password.trim()) {
            setError('Please enter both email and password')
            return
        }

        try {
            const result = await login({ email: email.trim(), password }).unwrap()
            dispatch(setAuthenticated({ accessToken: result.access_token, email: email.trim() }))
            history.push('/todos')
        } catch (err: unknown) {
            console.error('Login failed:', err)
            const detail = err && typeof err === 'object' && 'data' in err && err.data && typeof err.data === 'object' && 'detail' in err.data
                ? String((err.data as { detail?: unknown }).detail)
                : ''
            setError(detail || 'Login failed. Please check your credentials.')
        }
    }

    const handleEmailChange = (e: CustomEvent) => {
        setEmail((e.target as HTMLIonInputElement).value as string ?? '')
        if (error) setError('')
    }

    const handlePasswordChange = (e: CustomEvent) => {
        setPassword((e.target as HTMLIonInputElement).value as string ?? '')
        if (error) setError('')
    }

    return (
        <IonPage>
            <TopNavBar title="Log In" showBackButton={false} />
            <IonContent scrollY={false} className="ion-padding">
                <div className="flex flex-col items-center justify-center h-full">
                    <div className="w-full max-w-[400px]">
                        <form onSubmit={handleSubmit} className="mb-6">
                            <IonItem className="mb-3">
                                <IonLabel position="stacked">Email</IonLabel>
                                <IonInput
                                    type="email"
                                    value={email}
                                    onIonInput={handleEmailChange}
                                    required
                                    disabled={isLoading}
                                    autofocus
                                />
                            </IonItem>
                            <IonItem className="mb-3">
                                <IonLabel position="stacked">Password</IonLabel>
                                <IonInput
                                    type="password"
                                    value={password}
                                    onIonInput={handlePasswordChange}
                                    required
                                    disabled={isLoading}
                                />
                            </IonItem>

                            {error && (
                                <IonText color="danger" className="block mt-2">
                                    <p className="text-sm">{error}</p>
                                </IonText>
                            )}

                            <div className="flex justify-center mt-4 mb-2">
                                <IonButton
                                    type="submit"
                                    className="extra-px"
                                    disabled={isLoading || !email.trim() || !password.trim()}
                                >
                                    {isLoading ? (
                                        <IonSpinner name="crescent" />
                                    ) : (
                                        'Log In'
                                    )}
                                </IonButton>
                            </div>
                        </form>

                        <p className="text-center text-md">
                            New user?{' '}
                            <Link to="/sign-up" className="font-medium text-primary">
                                Sign up
                            </Link>
                        </p>
                    </div>
                </div>
            </IonContent>
        </IonPage>
    )
}

export default LoginScreen
