import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppState } from '../context/AppStateContext'

function WelcomePage() {
  const navigate = useNavigate()
  const { petName, setupComplete, updateState, API_BASE } = useAppState()
  const [nickname, setNickname] = useState('')
  const [loading, setLoading] = useState(false)

  const handleStart = async (e) => {
    e.preventDefault()
    if (!nickname.trim()) return

    setLoading(true)
    try {
      const res = await fetch(`${API_BASE}/api/user`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nickname })
      })
      
      const data = await res.json()
      updateState({ userId: data.id, nickname: data.nickname })
      navigate('/create-pet')
    } catch (err) {
      console.error('Error creating user:', err)
      alert('网络错误，请确保后端服务已启动')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="page" style={{ justifyContent: 'center' }}>
      <div className="welcome-hero">
        <div className="welcome-emoji">🐾</div>
        <div className="hero-badge">Warm companion OS</div>
        <h1 className="welcome-title">PetPal</h1>
        <p className="welcome-tagline">每一帧，都是它想对你说的话</p>
        
        <form onSubmit={handleStart} style={{ width: '100%' }}>
          <div className="input-group">
            <input 
              type="text" 
              className="input" 
              placeholder="怎么称呼你？(你的昵称)" 
              value={nickname}
              onChange={e => setNickname(e.target.value)}
              required
            />
          </div>
          
          <button 
            type="submit" 
            className="btn btn-primary btn-full btn-lg"
            disabled={!nickname.trim() || loading}
          >
            {loading ? '准备中...' : '开始我们的故事'}
          </button>
        </form>

        {setupComplete && (
          <button
            type="button"
            className="btn btn-secondary btn-full"
            style={{ marginTop: '14px' }}
            onClick={() => navigate('/chat')}
          >
            继续和 {petName || '宠物'} 聊天
          </button>
        )}
      </div>
    </div>
  )
}

export default WelcomePage
