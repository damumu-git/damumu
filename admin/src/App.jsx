import { useCallback, useEffect, useMemo, useState } from 'react'
import { API_BASE, api } from './api'
import './App.css'

const navigation = [
  { id: 'dashboard', label: '运营概览', icon: '⌁' },
  { id: 'users', label: '用户管理', icon: '◉' },
  { id: 'events', label: '活动管理', icon: '◇' },
  { id: 'reports', label: '举报治理', icon: '△' },
  { id: 'safety', label: '安全警报', icon: '!' },
  { id: 'categories', label: '分类配置', icon: '⊞' },
  { id: 'regions', label: '地区管理', icon: '⌖' },
  { id: 'avatars', label: '系统头像', icon: '◎' },
  { id: 'audit', label: '审计日志', icon: '≡' },
  { id: 'settings', label: '功能开关', icon: '⚙' },
]

const statusText = {
  active: '正常',
  pending: '待处理',
  pending_review: '待审核',
  suspended: '已暂停',
  banned: '已封禁',
  draft: '草稿',
  published: '已发布',
  full: '已满员',
  hidden: '已隐藏',
  cancelled: '已取消',
  completed: '已完成',
  submitted: '新举报',
  triaged: '已分诊',
  investigating: '调查中',
  resolved: '已解决',
  dismissed: '已驳回',
  appealed: '申诉中',
  open: '待响应',
  contacted: '已联系',
  acknowledged: '已确认',
  false_alarm: '误报',
}

const formatDate = (value, withTime = true) => {
  if (!value) return '—'
  const date = new Date(value)
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  }).format(date)
}

const compactNumber = (value) =>
  new Intl.NumberFormat('zh-CN', { notation: 'compact' }).format(Number(value ?? 0))

function useResource(loader, dependencies = []) {
  const [state, setState] = useState({ data: null, loading: true, error: '' })
  const load = useCallback(async () => {
    setState((current) => ({ ...current, loading: true, error: '' }))
    try {
      const response = await loader()
      setState({ data: response, loading: false, error: '' })
    } catch (error) {
      setState({ data: null, loading: false, error: error.message })
    }
  // The dependency list is supplied by each resource page.
  // eslint-disable-next-line react-hooks/exhaustive-deps, react-hooks/use-memo
  }, dependencies)
  useEffect(() => { load() }, [load])
  return { ...state, reload: load }
}

function Status({ value }) {
  return <span className={`status status-${value}`}>{statusText[value] ?? value ?? '未知'}</span>
}

function PageState({ loading, error, empty, onRetry, children }) {
  if (loading) {
    return <div className="page-state"><span className="spinner" /><p>正在读取业务数据…</p></div>
  }
  if (error) {
    return (
      <div className="page-state error-state">
        <strong>暂时无法连接 REST API</strong>
        <p>{error}</p>
        <code>{API_BASE}</code>
        <button className="button secondary" onClick={onRetry}>重新连接</button>
      </div>
    )
  }
  if (empty) {
    return <div className="page-state"><span className="empty-icon">○</span><strong>暂无数据</strong><p>符合当前条件的记录会显示在这里。</p></div>
  }
  return children
}

function FilterBar({ search, setSearch, placeholder, children }) {
  return (
    <div className="filter-bar">
      <label className="search-box">
        <span>⌕</span>
        <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={placeholder} />
      </label>
      {children}
    </div>
  )
}

