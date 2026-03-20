import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppState } from '../context/AppStateContext'

function CameraBindPage() {
  const navigate = useNavigate()
  const fileInputRef = useRef(null)
  const { userId, petId, demoVideoName, updateState, API_BASE } = useAppState()

  const [cameraName, setCameraName] = useState('客厅摄像头')
  const [selectedVideo, setSelectedVideo] = useState(null)
  const [videoPreviewUrl, setVideoPreviewUrl] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    return () => {
      if (videoPreviewUrl) URL.revokeObjectURL(videoPreviewUrl)
    }
  }, [videoPreviewUrl])

  const handleSelectVideo = (event) => {
    const file = event.target.files?.[0]
    if (!file) return

    if (videoPreviewUrl) {
      URL.revokeObjectURL(videoPreviewUrl)
    }

    setSelectedVideo(file)
    setVideoPreviewUrl(URL.createObjectURL(file))
  }

  const handleUpload = async () => {
    if (!userId || !petId || !selectedVideo) return

    setLoading(true)
    try {
      const formData = new FormData()
      formData.append('user_id', String(userId))
      formData.append('pet_id', String(petId))
      formData.append('camera_name', cameraName)
      formData.append('video', selectedVideo)

      const res = await fetch(`${API_BASE}/api/demo-video`, {
        method: 'POST',
        body: formData,
      })

      if (!res.ok) {
        throw new Error('upload demo video failed')
      }

      const data = await res.json()
      updateState({
        cameraId: data.camera_id,
        isDemo: true,
        demoVideoName: data.demo_video_name,
        demoVideoUrl: data.demo_video_url,
        setupComplete: true,
      })
      navigate('/chat')
    } catch (err) {
      console.error('Error uploading demo video:', err)
      alert('上传演示视频失败，请稍后再试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="page">
      {loading && (
        <div className="loading-overlay">
          <div className="loading-card">
            <div className="spinner"></div>
            <div className="loading-text">正在建立今天的行为上下文...</div>
            <div className="loading-subtext">我们会根据你上传的视频生成可聊天的今日记录。</div>
          </div>
        </div>
      )}

      <div className="step-indicator">
        <div className="step-dot done"></div>
        <div className="step-dot active"></div>
      </div>

      <div className="page-content page-stack">
        <section className="hero-card">
          <div className="hero-badge">Demo context</div>
          <div className="hero-row">
            <div className="pet-stamp">🎞️</div>
            <div>
              <h1 className="page-title">上传一段演示视频</h1>
              <p className="page-subtitle">
                当前版本会基于视频生成 mock 行为数据，但后续聊天、简报、日记和告警都会围绕这段视频的上下文展开。
              </p>
            </div>
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">上下文来源</div>
              <div className="section-title">给这只宠物绑定今天的“回家回放”</div>
            </div>
            <div className="sticker-chip">Step 4</div>
          </div>

          <div className="input-group">
            <label className="input-label">展示名称</label>
            <input
              type="text"
              className="input"
              value={cameraName}
              onChange={(event) => setCameraName(event.target.value)}
            />
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept="video/*"
            hidden
            onChange={handleSelectVideo}
          />

          <button
            type="button"
            className="upload-stage"
            onClick={() => fileInputRef.current?.click()}
          >
            <div className="upload-stage-icon">📼</div>
            <div className="upload-stage-title">
              {selectedVideo ? '重新选择视频' : '选择一段演示视频'}
            </div>
            <div className="upload-stage-desc">
              推荐上传 10 秒以上的家庭宠物片段，后续可在设置中替换。
            </div>
          </button>

          <div className="helper-note">
            当前已绑定：
            <strong>{selectedVideo?.name || demoVideoName || '暂未选择'}</strong>
          </div>

          {videoPreviewUrl && (
            <div className="video-preview-card">
              <div className="video-preview-head">
                <span className="video-tag">今日上下文视频</span>
                <span className="video-file-name">{selectedVideo.name}</span>
              </div>
              <video className="video-preview" controls src={videoPreviewUrl} />
            </div>
          )}

          <div className="soft-note">
            真正的摄像头绑定将在下一版补齐；这次先把视频上传、上下文建模、聊天体验和设置替换流程做成真实产品逻辑。
          </div>
        </section>
      </div>

      <div className="footer-actions">
        <button
          className="btn btn-primary btn-full btn-lg"
          onClick={handleUpload}
          disabled={!selectedVideo || loading}
        >
          上传并进入主页
        </button>
      </div>
    </div>
  )
}

export default CameraBindPage
