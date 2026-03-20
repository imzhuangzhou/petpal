let activeAudioContext = null

const VOICE_PATTERNS = {
  'cat-soft': [
    [520, 0.18, 0.035, 'sine'],
    [610, 0.14, 0.028, 'triangle'],
    [480, 0.22, 0.03, 'sine'],
  ],
  'cat-princess': [
    [660, 0.12, 0.03, 'triangle'],
    [720, 0.1, 0.028, 'triangle'],
    [590, 0.14, 0.024, 'sine'],
  ],
  'cat-night': [
    [390, 0.2, 0.03, 'sine'],
    [440, 0.18, 0.026, 'sine'],
    [350, 0.24, 0.022, 'triangle'],
  ],
  'dog-sunny': [
    [420, 0.16, 0.04, 'square'],
    [500, 0.16, 0.035, 'triangle'],
    [580, 0.2, 0.032, 'square'],
  ],
  'dog-cocoa': [
    [320, 0.22, 0.04, 'sine'],
    [360, 0.18, 0.034, 'triangle'],
    [410, 0.2, 0.03, 'sine'],
  ],
  'dog-bounce': [
    [500, 0.1, 0.038, 'square'],
    [620, 0.12, 0.035, 'triangle'],
    [700, 0.15, 0.03, 'square'],
    [540, 0.12, 0.032, 'triangle'],
  ],
}

export async function playVoicePreview(voiceKey) {
  if (typeof window === 'undefined') return

  if (activeAudioContext) {
    await activeAudioContext.close()
    activeAudioContext = null
  }

  const AudioContextClass = window.AudioContext || window.webkitAudioContext
  if (!AudioContextClass) return

  const context = new AudioContextClass()
  activeAudioContext = context
  const pattern = VOICE_PATTERNS[voiceKey] || VOICE_PATTERNS['cat-soft']

  let currentTime = context.currentTime
  pattern.forEach(([frequency, duration, volume, type]) => {
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    oscillator.type = type
    oscillator.frequency.setValueAtTime(frequency, currentTime)
    gain.gain.setValueAtTime(0.0001, currentTime)
    gain.gain.exponentialRampToValueAtTime(volume, currentTime + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, currentTime + duration)
    oscillator.connect(gain)
    gain.connect(context.destination)
    oscillator.start(currentTime)
    oscillator.stop(currentTime + duration)
    currentTime += duration + 0.04
  })

  window.setTimeout(async () => {
    if (activeAudioContext === context) {
      await context.close()
      activeAudioContext = null
    }
  }, 1200)
}
