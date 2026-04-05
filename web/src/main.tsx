import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { rehydrateKeysFromSession } from './crypto'

// Rehydrate PEK + identity privkey + profile keys from sessionStorage so a
// page refresh (refresh-token session) keeps the crypto state alive. Fires
// before the React tree mounts so hooks can assume keys are ready if the
// user still has a valid session.
rehydrateKeysFromSession().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
})

// Register service worker for PWA offline support
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {
      // Service worker registration failed — app works fine without it
    });
  });
}
