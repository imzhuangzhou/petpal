import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppState } from '../context/AppStateContext'

function getOpeningLine(style, species) {
  if (style === 'loyal') {
    return species === 'dog'
      ? '主人！我今天一直守着门口，终于等到你来找我啦！'
      : '主人主人，我今天也有乖乖等你，快夸夸我。'
  }

  if (style === 'chatty') {
    return species === 'dog'
      ? '你知道吗你知道吗，今天家里发生了好多事，我都记住了！'
      : '你终于来了，我今天从窗边看到好多小动静，想讲给你听。'
  }

  if (style === 'chill') {
    return '今天还算不错，阳光、零食和想你这件事都刚刚好。'
  }

  return species === 'dog'
    ? '哼，我才不是特地在等你，只是刚好想和你说说今天的事。'
    : '哼，你终于想起来看我了？我今天在门口等了你好一会儿。'
}

function ChatPage() {
  const navigate = useNavigate()
  const {
    petId,
    petName,
    petAvatar,
    petSpecies,
    languageStyle,
    demoVideoName,
    voiceLabel,
    API_BASE,
  } = useAppState()

  const [messages, setMessages] = useState([])
  const [inputValue, setInputValue] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [activeReport, setActiveReport] = useState(null)

  const messagesEndRef = useRef(null)

  useEffect(() => {
    if (!petId) {
      navigate('/')
      return
    }

    setMessages([
      {
        id: Date.now(),
        role: 'assistant',
        content: getOpeningLine(languageStyle, petSpecies),
      },
    ])
  }, [languageStyle, navigate, petId, petSpecies])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isTyping, activeReport])

  const handleSend = async (event) => {
    event.preventDefault()
    if (!inputValue.trim() || isTyping) return

    const userMsg = inputValue.trim()
    setInputValue('')
    setMessages((prev) => [...prev, { id: Date.now(), role: 'user', content: userMsg }])
    setActiveReport(null)
    setIsTyping(true)

    try {
      const res = await fetch(`${API_BASE}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pet_id: petId, message: userMsg }),
      })
      const data = await res.json()

      setMessages((prev) => [...prev, { id: Date.now() + 1, role: 'assistant', content: data.reply }])
    } catch (err) {
      console.error('Chat error:', err)
      setMessages((prev) => [
        ...prev,
        { id: Date.now() + 1, role: 'assistant', content: '喵呜，刚才网络打了个盹，再和我说一次吧。' },
      ])
    } finally {
      setIsTyping(false)
    }
  }

  const handleFeature = async (feature) => {
    if (isTyping) return
    setIsTyping(true)
    setActiveReport(null)

    const prompts = {
      daily: '给我看看你今天的简报吧',
      alerts: '你今天身体还好吗？',
      diary: '我想看看你今天写下的心情',
      anxiety: '我不在家的时候，你是不是有点想我？',
    }

    setMessages((prev) => [...prev, { id: Date.now(), role: 'user', content: prompts[feature] }])

    try {
      let endpoint = ''
      switch (feature) {
        case 'daily':
          endpoint = '/api/report/daily'
          break
        case 'alerts':
          endpoint = '/api/health/alerts'
          break
        case 'diary':
          endpoint = '/api/diary'
          break
        case 'anxiety':
          endpoint = '/api/anxiety'
          break
        default:
          return
      }

      const res = await fetch(`${API_BASE}${endpoint}/${petId}`)
      const data = await res.json()

      if (feature === 'alerts') {
        setActiveReport({ type: 'alerts', data: data.alerts })
      } else if (feature === 'anxiety') {
        setActiveReport({ type: 'anxiety', data })
      } else {
        const content = feature === 'daily' ? data.report : data.diary
        setMessages((prev) => [...prev, { id: Date.now() + 1, role: 'assistant', content }])
      }
    } catch (err) {
      console.error('Feature error:', err)
      setMessages((prev) => [
        ...prev,
        { id: Date.now() + 1, role: 'assistant', content: '刚才有点走神了，再点一次我就给你看。' },
      ])
    } finally {
      setIsTyping(false)
    }
  }

  const renderAlerts = () => {
    if (!activeReport || activeReport.type !== 'alerts') return null

    return (
      <div className="report-card fadeInUp">
        <div className="report-card-title">🩺 身体状况报告</div>
        <div className="report-stack">
          {activeReport.data.map((alert, index) => (
            <div key={index} className={`alert-card ${alert.level}`}>
              <div className="alert-icon">
                {alert.level === 'critical' ? '🚨' : alert.level === 'warning' ? '⚠️' : '✅'}
              </div>
              <div className="alert-content">
                <div className="alert-title">{alert.title}</div>
                <div className="alert-message">{alert.message}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  const renderAnxiety = () => {
    if (!activeReport || activeReport.type !== 'anxiety') return null
    const { data } = activeReport

    return (
      <div className="report-card fadeInUp">
        <div className="report-card-title">😟 分离焦虑指数</div>
        <div className="anxiety-meter">
          <div className={`anxiety-score-circle ${data.level}`}>{data.score}</div>
          <div className="anxiety-comment">{data.comment}</div>

          <div className="metric-grid">
            <div className="metric-card">
              <div className="metric-label">等你次数</div>
              <div className="metric-value">{data.waiting_count} 次</div>
            </div>
            <div className="metric-card">
              <div className="metric-label">累计等候</div>
              <div className="metric-value">{data.total_waiting_minutes} 分钟</div>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="page chat-page">
      <div className="chat-header">
        <div className="chat-header-avatar">{petAvatar}</div>
        <div className="chat-header-info">
          <div className="chat-header-name">{petName}</div>
          <div className="chat-header-status">今日上下文已加载，可以开始聊天了</div>
        </div>
        <button
          type="button"
          className="icon-ghost-btn"
          onClick={() => navigate('/settings')}
        >
          ⚙️
        </button>
      </div>

      <div className="chat-context-banner">
        <div className="context-pill">视频上下文：{demoVideoName || '已接入演示视频'}</div>
        <div className="context-pill">声音设定：{voiceLabel || '默认萌宠声线'}</div>
      </div>

      <div className="chat-messages">
        <div className="context-card">
          <div className="context-card-title">今天的陪伴模式已经准备好</div>
          <div className="context-card-text">
            现在的对话会结合 {demoVideoName || '当前视频'} 生成的行为事件来回答你。
          </div>
        </div>

        {messages.map((msg) => (
          <div key={msg.id} className={`chat-bubble-row ${msg.role === 'user' ? 'user' : 'pet'}`}>
            {msg.role === 'assistant' && <div className="chat-bubble-avatar">{petAvatar}</div>}
            <div className={`chat-bubble ${msg.role === 'user' ? 'user' : 'pet'}`}>{msg.content}</div>
          </div>
        ))}

        {isTyping && (
          <div className="chat-bubble-row pet">
            <div className="chat-bubble-avatar">{petAvatar}</div>
            <div className="chat-bubble pet loading">
              <div className="typing-dot"></div>
              <div className="typing-dot"></div>
              <div className="typing-dot"></div>
            </div>
          </div>
        )}

        {renderAlerts()}
        {renderAnxiety()}
        <div ref={messagesEndRef} />
      </div>

      <div className="quick-actions">
        <button className="quick-action-btn" onClick={() => handleFeature('alerts')}>
          <span>🩺</span> 健康告警
        </button>
        <button className="quick-action-btn" onClick={() => handleFeature('daily')}>
          <span>📋</span> 每日简报
        </button>
        <button className="quick-action-btn" onClick={() => handleFeature('anxiety')}>
          <span>😟</span> 焦虑指数
        </button>
        <button className="quick-action-btn" onClick={() => handleFeature('diary')}>
          <span>📖</span> 宠物日记
        </button>
      </div>

      <form className="chat-input-area" onSubmit={handleSend}>
        <input
          type="text"
          className="chat-input"
          placeholder={`和 ${petName} 聊聊天...`}
          value={inputValue}
          onChange={(event) => setInputValue(event.target.value)}
          disabled={isTyping}
        />
        <button
          type="submit"
          className="chat-send-btn"
          disabled={!inputValue.trim() || isTyping}
        >
          ⬆️
        </button>
      </form>
    </div>
  )
}

export default ChatPage
