import { useEffect, useState } from 'react'
import { FilePicker } from './AdminControls.jsx'
import { api, mediaUrl } from './api'

const bundledCoverBase = import.meta.env.VITE_APP_WEB_ORIGIN || 'https://app.damumu.com'
const majors = new Set(['food', 'sports', 'culture', 'outdoors', 'study', 'social', 'other'])

export function CategoryCoverPreview({ category, rows, selectedUrl }) {
  const parent = rows.find((row) => row.id === category.parent_id)
  const grandparent = rows.find((row) => row.id === parent?.parent_id)
  const root = grandparent || parent || category
  const directory = category.level === 1 ? '' : 'sub/'
  const bundled = new URL(`/assets/covers/${directory}${encodeURIComponent(category.code)}.webp`, bundledCoverBase).href
  const fallback = new URL(`/assets/covers/${majors.has(root.code) ? root.code : 'other'}.webp`, bundledCoverBase).href
  const managedUrl = category.cover_image_url || parent?.cover_image_url || grandparent?.cover_image_url
  const [failed, setFailed] = useState([])
  const src = [selectedUrl, managedUrl && mediaUrl(managedUrl), bundled, fallback].find((url) => url && !failed.includes(url))
  return <div className="category-cover-preview">
    {src ? <img src={src} alt={`${category.name_zh_cn}活动封面`} loading="lazy" onError={() => setFailed((urls) => [...urls, src])} /> : <span>封面暂不可用</span>}
  </div>
}

export default function CategoryCoverEditor({ category, rows, onClose, onSaved }) {
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview) }, [preview])
  useEffect(() => {
    function closeOnEscape(event) {
      if (event.key === 'Escape' && !busy) onClose()
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [busy, onClose])

  async function save(reset = false) {
    setBusy(true)
    setError('')
    try {
      if (reset) await api.resetCategoryCover(category.id)
      else {
        const form = new FormData()
        form.append('image', file)
        await api.saveCategoryCover(category.id, form)
      }
      onSaved(reset ? '已恢复默认封面' : '分类封面已更新')
    } catch (problem) {
      setError(problem.message)
    } finally {
      setBusy(false)
    }
  }

  return <div className="dialog-backdrop" onMouseDown={() => !busy && onClose()}>
    <form className="dialog category-dialog" role="dialog" aria-modal="true" aria-labelledby="category-cover-title"
      onMouseDown={(event) => event.stopPropagation()} onSubmit={(event) => { event.preventDefault(); if (file && !busy) save() }}>
      <div className="dialog-head"><h3 id="category-cover-title">{category.name_zh_cn} · 活动封面</h3>
        <button type="button" aria-label="关闭弹窗" disabled={busy} onClick={onClose}>×</button></div>
      <CategoryCoverPreview category={category} rows={rows} selectedUrl={file ? preview : null} />
      <p>这张图用于该分类未上传活动图片时的默认封面。建议使用横向 16:9 图片，支持 JPEG、PNG、WebP，最大 2 MB。</p>
      <FilePicker accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={(event) => {
        const next = event.target.files[0]
        if (next && next.size > 2_000_000) {
          setFile(null)
          setPreview(null)
          setError('图片不得超过 2 MB')
          event.target.value = ''
          return
        }
        setError('')
        setFile(next || null)
        setPreview(next ? URL.createObjectURL(next) : null)
      }} />
      {error && <p role="alert">{error}</p>}
      <div className="dialog-actions">
        {category.cover_image_url && <button type="button" disabled={busy} onClick={() => save(true)}>恢复默认</button>}
        <button type="submit" className="primary" disabled={busy || !file}>保存封面</button>
      </div>
    </form>
  </div>
}
