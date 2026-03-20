import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppState } from '../context/AppStateContext'
import {
  getPetAvatar,
  getVoicePreset,
  PET_STYLES,
  SPECIES_OPTIONS,
  VOICE_PRESETS,
} from '../data/petProfiles'
import { playVoicePreview } from '../utils/petAudio'

function PetCreatePage() {
  const navigate = useNavigate()
  const { userId, updateState, API_BASE } = useAppState()

  const [petName, setPetName] = useState('')
  const [species, setSpecies] = useState('cat')
  const [style, setStyle] = useState('tsundere')
  const [voiceMode, setVoiceMode] = useState('preset')
  const [voiceKey, setVoiceKey] = useState('cat-soft')
  const [loading, setLoading] = useState(false)
  const [recording, setRecording] = useState(false)
  const [recordingSeconds, setRecordingSeconds] = useState(0)
  const [recordedAudioBlob, setRecordedAudioBlob] = useState(null)
  const [recordedAudioUrl, setRecordedAudioUrl] = useState('')
  const [recorderError, setRecorderError] = useState('')

  const mediaRecorderRef = useRef(null)
  const streamRef = useRef(null)
  const chunksRef = useRef([])
  const timerRef = useRef(null)
  const stopTimeoutRef = useRef(null)

  const voicePresets = VOICE_PRESETS[species]
  const selectedVoicePreset = getVoicePreset(species, voiceKey)

  useEffect(() => {
    const speciesConfig = SPECIES_OPTIONS.find((item) => item.id === species)
    if (!voicePresets.some((item) => item.id === voiceKey)) {
      setVoiceKey(speciesConfig?.defaultVoiceKey || voicePresets[0]?.id || '')
    }
  }, [species, voiceKey, voicePresets])

  useEffect(() => {
    return () => {
      if (recordedAudioUrl) {
        URL.revokeObjectURL(recordedAudioUrl)
      }
      clearInterval(timerRef.current)
      clearTimeout(stopTimeoutRef.current)
      stopStream()
    }
  }, [recordedAudioUrl])

  const stopStream = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop())
      streamRef.current = null
    }
  }

  const stopRecording = () => {
    if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
      mediaRecorderRef.current.stop()
    }
    clearInterval(timerRef.current)
    clearTimeout(stopTimeoutRef.current)
    setRecording(false)
  }

  const startRecording = async () => {
    try {
      setRecorderError('')
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      streamRef.current = stream
      chunksRef.current = []

      const mimeType = MediaRecorder.isTypeSupported('audio/webm')
        ? 'audio/webm'
        : ''
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined)

      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data)
        }
      }

      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, {
          type: recorder.mimeType || 'audio/webm',
        })
        if (recordedAudioUrl) {
          URL.revokeObjectURL(recordedAudioUrl)
        }
        const nextUrl = URL.createObjectURL(blob)
        setRecordedAudioBlob(blob)
        setRecordedAudioUrl(nextUrl)
        setVoiceMode('clone')
        setRecordingSeconds(0)
        stopStream()
      }

      mediaRecorderRef.current = recorder
      recorder.start()
      setRecording(true)
      setRecordingSeconds(0)

      timerRef.current = window.setInterval(() => {
        setRecordingSeconds((prev) => prev + 1)
      }, 1000)

      stopTimeoutRef.current = window.setTimeout(() => {
        stopRecording()
      }, 6000)
    } catch (error) {
      console.error('record error', error)
      setRecorderError('无法使用麦克风，请检查浏览器权限。')
    }
  }

  const handleRecordClick = () => {
    if (recording) {
      stopRecording()
      return
    }
    startRecording()
  }

  const handleCreate = async () => {
    if (!petName.trim() || !userId || loading) return
    if (voiceMode === 'clone' && !recordedAudioBlob) {
      alert('请先录一段几秒钟的宠物声音')
      return
    }

    setLoading(true)
    try {
      const voicePayload =
        voiceMode === 'clone'
          ? {
              voice_type: 'clone',
              voice_key: 'custom-clone',
              voice_label: `${petName}原声`,
            }
          : {
              voice_type: 'preset',
              voice_key: selectedVoicePreset.id,
              voice_label: selectedVoicePreset.name,
            }

      const res = await fetch(`${API_BASE}/api/pet`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          user_id: userId,
          name: petName,
          species,
          language_style: style,
          ...voicePayload,
        }),
      })

      if (!res.ok) {
        throw new Error('create pet failed')
      }

      const data = await res.json()
      let voiceSampleUrl = ''

      if (voiceMode === 'clone' && recordedAudioBlob) {
        const audioFile = new File([recordedAudioBlob], 'pet-voice.webm', {
          type: recordedAudioBlob.type || 'audio/webm',
        })
        const formData = new FormData()
        formData.append('label', `${petName}原声`)
        formData.append('audio', audioFile)

        const uploadRes = await fetch(`${API_BASE}/api/pet/${data.id}/voice/sample`, {
          method: 'POST',
          body: formData,
        })

        if (!uploadRes.ok) {
          throw new Error('upload voice sample failed')
        }

        const uploadData = await uploadRes.json()
        voiceSampleUrl = uploadData.voice_sample_url
      }

      updateState({
        petId: data.id,
        petName,
        petSpecies: species,
        languageStyle: style,
        petAvatar: getPetAvatar(species),
        voiceType: voiceMode,
        voiceKey: voiceMode === 'preset' ? selectedVoicePreset.id : 'custom-clone',
        voiceLabel: voiceMode === 'preset' ? selectedVoicePreset.name : `${petName}原声`,
        voiceSampleUrl,
      })

      navigate('/bind-camera')
    } catch (err) {
      console.error('Error creating pet:', err)
      alert('网络错误，无法创建宠物档案')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="page">
      <div className="step-indicator">
        <div className="step-dot active"></div>
        <div className="step-dot"></div>
      </div>

      <div className="page-content page-stack">
        <section className="hero-card">
          <div className="hero-badge">Pet setup</div>
          <div className="hero-row">
            <div className="pet-stamp">{getPetAvatar(species)}</div>
            <div>
              <h1 className="page-title">认识一下新伙伴</h1>
              <p className="page-subtitle">
                先定好它的种类、说话风格和声音，后面聊天时就会更像它本人。
              </p>
            </div>
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">基础信息</div>
              <div className="section-title">它是家里的哪位小朋友？</div>
            </div>
            <div className="sticker-chip">Step 1</div>
          </div>

          <div className="input-group">
            <label className="input-label">名字</label>
            <input
              type="text"
              className="input"
              placeholder="例如：发财、奶盖、奥利奥..."
              value={petName}
              onChange={(event) => setPetName(event.target.value)}
            />
          </div>

          <div className="input-group">
            <label className="input-label">宠物种类</label>
            <div className="species-grid">
              {SPECIES_OPTIONS.map((option) => (
                <button
                  key={option.id}
                  type="button"
                  className={`species-tile ${species === option.id ? 'selected' : ''}`}
                  onClick={() => setSpecies(option.id)}
                >
                  <div className="species-option-emoji">{option.emoji}</div>
                  <div className="species-option-text">{option.label}</div>
                  <div className="species-option-desc">{option.summary}</div>
                </button>
              ))}
            </div>
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">聊天人格</div>
              <div className="section-title">它平时会怎么跟你说话？</div>
            </div>
            <div className="sticker-chip">Step 2</div>
          </div>

          <div className="style-cards">
            {PET_STYLES.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`style-card ${style === item.id ? 'selected' : ''}`}
                onClick={() => setStyle(item.id)}
              >
                <div className="style-card-emoji">{item.emoji}</div>
                <div className="style-card-name">{item.name}</div>
                <div className="style-card-desc">{item.desc}</div>
              </button>
            ))}
          </div>
        </section>

        <section className="panel-card">
          <div className="section-header">
            <div>
              <div className="section-eyebrow">声音设定</div>
              <div className="section-title">先选一个像它的声音，再决定要不要复刻真实原声</div>
            </div>
            <div className="sticker-chip">Step 3</div>
          </div>

          <div className="preset-grid">
            {voicePresets.map((preset) => (
              <div
                key={preset.id}
                className={`voice-card ${voiceMode === 'preset' && voiceKey === preset.id ? 'selected' : ''}`}
              >
                <button
                  type="button"
                  className="voice-card-main"
                  onClick={() => {
                    setVoiceMode('preset')
                    setVoiceKey(preset.id)
                  }}
                >
                  <div className="voice-card-top">
                    <span className="voice-card-name">{preset.name}</span>
                    <span className="voice-badge">{preset.sticker}</span>
                  </div>
                  <div className="voice-card-tone">{preset.tone}</div>
                  <div className="voice-card-desc">{preset.desc}</div>
                </button>

                <button
                  type="button"
                  className="tiny-btn"
                  onClick={() => playVoicePreview(preset.id)}
                >
                  试听一下
                </button>
              </div>
            ))}
          </div>

          <div className={`record-box ${voiceMode === 'clone' ? 'selected' : ''}`}>
            <div className="record-box-head">
              <div>
                <div className="record-box-title">复刻真实宠物声音</div>
                <div className="record-box-desc">
                  录 3-6 秒叫声、呼噜声或日常撒娇声，我们会把它保存成专属声音样本。
                </div>
              </div>
              <div className="sticker-chip soft">可选</div>
            </div>

            <div className="record-actions">
              <button
                type="button"
                className={`btn ${recording ? 'btn-ink' : 'btn-secondary'}`}
                onClick={handleRecordClick}
              >
                {recording ? `结束录音 ${recordingSeconds}s` : '开始录音'}
              </button>

              {recordedAudioUrl && (
                <>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() => setVoiceMode('clone')}
                  >
                    使用这段原声
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() => {
                      if (recordedAudioUrl) URL.revokeObjectURL(recordedAudioUrl)
                      setRecordedAudioBlob(null)
                      setRecordedAudioUrl('')
                      setVoiceMode('preset')
                    }}
                  >
                    重录
                  </button>
                </>
              )}
            </div>

            {recordedAudioUrl && (
              <div className="audio-preview-card">
                <div className="audio-preview-meta">
                  <span className="audio-dot"></span>
                  已录入一段真实宠物声音
                </div>
                <audio controls src={recordedAudioUrl} className="audio-player" />
              </div>
            )}

            {recorderError && <div className="helper-error">{recorderError}</div>}
          </div>
        </section>
      </div>

      <div className="footer-actions">
        <button
          className="btn btn-primary btn-full btn-lg"
          onClick={handleCreate}
          disabled={!petName.trim() || loading}
        >
          {loading ? '保存宠物档案中...' : '下一步，准备上传演示视频'}
        </button>
      </div>
    </div>
  )
}

export default PetCreatePage
