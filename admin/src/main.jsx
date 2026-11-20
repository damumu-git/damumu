import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './fonts.css'
import App from './App.jsx'
import './controls.css'
import './enterprise-theme.css'
import { AdminDialogProvider } from './AdminControls.jsx'
import { EmojiAssetsProvider } from './EmojiAssets.jsx'
import AdminLogin from './AdminLogin.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AdminLogin><AdminDialogProvider><EmojiAssetsProvider><App /></EmojiAssetsProvider></AdminDialogProvider></AdminLogin>
  </StrictMode>,
)
