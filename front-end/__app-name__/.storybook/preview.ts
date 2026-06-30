import type { Preview } from '@storybook/react'
import { setupIonicReact } from '@ionic/react'
import '../src/styling/ionic-base.css'
import '../src/styling/ionic-theme.css'
import '../src/styling/index.css'
import '../src/styling/custom-styles.css'

setupIonicReact()

const preview: Preview = {
    parameters: {
        controls: {
            matchers: {
                color: /(background|color)$/i,
                date: /Date$/i,
            },
        },
    },
}

export default preview