function Dashboard() {
  const resource = useResource(api.dashboard, [])
  const payload = resource.data?.data
  const metrics = payload?.metrics ?? {}
  const cards = [
    { label: '累计用户', value: metrics.total_users, note: `近 7 日 +${metrics.new_users_7d ?? 0}`, accent: 'green' },
    { label: '在架活动', value: metrics.active_events, note: `累计 ${metrics.total_events ?? 0} 场`, accent: 'amber' },
    { label: '待处理举报', value: metrics.open_reports, note: '按优先级处置', accent: 'red' },
    { label: '安全警报', value: metrics.open_safety_alerts, note: '需及时响应', accent: 'blue' },
  ]
  const trend = payload?.trend ?? []
  const maxTrend = Math.max(1, ...trend.map((item) => Number(item.users) + Number(item.applications)))

  return (
    <PageState {...resource} onRetry={resource.reload}>
      <div className="stats-grid">
        {cards.map((card) => (
          <article className={`stat-card accent-${card.accent}`} key={card.label}>
            <div className="stat-head"><span>{card.label}</span><i /></div>
            <strong>{compactNumber(card.value)}</strong>
            <small>{card.note}</small>
          </article>
        ))}
      </div>
      <div className="dashboard-grid">
        <section className="panel trend-panel">
          <div className="panel-heading">
            <div><span className="kicker">7 日趋势</span><h3>社区增长与报名</h3></div>
            <div className="legend"><span><i className="green-dot" />用户</span><span><i className="amber-dot" />报名</span></div>
          </div>
          <div className="trend-chart">
            {trend.map((item) => (
              <div className="trend-day" key={item.day}>
                <div className="bars">
                  <i className="user-bar" style={{ height: `${Math.max(4, Number(item.users) / maxTrend * 100)}%` }} />
                  <i className="join-bar" style={{ height: `${Math.max(4, Number(item.applications) / maxTrend * 100)}%` }} />
                </div>
                <span>{formatDate(item.day, false)}</span>
              </div>
            ))}
          </div>
        </section>
        <section className="panel pulse-panel">
          <div className="panel-heading"><div><span className="kicker">实时脉搏</span><h3>过去 24 小时</h3></div></div>
          <div className="pulse-number">{compactNumber(metrics.messages_24h)}</div>
          <p>条站内消息</p>
          <div className="pulse-row"><span>累计签到</span><strong>{compactNumber(metrics.total_checkins)}</strong></div>
          <div className="pulse-row"><span>系统状态</span><strong className="healthy">运行正常</strong></div>
        </section>
      </div>
      <div className="dashboard-grid equal">
        <section className="panel">
          <div className="panel-heading"><div><span className="kicker">活动供给</span><h3>最新创建</h3></div></div>
          <div className="compact-list">
            {(payload?.recentEvents ?? []).map((event) => (
              <div className="compact-row" key={event.id}>
                <span className="event-symbol">◇</span>
                <div><strong>{event.title}</strong><small>{event.organizer_name ?? '未完善资料'} · {formatDate(event.starts_at)}</small></div>
                <Status value={event.status} />
              </div>
            ))}
            {!payload?.recentEvents?.length && <p className="inline-empty">暂无活动</p>}
          </div>
        </section>
        <section className="panel">
          <div className="panel-heading"><div><span className="kicker">治理队列</span><h3>优先举报</h3></div></div>
          <div className="compact-list">
            {(payload?.priorityReports ?? []).map((report) => (
              <div className="compact-row" key={report.id}>
                <span className={`priority priority-${report.priority}`}>P{report.priority}</span>
                <div><strong>{report.category_code}</strong><small>{report.reporter_name ?? '匿名用户'} · {formatDate(report.created_at)}</small></div>
                <Status value={report.status} />
              </div>
            ))}
            {!payload?.priorityReports?.length && <p className="inline-empty">举报队列为空</p>}
          </div>
        </section>
      </div>
    </PageState>
  )
}

