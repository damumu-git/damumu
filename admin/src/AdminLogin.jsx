import { useEffect, useState } from 'react'
import { api } from './api'

export default function AdminLogin({ children }) {
  const [account, setAccount] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    api.adminSession().then((result) => setAccount(result.data)).catch(() => {})
      .finally(() => setLoading(false))
    const expired = () => setAccount(null)
    window.addEventListener('admin-session-expired', expired)
    return () => window.removeEventListener('admin-session-expired', expired)
  }, [])
  if (loading) return <main className="admin-signin"><p role="status">正在验证登录…</p></main>
  if (account) return <>
    <div className="admin-account-bar">
      <span>{account.username} · {account.role}</span>
      <button type="button" disabled={busy} onClick={async () => {
        setBusy(true)
        try { await api.adminLogout(); setAccount(null) }
        catch (failure) { setError(failure.message) }
        finally { setBusy(false) }
      }}>退出登录</button>
      {error && <span role="alert">{error}</span>}
    </div>
    {children}
  </>
  return <main className="admin-signin">
    <form className="dialog" onSubmit={async (event) => {
      event.preventDefault()
      if (busy) return
      const form = event.currentTarget
      const values = Object.fromEntries(new FormData(form))
      setBusy(true)
      setError('')
      try {
        await api.adminLogin(values)
        const result = await api.adminSession()
        form.reset()
        setAccount(result.data)
      } catch (failure) { setError(failure.message) }
      finally { setBusy(false) }
    }}>
      <h1>搭木木管理登录</h1>
      <label>账号<input name="username" required maxLength={80} autoComplete="username" /></label>
      <label>密码<input name="password" type="password" required maxLength={256} autoComplete="current-password" /></label>
      <label>身份验证器验证码<input name="code" required inputMode="numeric" pattern="[0-9]{6}" maxLength={6} autoComplete="one-time-code" /></label>
      {error && <p role="alert">{error}</p>}
      <button className="button primary" disabled={busy}>{busy ? '验证中…' : '登录'}</button>
    </form>
  </main>
}
