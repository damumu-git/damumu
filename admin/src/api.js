const API_BASE = import.meta.env.VITE_API_BASE ?? 'http://localhost:8080/api/v1'
const ADMIN_KEY = import.meta.env.VITE_ADMIN_KEY ?? 'muda-admin-local'

export function mediaUrl(value) {
  if (!value) return ''
  const apiUrl = new URL(API_BASE, window.location.origin)
  return new URL(value, apiUrl.origin).href
}

async function request(path, options = {}) {
  const isForm = options.body instanceof FormData
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      ...(isForm ? {} : { 'Content-Type': 'application/json' }),
      'X-Admin-Key': ADMIN_KEY,
      ...options.headers,
    },
  })

  if (response.status === 204) return null
  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? `请求失败 (${response.status})`)
  }
  return payload
}

function params(values) {
  const query = new URLSearchParams()
  Object.entries(values).forEach(([key, value]) => {
    if (value !== '' && value !== null && value !== undefined) query.set(key, value)
  })
  const result = query.toString()
  return result ? `?${result}` : ''
}

export const api = {
  emojiAssets: () => request('/emoji-assets'),
  adminEmojiAssets: () => request('/admin/emoji-assets'),
  uploadEmojiAsset: (form) => request('/admin/emoji-assets', { method: 'POST', body: form }),
  updateEmojiAsset: (key, body) => request(`/admin/emoji-assets/${encodeURIComponent(key)}`, { method: 'PATCH', body: JSON.stringify(body) }),
  health: () => request('/health'),
  dashboard: () => request('/admin/dashboard'),
  users: (filters = {}) => request(`/admin/users${params(filters)}`),
  user: (id) => request(`/admin/users/${id}`),
  updateUserStatus: (id, body) =>
    request(`/admin/users/${id}/status`, { method: 'PATCH', body: JSON.stringify(body) }),
  events: (filters = {}) => request(`/admin/events${params(filters)}`),
  messages: (filters = {}) => request(`/admin/messages${params(filters)}`),
  message: (id) => request(`/admin/messages/${id}`),
  moderateMessage: (id, body) =>
    request(`/admin/messages/${id}/moderation`, { method: 'PATCH', body: JSON.stringify(body) }),
  messageMedia: async (id, signal) => {
    const response = await fetch(`${API_BASE}/admin/messages/${id}/media`, {
      headers: { 'X-Admin-Key': ADMIN_KEY }, signal,
    })
    if (!response.ok) throw new Error('消息附件暂时无法读取')
    return response.blob()
  },
  event: (id) => request(`/admin/events/${id}`),
  pendingEventCovers: () => request('/admin/event-cover-review/count'),
  eventCover: async (id, signal) => {
    const response = await fetch(`${API_BASE}/admin/events/${id}/cover`, {
      headers: { 'X-Admin-Key': ADMIN_KEY }, signal,
    })
    if (!response.ok) throw new Error('活动图片暂时无法读取')
    return response.blob()
  },
  reviewEventCover: (id, body) =>
    request(`/admin/events/${id}/cover-review`, { method: 'PATCH', body: JSON.stringify(body) }),
  bulkModerateEvents: (body) =>
    request('/admin/events/bulk-moderation', { method: 'POST', body: JSON.stringify(body) }),
  suggestions: (filters = {}) => request(`/admin/suggestions${params(filters)}`),
  replyToSuggestion: (id, text) =>
    request(`/admin/suggestions/${id}/reply`, { method: 'POST', body: JSON.stringify({ text }) }),
  approveEventMember: (eventId, memberUserId, body) =>
    request(`/admin/events/${eventId}/members/${memberUserId}/approve`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  moderateEvent: (id, body) =>
    request(`/admin/events/${id}/moderation`, { method: 'PATCH', body: JSON.stringify(body) }),
  reports: (filters = {}) => request(`/admin/reports${params(filters)}`),
  report: (id) => request(`/admin/reports/${id}`),
  updateReport: (id, body) =>
    request(`/admin/reports/${id}`, { method: 'PATCH', body: JSON.stringify(body) }),
  safetyAlerts: (filters = {}) => request(`/admin/safety-alerts${params(filters)}`),
  updateSafetyAlert: (id, body) =>
    request(`/admin/safety-alerts/${id}`, { method: 'PATCH', body: JSON.stringify(body) }),
  categories: () => request('/admin/categories'),
  systemAvatars: () => request('/admin/system-avatars'),
  uploadSystemAvatar: (form) =>
    request('/admin/system-avatars', { method: 'POST', body: form }),
  updateSystemAvatar: (id, body) =>
    request(`/admin/system-avatars/${id}`, { method: 'PATCH', body: JSON.stringify(body) }),
  createCategory: (body) =>
    request('/admin/categories', { method: 'POST', body: JSON.stringify(body) }),
  updateCategory: (id, body) =>
    request(`/admin/categories/${id}`, { method: 'PATCH', body: JSON.stringify(body) }),
  deleteCategory: (id) => request(`/admin/categories/${id}`, { method: 'DELETE' }),
  regions: () => request('/admin/regions'),
  createRegion: (body) =>
    request('/admin/regions', { method: 'POST', body: JSON.stringify(body) }),
  updateRegion: (code, body) =>
    request(`/admin/regions/${code}`, { method: 'PATCH', body: JSON.stringify(body) }),
  deleteRegion: (code) => request(`/admin/regions/${code}`, { method: 'DELETE' }),
  reviewEvent: (id, body) =>
    request(`/admin/events/${id}/review`, { method: 'POST', body: JSON.stringify(body) }),
  featureFlags: () => request('/admin/feature-flags'),
  updateFeatureFlag: (key, body) =>
    request(`/admin/feature-flags/${key}`, { method: 'PATCH', body: JSON.stringify(body) }),
  audit: (filters = {}) => request(`/admin/audit${params(filters)}`),
  eventLog: (filters = {}) => request(`/admin/event-log${params(filters)}`),
  announcement: (body) =>
    request('/admin/announcements', { method: 'POST', body: JSON.stringify(body) }),
}

export { API_BASE }
