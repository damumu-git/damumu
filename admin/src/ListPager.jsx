import { useState } from 'react'

const controls = [
  ['首页', 'M4 3v10m8-10L7 8l5 5'],
  ['上一页', 'm10 3-5 5 5 5'],
  ['下一页', 'm6 3 5 5-5 5'],
]

export function ListPager({ page, total, size, onPage, loading }) {
  const pages = Math.max(1, Math.ceil(total / size))
  if (!total && page === 1) return null
  const button = (index, target, disabled) => {
    const [label, path] = controls[index]
    return <button type="button" title={label} aria-label={label} disabled={loading || disabled} onClick={() => onPage(target)}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d={path} /></svg>
    </button>
  }
  return <nav className="grid-pager" aria-label="列表分页">
    <span className="grid-pager-count" aria-live="polite">共 {total} 条</span>
    <div className="grid-pager-controls">
      {button(0, 1, page === 1)}{button(1, page - 1, page === 1)}
      <span className="grid-pager-current" aria-current="page">{page} / {pages}</span>
      {button(2, page + 1, page >= pages)}
    </div>
  </nav>
}

export function PagedItems({ items, size = 20, children }) {
  const [current, setPage] = useState(1)
  const page = Math.min(current, Math.max(1, Math.ceil(items.length / size)))
  return <>
    {children(items.slice((page - 1) * size, page * size))}
    {items.length > size && <ListPager page={page} size={size} total={items.length} onPage={setPage} />}
  </>
}
