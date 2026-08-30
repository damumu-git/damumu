const API_BASE = import.meta.env.VITE_API_BASE ?? 'http://localhost:8080/api/v1'
const ADMIN_KEY = import.meta.env.VITE_ADMIN_KEY ?? 'muda-admin-local'

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
  health: () => request('/health'),
  dashboard: () => request('/admin/dashboard'),
  users: (filters = {}) => request(`/admin/users${params(filters)}`),
  user: (id) => request(`/admin/users/${id}`),
  updateUserStatus: (id, body) =>
    request(`/admin/users/${id}/status`, { method: 'PATCH', body: JSON.stringify(body) }),
  events: (filters = {}) => request(`/admin/events${params(filters)}`),
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
  announcement: (body) =>
    request('/admin/announcements', { method: 'POST', body: JSON.stringify(body) }),
}

export { API_BASE }