function Users() {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [notice, setNotice] = useState('')
  const resource = useResource(() => api.users({ q: search, status, limit: 50 }), [search, status])
  const rows = resource.data?.data ?? []

  const changeStatus = async (user, nextStatus) => {
    const reason = window.prompt(`将「${user.nickname ?? user.id}」设为${statusText[nextStatus]}，请输入原因：`)
    if (reason === null) return
    try {
      await api.updateUserStatus(user.id, { status: nextStatus, reason, actorUserId: null })
      setNotice('用户状态已更新并写入审计日志')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }

  return (
    <section className="panel full-panel">
      <div className="panel-heading">
        <div><span className="kicker">Identity & trust</span><h3>用户管理</h3><p>账号状态、信誉和被举报情况</p></div>
        <span className="count-badge">{resource.data?.meta?.total ?? 0} 位用户</span>
      </div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <FilterBar search={search} setSearch={setSearch} placeholder="搜索昵称或用户 UUID">
        <select value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="">全部状态</option><option value="active">正常</option>
          <option value="suspended">暂停</option><option value="banned">封禁</option>
        </select>
      </FilterBar>
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="table-wrap">
          <table>
            <thead><tr><th>用户</th><th>地区</th><th>身份</th><th>信誉</th><th>活动记录</th><th>举报</th><th>状态</th><th /></tr></thead>
            <tbody>
              {rows.map((user) => (
                <tr key={user.id}>
                  <td><div className="identity"><span className="avatar">{(user.nickname ?? '慕').slice(0, 1)}</span><div><strong>{user.nickname ?? '未设置昵称'}</strong><small>{user.id.slice(0, 8)}</small></div></div></td>
                  <td>{user.city_code}{user.district_code ? ` · ${user.district_code}` : ''}</td>
                  <td>{user.role === 'organizer' ? '组织者' : user.role === 'admin' ? '管理员' : '用户'}</td>
                  <td><strong>{Number(user.trust_score).toFixed(1)}</strong><small className="cell-note"> / 5.0</small></td>
                  <td>{user.attended_count} 参加 · {user.no_show_count} 爽约</td>
                  <td><span className={Number(user.report_count) ? 'danger-text' : ''}>{user.report_count}</span></td>
                  <td><Status value={user.status} /></td>
                  <td>
                    <div className="row-actions">
                      {user.status !== 'suspended' && <button onClick={() => changeStatus(user, 'suspended')}>暂停</button>}
                      {user.status !== 'active' && <button onClick={() => changeStatus(user, 'active')}>恢复</button>}
                      {user.status !== 'banned' && <button className="danger" onClick={() => changeStatus(user, 'banned')}>封禁</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
    </section>
  )
}

function Events() {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [notice, setNotice] = useState('')
  const resource = useResource(() => api.events({ q: search, status, limit: 50 }), [search, status])
  const rows = resource.data?.data ?? []

  const moderate = async (event, nextStatus) => {
    const reason = window.prompt(`处置活动「${event.title}」，请输入理由：`)
    if (reason === null) return
    try {
      await api.moderateEvent(event.id, {
        status: nextStatus, reasonCode: 'admin_decision', reason, actorUserId: null,
      })
      setNotice('活动处置已完成')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }

  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Supply operations</span><h3>活动管理</h3><p>供给质量、可见性和履约情况</p></div><span className="count-badge">{resource.data?.meta?.total ?? 0} 场活动</span></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <FilterBar search={search} setSearch={setSearch} placeholder="搜索活动标题">
        <select value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="">全部状态</option><option value="draft">草稿</option><option value="published">已发布</option>
          <option value="full">已满员</option><option value="hidden">已隐藏</option><option value="cancelled">已取消</option>
        </select>
      </FilterBar>
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="table-wrap">
          <table>
            <thead><tr><th>活动</th><th>组织者</th><th>时间 / 地点</th><th>名额</th><th>举报</th><th>状态</th><th /></tr></thead>
            <tbody>{rows.map((event) => (
              <tr key={event.id}>
                <td><div className="event-name"><span>{event.category_icon ?? '◇'}</span><div><strong>{event.title}</strong><small>{event.category_name}</small></div></div></td>
                <td>{event.organizer_name ?? '未设置'}</td>
                <td><strong>{formatDate(event.starts_at)}</strong><small className="block-note">{event.place_name ?? event.district_code ?? event.city_code}</small></td>
                <td><strong>{event.approved_count}/{event.capacity}</strong><small className="block-note">候补 {event.waitlist_count}</small></td>
                <td><span className={Number(event.report_count) ? 'danger-text' : ''}>{event.report_count}</span></td>
                <td><Status value={event.status} /></td>
                <td><div className="row-actions">
                  {event.status === 'hidden' ? <button onClick={() => moderate(event, 'published')}>恢复</button> : <button onClick={() => moderate(event, 'hidden')}>隐藏</button>}
                  {event.status !== 'cancelled' && <button className="danger" onClick={() => moderate(event, 'cancelled')}>取消</button>}
                </div></td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      </PageState>
    </section>
  )
}

function Reports() {
  const [status, setStatus] = useState('submitted')
  const [notice, setNotice] = useState('')
  const resource = useResource(() => api.reports({ status, limit: 50 }), [status])
  const rows = resource.data?.data ?? []

  const update = async (report, nextStatus) => {
    const note = window.prompt('请输入处置说明：')
    if (note === null) return
    try {
      await api.updateReport(report.id, {
        status: nextStatus,
        resolutionCode: nextStatus === 'dismissed' ? 'no_violation' : nextStatus === 'resolved' ? 'action_taken' : null,
        note,
        rowVersion: report.row_version,
        actorUserId: null,
      })
      setNotice('举报状态已更新')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }

  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Trust & safety</span><h3>举报治理</h3><p>按风险优先级处理用户、活动和消息举报</p></div><span className="count-badge critical">{resource.data?.meta?.total ?? 0} 条</span></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <div className="tabs">
        {['submitted', 'triaged', 'investigating', 'appealed', 'resolved', 'dismissed', ''].map((item) => (
          <button className={status === item ? 'active' : ''} key={item || 'all'} onClick={() => setStatus(item)}>{item ? statusText[item] : '全部'}</button>
        ))}
      </div>
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="report-grid">
          {rows.map((report) => (
            <article className="report-card" key={report.id}>
              <div className="report-top"><span className={`priority priority-${report.priority}`}>P{report.priority}</span><Status value={report.status} /><time>{formatDate(report.created_at)}</time></div>
              <h4>{report.category_code}</h4>
              <p>{report.description || '举报人未提供补充说明。'}</p>
              <dl><div><dt>对象</dt><dd>{report.target_type} · {report.target_summary || report.target_id.slice(0, 8)}</dd></div><div><dt>举报人</dt><dd>{report.reporter_name ?? '未知用户'}</dd></div><div><dt>证据</dt><dd>{report.evidence_count} 项</dd></div></dl>
              <div className="card-actions">
                {report.status === 'submitted' && <button className="button secondary" onClick={() => update(report, 'triaged')}>完成分诊</button>}
                {!['resolved', 'dismissed'].includes(report.status) && <button className="button dark" onClick={() => update(report, 'investigating')}>开始调查</button>}
                {!['resolved', 'dismissed'].includes(report.status) && <button className="button primary" onClick={() => update(report, 'resolved')}>处置完成</button>}
                {!['resolved', 'dismissed'].includes(report.status) && <button className="button ghost" onClick={() => update(report, 'dismissed')}>驳回</button>}
              </div>
            </article>
          ))}
        </div>
      </PageState>
    </section>
  )
}

function Safety() {
  const [status, setStatus] = useState('')
  const [notice, setNotice] = useState('')
  const resource = useResource(() => api.safetyAlerts({ status }), [status])
  const rows = resource.data?.data ?? []
  const update = async (alert, nextStatus) => {
    const note = window.prompt('记录本次响应情况：')
    if (note === null) return
    try {
      await api.updateSafetyAlert(alert.id, { status: nextStatus, note, actorUserId: null })
      setNotice('安全警报响应已记录')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Safety response</span><h3>安全警报</h3><p>此处仅提供联系人通知和运营响应，不代替紧急救援</p></div><select value={status} onChange={(event) => setStatus(event.target.value)}><option value="">全部状态</option><option value="open">待响应</option><option value="contacted">已联系</option><option value="resolved">已解决</option></select></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="safety-list">{rows.map((alert) => (
          <article className={`safety-card ${alert.status === 'open' ? 'urgent' : ''}`} key={alert.id}>
            <div className="safety-mark">!</div>
            <div className="safety-copy"><div><Status value={alert.status} /><time>{formatDate(alert.created_at)}</time></div><h4>{alert.nickname ?? '未设置昵称'} · {alert.alert_type}</h4><p>{alert.event_title ?? '非活动场景'} · 下次确认 {formatDate(alert.next_due_at)}</p></div>
            <div className="card-actions vertical">
              {alert.status === 'open' && <button className="button dark" onClick={() => update(alert, 'contacted')}>已联系紧急联系人</button>}
              {!['resolved', 'false_alarm'].includes(alert.status) && <button className="button primary" onClick={() => update(alert, 'resolved')}>标记已解决</button>}
              {!['resolved', 'false_alarm'].includes(alert.status) && <button className="button ghost" onClick={() => update(alert, 'false_alarm')}>确认误报</button>}
            </div>
          </article>
        ))}</div>
      </PageState>
    </section>
  )
}

const categoryPayload = (category, overrides = {}) => ({
  code: category.code,
  nameZhCn: category.name_zh_cn,
  nameEnUs: category.name_en_us || null,
  nameKoKr: category.name_ko_kr || null,
  descriptionZhCn: category.description_zh_cn || null,
  descriptionEnUs: category.description_en_us || null,
  descriptionKoKr: category.description_ko_kr || null,
  icon: category.icon || null,
  iconKey: category.icon_key || null,
  color: category.color || null,
  parentId: category.parent_id || null,
  sortOrder: Number(category.sort_order || 0),
  isActive: Boolean(category.is_active),
  isFeatured: Boolean(category.is_featured),
  ...overrides,
})

function CategoryEditor({ category, rows, onClose, onSaved }) {
  const [form, setForm] = useState(category ? categoryPayload(category) : {
    code: '', nameZhCn: '', nameEnUs: '', nameKoKr: '',
    descriptionZhCn: '', descriptionEnUs: '', descriptionKoKr: '',
    icon: '✨', iconKey: null, color: '#1F7A55', parentId: null,
    sortOrder: 10, isActive: true, isFeatured: false,
  })
  const [status, setStatus] = useState('')
  const parents = rows.filter((row) => row.level === 1 && row.id !== category?.id)
  const update = (key, value) => setForm((current) => ({ ...current, [key]: value }))
  const submit = async (event) => {
    event.preventDefault()
    setStatus('保存中…')
    try {
      if (category) await api.updateCategory(category.id, form)
      else await api.createCategory(form)
      onSaved(category ? '分类资料已更新' : '新分类已创建')
    } catch (error) { setStatus(error.message) }
  }
  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <form className="dialog category-dialog" onSubmit={submit} onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-head"><div><span className="kicker">Taxonomy editor</span><h3>{category ? '编辑分类' : '新建分类'}</h3></div><button type="button" onClick={onClose}>×</button></div>
        <div className="category-form-grid">
          <label>父级分类<select value={form.parentId ?? ''} onChange={(e) => update('parentId', e.target.value || null)}><option value="">无（作为大分类）</option>{parents.map((row) => <option key={row.id} value={row.id}>{'　'.repeat(row.level - 1)}{row.full_path}</option>)}</select></label>
          <label>唯一代码<input required pattern="[a-z0-9_]+" value={form.code} onChange={(e) => update('code', e.target.value.toLowerCase())} placeholder="例如 outdoor_hiking" /></label>
          <label>图标 Emoji<input value={form.icon ?? ''} onChange={(e) => update('icon', e.target.value)} /></label>
          <label>插画资源键<input value={form.iconKey ?? ''} onChange={(e) => update('iconKey', e.target.value || null)} placeholder="例如 food；未提供时显示 Emoji" /></label>
          <label>主题颜色<input type="color" value={form.color || '#1F7A55'} onChange={(e) => update('color', e.target.value)} /></label>
          <label>中文名称<input required value={form.nameZhCn} onChange={(e) => update('nameZhCn', e.target.value)} /></label>
          <label>English<input value={form.nameEnUs ?? ''} onChange={(e) => update('nameEnUs', e.target.value)} /></label>
          <label>한국어<input value={form.nameKoKr ?? ''} onChange={(e) => update('nameKoKr', e.target.value)} /></label>
          <label>排序<input type="number" value={form.sortOrder} onChange={(e) => update('sortOrder', Number(e.target.value))} /></label>
        </div>
        <label>中文说明<textarea rows="2" value={form.descriptionZhCn ?? ''} onChange={(e) => update('descriptionZhCn', e.target.value)} /></label>
        <div className="category-form-grid">
          <label>English description<textarea rows="2" value={form.descriptionEnUs ?? ''} onChange={(e) => update('descriptionEnUs', e.target.value)} /></label>
          <label>한국어 설명<textarea rows="2" value={form.descriptionKoKr ?? ''} onChange={(e) => update('descriptionKoKr', e.target.value)} /></label>
        </div>
        <label className="category-active"><input type="checkbox" checked={form.isActive} onChange={(e) => update('isActive', e.target.checked)} /> 在 App 中启用此分类</label>
        {!form.parentId && <label className="category-active"><input type="checkbox" checked={form.isFeatured} onChange={(e) => update('isFeatured', e.target.checked)} /> 默认展示在发布页</label>}
        {status && <p className="dialog-status">{status}</p>}
        <div className="dialog-actions"><button type="button" className="button ghost" onClick={onClose}>取消</button><button className="button primary">保存分类</button></div>
      </form>
    </div>
  )
}

function Categories() {
  const [notice, setNotice] = useState('')
  const [level, setLevel] = useState(0)
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState(undefined)
  const resource = useResource(api.categories, [])
  const rows = resource.data?.data ?? []
  const visible = rows.filter((row) =>
    (!level || row.level === level) &&
    (!search || `${row.full_path} ${row.code} ${row.name_en_us ?? ''} ${row.name_ko_kr ?? ''}`.toLowerCase().includes(search.toLowerCase())))
  const toggle = async (category) => {
    try {
      await api.updateCategory(category.id, categoryPayload(category, { isActive: !category.is_active }))
      setNotice('分类状态已更新')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  const saved = (message) => { setEditing(undefined); setNotice(message); resource.reload() }
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Three-level taxonomy</span><h3>活动分类</h3><p>大分类用于导航，中分类用于聚合，小分类供发布活动时最终选择</p></div><button className="button primary" onClick={() => setEditing(null)}>＋ 新建分类</button></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <div className="category-summary">
        {[['全部', 0], ['大分类', 1], ['小分类', 2]].map(([label, value]) => <button className={level === value ? 'active' : ''} key={value} onClick={() => setLevel(value)}><strong>{value ? rows.filter((r) => r.level === value).length : rows.length}</strong><span>{label}</span></button>)}
      </div>
      <FilterBar search={search} setSearch={setSearch} placeholder="搜索分类路径、代码或多语言名称" />
      <PageState {...resource} empty={!visible.length} onRetry={resource.reload}>
        <div className="category-grid">{visible.map((category) => (
          <article className={`category-card level-${category.level} ${category.is_active ? '' : 'disabled'}`} key={category.id} style={{ '--category-color': category.color || '#1F7A55' }}>
            <span className="category-icon">{category.icon ?? '◇'}</span>
            <div className="category-copy"><span className="category-level">{category.level === 1 ? '大分类' : '小分类'}</span><h4>{category.name_zh_cn}</h4><p className="category-path">{category.full_path}</p><p>{category.name_en_us || '未设置英文'} · {category.name_ko_kr || '未设置韩文'}</p><p>{category.description_zh_cn || '暂无分类说明'}</p><small>{category.child_count} 个子类 · {category.event_count} 场活动 · 排序 {category.sort_order}</small><code>{category.code}</code></div>
            <div className="category-actions"><button onClick={() => setEditing(category)}>编辑</button><button className="danger" onClick={async () => { if (!window.confirm(`确认删除「${category.name_zh_cn}」？`)) return; try { await api.deleteCategory(category.id); setNotice('分类已删除'); resource.reload() } catch (error) { setNotice(error.message) } }}>删除</button><label className="switch"><input type="checkbox" checked={category.is_active} onChange={() => toggle(category)} /><span /></label></div>
          </article>
        ))}</div>
      </PageState>
      {editing !== undefined && <CategoryEditor category={editing} rows={rows} onClose={() => setEditing(undefined)} onSaved={saved} />}
    </section>
  )
}

const regionPayload = (region, overrides = {}) => ({
  code: region.code,
  parentCode: region.parent_code || null,
  level: Number(region.level),
  nameZhCn: region.name_zh_cn,
  nameKoKr: region.name_ko_kr,
  nameEnUs: region.name_en_us,
  sortOrder: Number(region.sort_order || 0),
  isActive: Boolean(region.is_active),
  ...overrides,
})

function RegionEditor({ region, cities, onClose, onSaved }) {
  const [form, setForm] = useState(region ? regionPayload(region) : {
    code: '', parentCode: null, level: 1, nameZhCn: '', nameKoKr: '', nameEnUs: '', sortOrder: 10, isActive: true,
  })
  const [status, setStatus] = useState('')
  const update = (key, value) => setForm((current) => ({ ...current, [key]: value }))
  const submit = async (event) => {
    event.preventDefault()
    setStatus('保存中…')
    try {
      const body = { ...form, parentCode: form.level === 1 ? null : form.parentCode }
      if (region) await api.updateRegion(region.code, body)
      else await api.createRegion(body)
      onSaved(region ? '地区资料已更新' : '地区已创建')
    } catch (error) { setStatus(error.message) }
  }
  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <form className="dialog" onSubmit={submit} onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-head"><div><span className="kicker">Region editor</span><h3>{region ? '编辑地区' : '新建地区'}</h3></div><button type="button" onClick={onClose}>×</button></div>
        <label>层级<select value={form.level} onChange={(e) => update('level', Number(e.target.value))}><option value={1}>城市/道</option><option value={2}>区/市</option></select></label>
        {form.level === 2 && <label>所属城市<select required value={form.parentCode ?? ''} onChange={(e) => update('parentCode', e.target.value)}><option value="">请选择</option>{cities.map((city) => <option key={city.code} value={city.code}>{city.name_zh_cn}</option>)}</select></label>}
        <label>标准代码<input required readOnly={Boolean(region)} value={form.code} onChange={(e) => update('code', e.target.value.toUpperCase())} placeholder="例如 KR-11" /></label>
        <label>中文名称<input required value={form.nameZhCn} onChange={(e) => update('nameZhCn', e.target.value)} /></label>
        <label>한국어<input required value={form.nameKoKr} onChange={(e) => update('nameKoKr', e.target.value)} /></label>
        <label>English<input required value={form.nameEnUs} onChange={(e) => update('nameEnUs', e.target.value)} /></label>
        <label>排序<input type="number" value={form.sortOrder} onChange={(e) => update('sortOrder', Number(e.target.value))} /></label>
        <label className="category-active"><input type="checkbox" checked={form.isActive} onChange={(e) => update('isActive', e.target.checked)} /> 在 App 中启用此地区</label>
        {status && <p className="dialog-status">{status}</p>}
        <div className="dialog-actions"><button type="button" className="button ghost" onClick={onClose}>取消</button><button className="button primary">保存地区</button></div>
      </form>
    </div>
  )
}

function Regions() {
  const [notice, setNotice] = useState('')
  const [editing, setEditing] = useState(undefined)
  const resource = useResource(api.regions, [])
  const rows = resource.data?.data ?? []
  const cities = rows.filter((row) => row.level === 1)
  const saved = (message) => { setEditing(undefined); setNotice(message); resource.reload() }
  const toggle = async (region) => {
    try {
      await api.updateRegion(region.code, regionPayload(region, { isActive: !region.is_active }))
      setNotice('地区状态已更新')
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Administrative regions</span><h3>行政地区</h3><p>标准代码保持稳定，名称、排序和 App 可见状态可由运营维护</p></div><button className="button primary" onClick={() => setEditing(null)}>＋ 新建地区</button></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="table-wrap"><table><thead><tr><th>地区</th><th>代码</th><th>层级</th><th>English / 한국어</th><th>活动</th><th>启用</th><th>操作</th></tr></thead><tbody>{rows.map((region) => (
          <tr key={region.code}><td><strong>{region.name_zh_cn}</strong><small className="block-note">{region.parent_name || '一级地区'}</small></td><td><code>{region.code}</code></td><td>{region.level === 1 ? '城市/道' : '区/市'}</td><td>{region.name_en_us}<small className="block-note">{region.name_ko_kr}</small></td><td>{region.event_count}</td><td><label className="switch"><input type="checkbox" checked={region.is_active} onChange={() => toggle(region)} /><span /></label></td><td><div className="row-actions"><button onClick={() => setEditing(region)}>编辑</button><button className="danger" onClick={async () => { if (!window.confirm(`确认删除「${region.name_zh_cn}」？`)) return; try { await api.deleteRegion(region.code); setNotice('地区已删除'); resource.reload() } catch (error) { setNotice(error.message) } }}>删除</button></div></td></tr>
        ))}</tbody></table></div>
      </PageState>
      {editing !== undefined && <RegionEditor region={editing} cities={cities} onClose={() => setEditing(undefined)} onSaved={saved} />}
    </section>
  )
}

function SystemAvatars() {
  const [notice, setNotice] = useState('')
  const resource = useResource(api.systemAvatars, [])
  const rows = resource.data?.data ?? []
  const upload = async (event) => {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    try {
      await api.uploadSystemAvatar(form)
      setNotice('系统头像已上传')
      event.currentTarget.reset()
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  const toggle = async (avatar) => {
    try {
      await api.updateSystemAvatar(avatar.id, {
        code: avatar.code,
        nameZhCn: avatar.name_zh_cn,
        nameEnUs: avatar.name_en_us,
        nameKoKr: avatar.name_ko_kr,
        sortOrder: avatar.sort_order,
        isActive: !avatar.is_active,
      })
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Avatar library</span><h3>系统头像库</h3><p>仅接收 512×512 JPEG，文件最大 1 MB</p></div></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <form className="avatar-upload" onSubmit={upload}>
        <input required name="code" placeholder="唯一代码，如 forest_fox" />
        <input required name="nameZhCn" placeholder="中文名称" />
        <input required name="nameEnUs" placeholder="English name" />
        <input required name="nameKoKr" placeholder="한국어 이름" />
        <input name="sortOrder" type="number" defaultValue={rows.length * 10 + 10} />
        <input required name="image" type="file" accept="image/jpeg" />
        <button className="button primary">上传头像</button>
      </form>
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="avatar-grid">{rows.map((avatar) => (
          <article className={`avatar-card ${avatar.is_active ? '' : 'disabled'}`} key={avatar.id}>
            <img src={`${API_BASE}${avatar.image_url}`} alt={avatar.name_zh_cn} />
            <div><h4>{avatar.name_zh_cn}</h4><p>{avatar.name_en_us} · {avatar.name_ko_kr}</p><small>{avatar.code} · {avatar.byte_size} bytes</small></div>
            <label className="switch"><input type="checkbox" checked={avatar.is_active} onChange={() => toggle(avatar)} /><span /></label>
          </article>
        ))}</div>
      </PageState>
    </section>
  )
}

function Audit() {
  const [search, setSearch] = useState('')
  const resource = useResource(() => api.audit({ action: search, limit: 100 }), [search])
  const rows = resource.data?.data ?? []
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Immutable trail</span><h3>审计日志</h3><p>管理员高风险操作与敏感对象访问记录</p></div></div>
      <FilterBar search={search} setSearch={setSearch} placeholder="按准确操作代码筛选" />
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="timeline">{rows.map((row) => (
          <div className="timeline-item" key={row.id}><i /><time>{formatDate(row.created_at)}</time><div><strong>{row.action}</strong><p>{row.actor_name ?? '系统管理员'} · {row.target_type ?? 'system'} {row.target_id ? row.target_id.slice(0, 8) : ''}</p></div><code>{row.trace_id?.slice(0, 18) ?? '—'}</code></div>
        ))}</div>
      </PageState>
    </section>
  )
}

function Settings() {
  const [notice, setNotice] = useState('')
  const resource = useResource(api.featureFlags, [])
  const rows = resource.data?.data ?? []
  const toggle = async (flag) => {
    try {
      await api.updateFeatureFlag(flag.key, { enabled: !flag.enabled, actorUserId: null })
      setNotice(`${flag.key} 已${flag.enabled ? '关闭' : '开启'}`)
      resource.reload()
    } catch (error) { setNotice(error.message) }
  }
  return (
    <section className="panel full-panel">
      <div className="panel-heading"><div><span className="kicker">Feature control</span><h3>功能开关</h3><p>不发版控制灰度能力；不得在配置中保存密钥</p></div></div>
      {notice && <div className="notice" onClick={() => setNotice('')}>{notice}<span>×</span></div>}
      <PageState {...resource} empty={!rows.length} onRetry={resource.reload}>
        <div className="settings-list">{rows.map((flag) => (
          <div className="setting-row" key={flag.key}><div className="setting-code">{flag.key.slice(0, 2).toUpperCase()}</div><div><strong>{flag.key}</strong><p>{flag.description || '暂无说明'}</p><small>版本 {flag.version} · {formatDate(flag.updated_at)}</small></div><label className="switch"><input type="checkbox" checked={flag.enabled} onChange={() => toggle(flag)} /><span /></label></div>
        ))}</div>
      </PageState>
    </section>
  )
}

const pages = { dashboard: Dashboard, users: Users, events: Events, reports: Reports, safety: Safety, categories: Categories, regions: Regions, avatars: SystemAvatars, audit: Audit, settings: Settings }

function AnnouncementDialog({ onClose }) {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [status, setStatus] = useState('')
  const submit = async (event) => {
    event.preventDefault()
    setStatus('发送中…')
    try {
      const result = await api.announcement({ title, body, actorUserId: null })
      setStatus(`已发送给 ${result.data.recipients} 位用户`)
      setTimeout(onClose, 900)
    } catch (error) { setStatus(error.message) }
  }
  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <form className="dialog" onSubmit={submit} onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-head"><div><span className="kicker">Broadcast</span><h3>发布站内公告</h3></div><button type="button" onClick={onClose}>×</button></div>
        <label>公告标题<input required maxLength="160" value={title} onChange={(event) => setTitle(event.target.value)} /></label>
        <label>公告内容<textarea required maxLength="1000" rows="5" value={body} onChange={(event) => setBody(event.target.value)} /></label>
        {status && <p className="dialog-status">{status}</p>}
        <div className="dialog-actions"><button type="button" className="button ghost" onClick={onClose}>取消</button><button className="button primary">确认发布</button></div>
      </form>
    </div>
  )
}

function App() {
  const [active, setActive] = useState('dashboard')
  const [mobileNav, setMobileNav] = useState(false)
  const [announcement, setAnnouncement] = useState(false)
  const ActivePage = pages[active]
  const current = useMemo(() => navigation.find((item) => item.id === active), [active])

  return (
    <div className="admin-shell">
      <aside className={mobileNav ? 'sidebar open' : 'sidebar'}>
        <div className="brand"><div className="brand-mark">慕</div><div><strong>搭慕慕</strong><span>社区运营中心</span></div></div>
        <nav>{navigation.map((item) => (
          <button key={item.id} className={active === item.id ? 'active' : ''} onClick={() => { setActive(item.id); setMobileNav(false) }}>
            <i>{item.icon}</i><span>{item.label}</span>{item.id === 'reports' && <em>!</em>}
          </button>
        ))}</nav>
        <div className="sidebar-foot"><span className="health-dot" /><div><strong>API 已配置</strong><small>{API_BASE.replace(/^https?:\/\//, '')}</small></div></div>
      </aside>
      <main className="main-panel">
        <header className="topbar">
          <div className="title-row"><button className="menu-button" onClick={() => setMobileNav(!mobileNav)}>☰</button><div><span className="breadcrumb">搭慕慕 / 运营管理</span><h1>{current.label}</h1></div></div>
          <div className="top-actions"><span className="today">{new Intl.DateTimeFormat('zh-CN', { month: 'long', day: 'numeric', weekday: 'short' }).format(new Date())}</span><button className="announcement-button" onClick={() => setAnnouncement(true)}>发布公告</button><div className="admin-avatar">管</div></div>
        </header>
        <div className="page-content"><ActivePage /></div>
      </main>
      {announcement && <AnnouncementDialog onClose={() => setAnnouncement(false)} />}
    </div>
  )
}

export default App
