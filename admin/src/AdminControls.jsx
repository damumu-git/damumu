import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AdminDialogContext } from './admin-dialog-context'

export function FilePicker({ buttonText = '选择图片', label = '选择图片文件', onChange, ...props }) {
  const input = useRef(null)
  const [name, setName] = useState('')
  useEffect(() => {
    const form = input.current?.form
    const reset = () => setName('')
    form?.addEventListener('reset', reset)
    return () => form?.removeEventListener('reset', reset)
  }, [])
  return <div className={`file-picker ${props.disabled ? 'is-disabled' : ''}`}>
    <input {...props} ref={input} type="file" aria-label={label} onChange={(event) => {
      setName(Array.from(event.target.files || []).map((file) => file.name).join('、'))
      onChange?.(event)
    }} />
    <span className="file-picker-button" aria-hidden="true">{buttonText}</span>
    <span className="file-picker-name" title={name} aria-live="polite">{name || '尚未选择文件'}</span>
  </div>
}

export function AdminDialogProvider({ children }) {
  const [request, setRequest] = useState(null)
  const pending = useRef(null)
  const modal = useRef(null)
  const ask = useCallback((message, kind) => {
    if (pending.current) return Promise.resolve(null)
    return new Promise((resolve) => {
      pending.current = resolve
      setRequest({ message, kind })
    })
  }, [])
  const methods = useMemo(() => ({
    prompt: (message) => ask(message, 'prompt'),
    confirm: (message) => ask(message, 'confirm').then(Boolean),
  }), [ask])
  const settle = useCallback((value) => {
    const resolve = pending.current
    pending.current = null
    setRequest(null)
    resolve?.(value)
  }, [])
  useEffect(() => () => { pending.current?.(null) }, [])
  useEffect(() => {
    if (!request) return
    const previous = document.activeElement
    const node = modal.current
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    node.showModal?.()
    const focusTarget = node.querySelector('textarea') || node.querySelector('button')
    focusTarget?.focus()
    return () => {
      if (node.isConnected && node.open) node.close?.()
      document.body.style.overflow = overflow
      if (previous?.isConnected) previous.focus()
    }
  }, [request])
  return <AdminDialogContext.Provider value={methods}>
    {children}
    {request && <dialog className="dialog action-dialog" ref={modal} aria-labelledby="action-title"
      aria-describedby="action-message" onCancel={(event) => { event.preventDefault(); settle(null) }}>
      <form onSubmit={(event) => {
        event.preventDefault()
        settle(request.kind === 'prompt' ? new FormData(event.currentTarget).get('reason') : true)
      }}>
        <div className="dialog-head"><h3 id="action-title">{request.kind === 'prompt' ? '填写处置说明' : '确认操作'}</h3>
          <button type="button" aria-label="关闭弹窗" onClick={() => settle(null)}>×</button></div>
        <p id="action-message" className="dialog-description">{request.message}</p>
        {request.kind === 'prompt' && <label>处置说明<textarea name="reason" rows={4} /></label>}
        <div className="dialog-actions"><button type="button" className="button ghost" onClick={() => settle(null)}>取消</button>
          <button type="submit" className={`button ${request.kind === 'confirm' ? 'danger' : 'primary'}`}>确认</button></div>
      </form>
    </dialog>}
  </AdminDialogContext.Provider>
}
