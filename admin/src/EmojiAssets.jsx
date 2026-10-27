import { createContext, useContext, useEffect, useState } from 'react'
import { api, mediaUrl } from './api'
import './emoji-assets.css'

const Assets = createContext([])
const normalized = (value) => (value || '').replace(/[\uFE0E\uFE0F]/g, '')
const refresh = () => window.dispatchEvent(new Event('emoji-assets-changed'))

export function EmojiAssetsProvider({ children }) {
  const [assets, setAssets] = useState([])
  useEffect(() => {
    let live = true
    const load = () => api.emojiAssets().then((response) => {
      if (live) setAssets(response.data)
    }).catch(() => {})
    load()
    window.addEventListener('emoji-assets-changed', load)
    return () => { live = false; window.removeEventListener('emoji-assets-changed', load) }
  }, [])
  return <Assets.Provider value={assets}>{children}</Assets.Provider>
}

export function EmojiIcon({ emoji = '◇', url, size = 24 }) {
  const assets = useContext(Assets)
  const resolved = url || assets.find((item) => normalized(item.emoji) === normalized(emoji))?.image_url
  const [failed, setFailed] = useState(null)
  if (!resolved || failed === resolved) return <span aria-label={emoji}>{emoji}</span>
  return <img className="emoji-art" src={mediaUrl(resolved)} alt={emoji} width={size} height={size}
    onError={() => setFailed(resolved)} />
}

export function EmojiAssetSelect({ value, onChange }) {
  const assets = useContext(Assets)
  return <select value={value || ''} onChange={(event) => onChange(event.target.value || null)}>
    <option value="">按 Emoji 自动匹配</option>
    {value && !assets.some((item) => item.key === value) && <option value={value}>{value}（旧资源键）</option>}
    {assets.map((item) => <option value={item.key} key={item.key}>{item.name} · {item.key}</option>)}
  </select>
}

export function EmojiAssetManager() {
  const [rows, setRows] = useState([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState(null)
  const [search, setSearch] = useState('')
  const load = () => api.adminEmojiAssets().then((response) => { setRows(response.data); setError('') })
    .catch((reason) => setError(reason.message)).finally(() => setLoading(false))
  useEffect(() => { load() }, [])
  const save = async (event) => {
    event.preventDefault()
    const body = new FormData(event.currentTarget)
    setBusy(true); setError('')
    try {
      if (editing.key && !body.get('image')?.size) {
        await api.updateEmojiAsset(editing.key, { name: body.get('name'), isActive: editing.is_active })
      } else {
        await api.uploadEmojiAsset(body)
      }
      setEditing(null); refresh(); await load()
    } catch (reason) { setError(reason.message) }
    finally { setBusy(false) }
  }
  const toggle = async (row) => {
    setBusy(true)
    try {
      await api.updateEmojiAsset(row.key, { name: row.name, isActive: !row.is_active })
      refresh(); await load()
    } catch (reason) { setError(reason.message) }
    finally { setBusy(false) }
  }
  return <section className="panel full-panel">
    <div className="panel-heading"><div><span className="kicker">Icon library</span><h3>图标素材</h3>
      <p>64×64 PNG，最大200KB。替换后使用新地址；停用后保留原Emoji回退。</p></div>
      <button className="button primary" onClick={() => setEditing({})}>上传新图标</button></div>
    {error && <p role="alert">{error} <button onClick={load}>重新读取</button></p>}
    {loading && <p>正在读取图标…</p>}
    <label className="emoji-search">搜索图标<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="名称、资源键或Emoji" /></label>
    <div className="emoji-library">{rows.filter((row) => `${row.name} ${row.key} ${row.emoji}`.includes(search)).map((row) =>
      <article className="emoji-tile" key={row.key}>
        <EmojiIcon emoji={row.emoji} url={row.image_url} size={64} />
        <div><strong>{row.name}</strong><small>{row.key} · {(row.byte_size / 1024).toFixed(1)}KB</small>
          <small>{row.is_active ? '使用中' : '已停用'}</small></div>
        <button disabled={busy} onClick={() => setEditing(row)}>替换图片 / 名称</button>
        <button disabled={busy} onClick={() => toggle(row)}>{row.is_active ? '停用' : '启用'}</button>
      </article>)}</div>
    {!loading && !rows.length && !error && <p>暂无图标，请上传。</p>}
    {editing && <div className="dialog-backdrop"><form className="dialog" onSubmit={save}>
      <h3>{editing.key ? '替换图标' : '上传新图标'}</h3>
      <label>资源键<input name="key" required pattern="[a-z][a-z0-9-]{0,63}" defaultValue={editing.key || ''} readOnly={!!editing.key} /></label>
      <label>对应Emoji<input name="emoji" required maxLength={32} defaultValue={editing.emoji || ''} readOnly={!!editing.key} /></label>
      <label>名称<input name="name" required maxLength={100} defaultValue={editing.name || ''} /></label>
      <label>64×64 PNG<input name="image" type="file" accept="image/png" required={!editing.key} /></label>
      <div className="dialog-actions"><button type="button" disabled={busy} onClick={() => setEditing(null)}>取消</button>
        <button className="button primary" disabled={busy}>{busy ? '保存中…' : '上传并保存'}</button></div>
    </form></div>}
  </section>
}
