import { createContext, useContext } from 'react'

export const AdminDialogContext = createContext(null)

export function useAdminDialog() {
  const value = useContext(AdminDialogContext)
  if (!value) throw new Error('AdminDialogProvider is required')
  return value
}
