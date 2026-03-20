import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { useEffect, useState } from 'react'
import WelcomePage from './pages/WelcomePage'
import PetCreatePage from './pages/PetCreatePage'
import CameraBindPage from './pages/CameraBindPage'
import ChatPage from './pages/ChatPage'
import SettingsPage from './pages/SettingsPage'
import { AppContext } from './context/AppStateContext'

const API_BASE = 'http://localhost:8000'
const APP_STATE_KEY = 'petpal-app-state'

const defaultAppState = {
  userId: null,
  nickname: '',
  petId: null,
  petName: '',
  petSpecies: 'cat',
  petBreed: '',
  petAvatar: '🐱',
  languageStyle: 'tsundere',
  voiceType: 'preset',
  voiceKey: 'cat-soft',
  voiceLabel: '奶呼噜',
  voiceSampleUrl: '',
  cameraId: null,
  demoVideoName: '',
  demoVideoUrl: '',
  isDemo: false,
  setupComplete: false,
}

function getInitialState() {
  try {
    const stored = window.localStorage.getItem(APP_STATE_KEY)
    if (!stored) return defaultAppState
    return { ...defaultAppState, ...JSON.parse(stored) }
  } catch {
    return defaultAppState
  }
}

function App() {
  const [appState, setAppState] = useState(getInitialState)

  useEffect(() => {
    window.localStorage.setItem(APP_STATE_KEY, JSON.stringify(appState))
  }, [appState])

  const updateState = (updates) => {
    setAppState((prev) => ({ ...prev, ...updates }))
  }

  const resetState = () => {
    setAppState(defaultAppState)
    window.localStorage.removeItem(APP_STATE_KEY)
  }

  return (
    <AppContext.Provider value={{ ...appState, updateState, resetState, API_BASE }}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<WelcomePage />} />
          <Route path="/create-pet" element={<PetCreatePage />} />
          <Route path="/bind-camera" element={<CameraBindPage />} />
          <Route path="/chat" element={<ChatPage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AppContext.Provider>
  )
}

export default App
