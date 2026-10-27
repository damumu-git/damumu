import icons from './navigation-icons.json'

export default function AdminNavIcon({ name, size = 20 }) {
  return <svg className="admin-nav-icon" width={size} height={size} viewBox="0 0 24 24"
    fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"
    aria-hidden="true" focusable="false">
    {(icons[name] || icons.dashboard).map((path, index) => <path key={index} d={path} />)}
  </svg>
}
