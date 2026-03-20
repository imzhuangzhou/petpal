import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppState } from '../context/AppStateContext'

function toMediaUrl(apiBase, path) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  return `${apiBase}${path}`
}

function SettingsPage() {
  const navigate = useNavigate()
  const fileInputRef = useRef(null)
  const {
    userId,
    petId,
    petName,
    petAvatar,
    petSpecies,
    voiceType,
    voiceLabel,
    voiceSampleUrl,
    cameraId,
    demoVideoName,
    demoVideoUrl,
    nickname,
    resetState,
    updateState,
    API_BASE,
  } = useAppState()

  const [uploadingVideo, setUploadingVideo] = useState(false)

  const handleReset = () => {
    if (window.confirm('确定要清除当前宠物档案并回到初始页吗？')) {
      resetState()
      navigate('/')
    }
  }

  const handleReplaceVideo = async (event) => {
    const file = event.target.files?.[0]
    if (!file || !userId || !petId || !cameraId) return

    setUploadingVideo(true)
    try {
      const formData = new FormData()
      formData.append('user_id', String(userId))
      formData.append('pet_id', String(petId))
      formData.append('camera_id', String(cameraId))
      formData.append('camera_name', '家庭摄像头')
      formData.append('video', file)

      const res = await fetch(`${API_BASE}/api/demo-video`, {
        method: 'POST',
        body: formData,
      })

      if (!res.ok) {
        throw new Error('replace video failed')
      }

      const data = await res.json()
      updateState({
        demoVideoName: data.demo_video_name,
        demoVideoUrl: data.demo_video_url,
      })
    } catch (error) {
      console.error(error)
      alert('替换视频失败，请稍后重试')
    } finally {
      setUploadingVideo(false)
      event.target.value = ''
    }
  }

  return (
    <div className="page settings-page">
      <div className="chat-header">
        <button
          type="button"
          className="back-link"
          onClick={() => navigate('/chat')}
        >
          ← 返回
        </button>
        <div className="chat-header-name">设置</div>
      </div>

      <div className="page-content page-stack">
        <section className="hero-card">
          <div className="hero-row">
            <div className="pet-stamp">{petAvatar}</div>
            <div>
              <div className="hero-badge">Profile</div>
              <h1 className="page-title">{petName}</h1>
              <p className="page-subtitle">
                主人是 {nickname || '你'}，当前宠物种类为 {petSpecies === 'dog' ? '狗狗' : '猫咪'}。
              </p>
            </div>
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">声音配置</div>
              <div className="section-title">当前聊天会使用的宠物声音画像</div>
            </div>
          </div>

          <div className="settings-surface">
            <div className="settings-surface-row">
              <span className="settings-kicker">当前模式</span>
              <span className="settings-value">
                {voiceType === 'clone' ? '真实宠物原声' : '预设宠物声音'}
              </span>
            </div>
            <div className="settings-surface-row">
              <span className="settings-kicker">声音名称</span>
              <span className="settings-value">{voiceLabel || '未设置'}</span>
            </div>

            {voiceSampleUrl && (
              <div className="audio-preview-card">
                <div className="audio-preview-meta">
                  <span className="audio-dot"></span>
                  已保存的真实宠物原声
                </div>
                <audio
                  controls
                  src={toMediaUrl(API_BASE, voiceSampleUrl)}
                  className="audio-player"
                />
              </div>
            )}
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">视频上下文</div>
              <div className="section-title">随时替换今天的演示视频</div>
            </div>
          </div>

          <div className="settings-surface">
            <div className="settings-surface-row">
              <span className="settings-kicker">当前视频</span>
              <span className="settings-value">{demoVideoName || '未上传'}</span>
            </div>

            {demoVideoUrl && (
              <video
                className="video-preview compact"
                controls
                src={toMediaUrl(API_BASE, demoVideoUrl)}
              />
            )}

            <input
              ref={fileInputRef}
              type="file"
              accept="video/*"
              hidden
              onChange={handleReplaceVideo}
            />

            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => fileInputRef.current?.click()}
              disabled={uploadingVideo}
            >
              {uploadingVideo ? '替换中...' : '替换演示视频'}
            </button>
          </div>
        </section>

        <section className="panel-card danger-panel">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">通用</div>
              <div className="section-title">重新开始配置</div>
            </div>
          </div>

          <div className="soft-note">
            如果你想重新创建宠物档案、重新录声音或重新绑定一段上下文视频，可以从这里回到起点。
          </div>

          <button type="button" className="btn btn-danger" onClick={handleReset}>
            重置所有应用数据
          </button>
        </section>
      </div>
    </div>
  )
}

export default SettingsPage
