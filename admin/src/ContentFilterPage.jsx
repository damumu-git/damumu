import { useEffect, useState } from 'react'
import { api } from './api'

export default function ContentFilterPage() {
  const [terms, setTerms] = useState(null)
  const [input, setInput] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    api.contentFilterTerms().then(({ data }) => {
      if (active) setTerms(data)
    }).catch((failure) => {
      if (active) setError(failure.message)
    })
    return () => { active = false }
  }, [])

  async function save(term, isEnabled) {
    setPending(true)
    setError('')
    try {
      const { data } = await api.saveContentFilterTerm({ term, isEnabled })
      setTerms((previous) => [data, ...(previous ?? []).filter((entry) => entry.term !== data.term)])
      return true
    } catch (failure) {
      setError(failure.message)
      return false
    } finally {
      setPending(false)
    }
  }

  return (
    <section className="panel">
      <p>已启用的词条会拦截网页和 App 的新提交。可以停用容易误判的词条。</p>
      <form className="toolbar" onSubmit={async (event) => {
        event.preventDefault()
        if (await save(input.trim(), true)) setInput('')
      }}>
        <label>词或短语 <input required minLength={2} maxLength={40} value={input}
          onChange={(event) => setInput(event.target.value)} disabled={pending} /></label>
        <button className="button primary" disabled={pending || input.trim().length < 2}>添加并启用</button>
      </form>
      {error && <p role="alert">{error}</p>}
      {terms && <table>
        <thead><tr><th>词条</th><th>状态</th><th>操作</th></tr></thead>
        <tbody>{terms.map((entry) => (
          <tr key={entry.term}>
            <td>{entry.term}</td><td>{entry.is_enabled ? '已启用' : '已停用'}</td>
            <td><button className="button secondary" type="button" disabled={pending}
              onClick={() => save(entry.term, !entry.is_enabled)}>
              {entry.is_enabled ? '停用' : '启用'}
            </button></td>
          </tr>
        ))}</tbody>
      </table>}
    </section>
  )
}
