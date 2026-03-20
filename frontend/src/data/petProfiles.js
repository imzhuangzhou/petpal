export const SPECIES_OPTIONS = [
  {
    id: 'cat',
    emoji: '🐱',
    label: '喵星人',
    summary: '轻盈、敏感、会把心事藏在尾巴尖。',
    defaultVoiceKey: 'cat-soft',
  },
  {
    id: 'dog',
    emoji: '🐶',
    label: '汪星人',
    summary: '热情、黏人、会把开心都写在眼睛里。',
    defaultVoiceKey: 'dog-sunny',
  },
]

export const PET_STYLES = [
  { id: 'tsundere', emoji: '😼', name: '傲娇主子', desc: '嘴上不说，心里却记得你什么时候回家。' },
  { id: 'loyal', emoji: '🐕', name: '忠诚小跟班', desc: '每一句回应都像摇着尾巴朝你跑来。' },
  { id: 'chatty', emoji: '🪽', name: '碎碎念搭子', desc: '芝麻大的小事，也想马上讲给你听。' },
  { id: 'chill', emoji: '🛋️', name: '松弛感主角', desc: '不慌不忙，连撒娇都带着午后阳光味。' },
]

export const VOICE_PRESETS = {
  cat: [
    { id: 'cat-soft', name: '奶呼噜', tone: '柔软', desc: '轻轻黏人，像在耳边打呼噜。', sticker: '推荐' },
    { id: 'cat-princess', name: '小公主', tone: '灵巧', desc: '清脆娇气，适合高冷又精致的小猫。', sticker: '人气' },
    { id: 'cat-night', name: '月光喵', tone: '低缓', desc: '松弛慵懒，像半夜跳上床沿轻轻叫你。', sticker: '治愈' },
  ],
  dog: [
    { id: 'dog-sunny', name: '太阳尾巴', tone: '明亮', desc: '热情开朗，一开口就是扑面而来的亲近感。', sticker: '推荐' },
    { id: 'dog-cocoa', name: '可可伙伴', tone: '温厚', desc: '沉稳友好，像懂事的大型犬陪在身旁。', sticker: '稳定' },
    { id: 'dog-bounce', name: '弹跳泡泡', tone: '活泼', desc: '更有少年感，适合精力旺盛的狗狗。', sticker: '活力' },
  ],
}

export function getPetAvatar(species) {
  return species === 'dog' ? '🐶' : '🐱'
}

export function getVoicePreset(species, voiceKey) {
  const presets = VOICE_PRESETS[species] || []
  return presets.find((item) => item.id === voiceKey) || presets[0]
}
