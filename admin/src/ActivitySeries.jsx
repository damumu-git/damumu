import { useEffect, useState } from 'react'
import { api } from './api'

export default function ActivitySeries() {
  const [rows, setRows] = useState(null)
  const [regions, setRegions] = useState([])
  const [draft, setDraft] = useState({ userId: '', regionCode: '' })
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let live = true
    Promise.all([api.seriesProposals(), api.seriesEditor(), api.regions()]).then(([proposals, editor, areas]) => {
      if (!live) return
      setRows(proposals.data)
      setDraft({ userId: editor.data?.editor_id ?? '', regionCode: editor.data?.region_code ?? '' })
      setRegions(areas.data.filter((area) => area.is_active))
    }).catch((error) => { if (live) setMessage(error.message) })
    return () => { live = false }
  }, [])

  async function save(event) {
    event.preventDefault()
    setBusy(true)
    try {
      await api.saveSeriesEditor({ userId: draft.userId.trim() || null, regionCode: draft.regionCode || null })
      setMessage('已保存搭慕周末设置。')
    } catch (error) {
      setMessage(error.message)
    } finally {
      setBusy(false)
    }
  }

  return <div>
    <section className="panel">
      <h2>搭慕周末</h2>
      <form className="form-grid" onSubmit={save}>
        <label>系列运营者账号 ID<input value={draft.userId} onChange={(event) => setDraft({ ...draft, userId: event.target.value })} /></label>
        <label>试点地区<select value={draft.regionCode} onChange={(event) => setDraft({ ...draft, regionCode: event.target.value })}>
          <option value="">暂未设置</option>
          {regions.map((area) => <option key={area.code} value={area.code}>{area.name_zh_cn} · {area.code}</option>)}
        </select></label>
        <button className="button primary" disabled={busy || rows === null}>保存</button>
      </form>
      {message && <p role="status">{message}</p>}
    </section>
    <section className="panel">
      <h2>组织者与场地申请</h2>
      {rows?.length === 0 && <p>暂无申请。</p>}
      <ul>{rows?.map((row) => <li key={row.id}>
        <strong>{row.kind === 'venue' ? '场地合作' : '组织者申请'} · {row.region_name}</strong>
        <p>{row.body}</p><small>{row.user_id} · {new Date(row.created_at).toLocaleString()}</small>
      </li>)}</ul>
    </section>
  </div>
}
