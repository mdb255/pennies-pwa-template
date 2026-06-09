import { useState } from 'react'
import { IonPage, IonContent, IonItem, IonInput, IonLabel, IonButton, IonSpinner, IonText, IonIcon } from '@ionic/react'
import { eyeOffOutline, eyeOutline } from 'ionicons/icons'
import { useHistory } from 'react-router-dom'
import { appApi } from '../../rtk/app-api'
import TopNavBar from '../design-system/top-nav-bar'

function SignUpScreen() {
    const history = useHistory()

    const [step, setStep] = useState<1 | 2>(1)
    const [email, setEmail] = useState('')
    const [password, setPassword] = useState('')
    const [confirmPassword, setConfirmPassword] = useState('')
    const [confirmationCode, setConfirmationCode] = useState('')
    const [showPw, setShowPw] = useState(false)
    const [showConfirmPw, setShowConfirmPw] = useState(false)
    const [error, setError] = useState('')

    const [signup, { isLoading: isSigningUp }] = appApi.useSignupMutation()
    const [confirmSignup, { isLoading: isConfirming }] = appApi.useConfirmSignupMutation()

    const isValidEmail = (val: string) => /.+@.+\..+/.test(val)

    const handleSubmitStep1 = async (e: React.FormEvent) => {
        e.preventDefault()
        setError('')
        if (!isValidEmail(email)) {
            setError('Enter a valid email')
            return
        }
        if (!password || !confirmPassword) {
            setError('Enter password in both fields')
            return
        }
        if (password !== confirmPassword) {
            setError('Passwords do not match')
            return
        }
        try {
            await signup({ email: email.trim(), password }).unwrap()
            setStep(2)
        } catch (err: unknown) {
            const detail = err && typeof err === 'object' && 'data' in err && err.data && typeof err.data === 'object' && 'detail' in err.data
                ? String((err.data as { detail?: unknown }).detail)
                : ''
            setError(detail || 'Sign up failed')
        }
    }

    const handleSubmitStep2 = async (e: React.FormEvent) => {
        e.preventDefault()
        setError('')
        if (!confirmationCode.trim()) {
            setError('Enter the confirmation code')
            return
        }
        try {
            await confirmSignup({ email: email.trim(), confirmation_code: confirmationCode.trim() }).unwrap()
            history.push('/login')
        } catch (err: unknown) {
            const detail = err && typeof err === 'object' && 'data' in err && err.data && typeof err.data === 'object' && 'detail' in err.data
                ? String((err.data as { detail?: unknown }).detail)
                : ''
            setError(detail || 'Confirmation failed')
        }
    }

    const passwordsMismatch = password.length > 0 && confirmPassword.length > 0 && password !== confirmPassword
    const isStep1Valid = () => isValidEmail(email) && password.length > 0 && confirmPassword.length > 0 && !passwordsMismatch

    return (
        <IonPage>
            <TopNavBar title={step === 1 ? 'Create Account' : 'Confirm Email'} />
            <IonContent scrollY={false} className="ion-padding">
                <div className="flex flex-col items-center justify-center h-full">
                    <div className="w-full max-w-[440px]">
                        {step === 1 ? (
                            <form onSubmit={handleSubmitStep1} className="flex flex-col gap-4">
                                <IonItem>
                                    <IonLabel position="stacked">Email</IonLabel>
                                    <IonInput
                                        type="email"
                                        value={email}
                                        onIonInput={(e) => setEmail((e.target as HTMLIonInputElement).value as string ?? '')}
                                        required
                                        disabled={isSigningUp}
                                    />
                                </IonItem>
                                <IonItem>
                                    <IonLabel position="stacked">Password</IonLabel>
                                    <IonInput
                                        type={showPw ? 'text' : 'password'}
                                        value={password}
                                        onIonInput={(e) => setPassword((e.target as HTMLIonInputElement).value as string ?? '')}
                                        required
                                        disabled={isSigningUp}
                                    />
                                    <IonButton fill="clear" slot="end" onClick={() => setShowPw((s) => !s)} aria-label="toggle password visibility">
                                        <IonIcon icon={showPw ? eyeOffOutline : eyeOutline} />
                                    </IonButton>
                                </IonItem>
                                <IonItem className={passwordsMismatch ? 'ion-invalid' : ''}>
                                    <IonLabel position="stacked">Confirm Password</IonLabel>
                                    <IonInput
                                        type={showConfirmPw ? 'text' : 'password'}
                                        value={confirmPassword}
                                        onIonInput={(e) => setConfirmPassword((e.target as HTMLIonInputElement).value as string ?? '')}
                                        required
                                        disabled={isSigningUp}
                                    />
                                    <IonButton fill="clear" slot="end" onClick={() => setShowConfirmPw((s) => !s)} aria-label="toggle confirm password visibility">
                                        <IonIcon icon={showConfirmPw ? eyeOffOutline : eyeOutline} />
                                    </IonButton>
                                    {passwordsMismatch && (
                                        <IonText color="danger" slot="helper">
                                            <p className="text-sm">Passwords don&apos;t match</p>
                                        </IonText>
                                    )}
                                </IonItem>

                                {error && (
                                    <IonText color="danger">
                                        <p className="text-sm">{error}</p>
                                    </IonText>
                                )}

                                <div className="flex justify-center mt-4 mb-2">
                                    <IonButton
                                        type="submit"
                                        className="extra-px"
                                        disabled={isSigningUp || !isStep1Valid()}
                                    >
                                        {isSigningUp ? <IonSpinner name="crescent" /> : 'Sign Up'}
                                    </IonButton>
                                </div>
                            </form>
                        ) : (
                            <form onSubmit={handleSubmitStep2} className="flex flex-col gap-4">
                                <IonItem>
                                    <IonLabel position="stacked">Email</IonLabel>
                                    <IonInput type="email" value={email} disabled />
                                </IonItem>
                                <IonItem>
                                    <IonLabel position="stacked">Confirmation Code</IonLabel>
                                    <IonInput
                                        value={confirmationCode}
                                        onIonInput={(e) => setConfirmationCode((e.target as HTMLIonInputElement).value as string ?? '')}
                                        required
                                        disabled={isConfirming}
                                    />
                                </IonItem>

                                {error && (
                                    <IonText color="danger">
                                        <p className="text-sm">{error}</p>
                                    </IonText>
                                )}

                                <div className="flex justify-center mt-4 mb-2">
                                    <IonButton
                                        type="submit"
                                        className="extra-px"
                                        disabled={isConfirming || !confirmationCode.trim()}
                                    >
                                        {isConfirming ? <IonSpinner name="crescent" /> : 'Confirm'}
                                    </IonButton>
                                </div>
                            </form>
                        )}
                    </div>
                </div>
            </IonContent>
        </IonPage>
    )
}

export default SignUpScreen
