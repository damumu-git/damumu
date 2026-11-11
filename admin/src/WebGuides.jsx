import { useEffect, useState } from 'react'
import { api } from './api'

const blank = { slug: '', title: '', summary: '', body: '', cover_category: 'other', source_url: '', region_code: '', category_id: '', published: false, featured: false }
const covers = { other: '通用', outdoors: '户外', culture: '文化', food: '餐饮', sports: '运动', study: '学习', social: '社交' }

export default function WebGuides() {
  const [items, setItems] = useState([])
  const [regions, setRegions] = useState([])
  const [categories, setCategories] = useState([])
  const [draft, setDraft] = useState(blank)
  const [editing, setEditing] = useState(false)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let cancelled = false
    Promise.all([api.webGuides(), api.regions(), api.categories()]).then(
      ([guides, areas, kinds]) => {
        if (cancelled) return
        setItems(guides.data)
        setRegions(areas.data.filter(item => item.is_active))
        setCategories(kinds.data.filter(item => item.is_active))
      },
      reason => { if (!cancelled) setError(reason.message) },
    )
    return () => { cancelled = true }
  }, [])

  function change(key, value) {
    setDraft(current => ({ ...current, [key]: value }))
  }
  async function save(event) {
    event.preventDefault()
    setBusy(true)
    setError('')
    try {
      await api.saveWebGuide(draft.slug, {
        title: draft.title, summary: draft.summary, body: draft.body,
        coverCategory: draft.cover_category, sourceUrl: draft.source_url || null,
        published: draft.published, featured: draft.featured,
        regionCode: draft.region_code || null, categoryId: draft.category_id || null,
      })
      setEditing(true)
      setItems((await api.webGuides()).data)
    } catch (reason) { setError(reason.message) }
    finally { setBusy(false) }
  }

  return <section className="panel">
    <div className="panel-heading">
      <h3>周末指南</h3>
      <button className="button secondary" onClick={() => { setDraft(blank); setEditing(false); setError('') }}>新建指南</button>
    </div>
    {error && <p role="alert">{error}</p>}
    <ul>{items.map(item => <li key={item.slug}>
      <button className="button secondary" onClick={() => { setDraft(item); setEditing(true); setError('') }}>{item.title}</button>
      {' '}{item.published ? '已发布' : '未发布'}{item.featured ? ' · 首页推荐' : ''}
    </li>)}</ul>
    <form className="form-grid" onSubmit={save}>
      <label>网址标识<input required pattern="[a-z0-9]+(-[a-z0-9]+)*" maxLength={80} disabled={editing} value={draft.slug} onChange={e => change('slug', e.target.value)} /></label>
      <label>标题<input required minLength={2} maxLength={120} value={draft.title} onChange={e => change('title', e.target.value)} /></label>
      <label>摘要<input required minLength={2} maxLength={300} value={draft.summary} onChange={e => change('summary', e.target.value)} /></label>
      <label>正文<textarea required minLength={2} maxLength={20000} rows={8} value={draft.body} onChange={e => change('body', e.target.value)} /></label>
      <label>封面分类<select value={draft.cover_category} onChange={e => change('cover_category', e.target.value)}>{Object.entries(covers).map(([code, name]) => <option key={code} value={code}>{name}</option>)}</select></label>
      <label>专题地区<select value={draft.region_code ?? ''} onChange={e => change('region_code', e.target.value)}><option value="">不限</option>{regions.map(item => <option key={item.code} value={item.code}>{item.name_zh_cn}</option>)}</select></label>
      <label>专题分类<select value={draft.category_id ?? ''} onChange={e => change('category_id', e.target.value)}><option value="">不限</option>{categories.map(item => <option key={item.id} value={item.id}>{item.name_zh_cn}</option>)}</select></label>
      <label>来源链接（选填）<input type="url" value={draft.source_url ?? ''} onChange={e => change('source_url', e.target.value)} /></label>
      <label><input type="checkbox" checked={draft.published} onChange={e => change('published', e.target.checked)} />公开发布</label>
      <label><input type="checkbox" checked={draft.featured} onChange={e => change('featured', e.target.checked)} />首页推荐</label>
      <button className="button primary" disabled={busy} type="submit">保存指南</button>
    </form>
  </section>
}
