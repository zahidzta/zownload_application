// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useEffect, useRef, useState } from 'react'
import { useStore } from 'zustand'
import type { Locale } from '../i18n'
import { t } from '../i18n'
import type { DownloadFlowStore } from './InputCard'
import { Button, IconButton } from './ui/Button'
import { Card } from './ui/Card'
import { Page } from './ui/Page'

export type FolderPicker = () => Promise<string | null>

// A browser preview may render Settings without calling the native plugin.
async function pickDesktopFolder(): Promise<string | null> {
  const { open } = await import('@tauri-apps/plugin-dialog')
  return open({ directory: true, multiple: false })
}

interface SettingsShellProps {
  locale: Locale
  onBack: () => void
  onChangeLanguage: (locale: Locale) => void
  flowStore: DownloadFlowStore
  isAndroid?: boolean
  pickFolder?: FolderPicker
}

const fieldClass = 'min-h-11 rounded-control border border-border bg-field px-3 text-text-strong'
const actionClass = 'rounded-control border border-border px-stack text-accent-text'

export function SettingsShell({ locale, onBack, onChangeLanguage, flowStore,
  isAndroid = /Android/i.test(typeof navigator === 'undefined' ? '' : navigator.userAgent),
  pickFolder = pickDesktopFolder }: SettingsShellProps) {
  const backButton = useRef<HTMLButtonElement>(null)
  const settings = useStore(flowStore, (state) => state.settings)
  const engineInfo = useStore(flowStore, (state) => state.engineInfo)
  const engineBusy = useStore(flowStore, (state) => state.engineBusy)
  const engineError = useStore(flowStore, (state) => state.engineError)
  const actionError = useStore(flowStore, (state) => state.actionError)
  const [picking, setPicking] = useState(false)
  const [pickerError, setPickerError] = useState(false)

  useEffect(() => { backButton.current?.focus() }, [])

  async function selectFolder() {
    if (picking || isAndroid || !settings) return
    setPickerError(false)
    setPicking(true)
    try {
      const path = await pickFolder()
      if (path !== null) await flowStore.getState().saveSettings({ downloadDir: path })
    } catch {
      setPickerError(true)
    } finally {
      setPicking(false)
    }
  }

  return (
    <Page title={t(locale, 'settings.title')} headingClassName="sr-only"
      className="mx-auto w-full max-w-[86.25rem] px-shell-inline pt-card pb-shell lg:pt-shell xl:px-0">
      <Card title={t(locale, 'settings.title')}
        className="mx-auto grid w-full max-w-[42rem] grid-cols-[2.75rem_minmax(0,1fr)] items-center gap-x-2 rounded-card border border-border bg-card p-4 lg:p-card"
        headingClassName="col-start-2 row-start-1 text-card-title font-medium text-text-strong">
        <IconButton ref={backButton} label={t(locale, 'navigation.back')} onClick={onBack}
          icon={<svg viewBox="0 0 24 24" className="size-5 fill-none stroke-current stroke-2">
            <path d="m12 5-7 7 7 7M5 12h14" strokeLinecap="round" strokeLinejoin="round" />
          </svg>}
          className="col-start-1 row-start-1 rounded-control text-text hover:text-text-strong" />
        <div className="col-span-2 mt-section space-y-section border-t border-border pt-section">
          {actionError && <p role="alert" className="text-small text-danger">{t(locale, 'activity.actionError')}</p>}
          <div className="flex flex-col gap-compact">
            <label htmlFor="settings-language" className="font-medium text-text-strong">{t(locale, 'settings.language')}</label>
            <select id="settings-language" className={fieldClass} value={settings?.language ?? locale}
              disabled={!settings} onChange={(event) => { onChangeLanguage(event.target.value as Locale) }}>
              <option value="en">{t(locale, 'header.english')}</option>
              <option value="es">{t(locale, 'header.spanish')}</option>
            </select>
          </div>
          <label className="flex min-h-11 items-center gap-stack text-text-strong">
            <input type="checkbox" checked={settings?.zipPlaylists ?? false} disabled={!settings}
              onChange={(event) => { void flowStore.getState().saveSettings({ zipPlaylists: event.target.checked }) }}
              className="h-5 w-5 shrink-0 accent-primary" />
            <span>{t(locale, 'settings.zipPlaylists')}</span>
          </label>
          {!isAndroid && <section aria-labelledby="settings-folder-heading" className="space-y-compact">
            <h3 id="settings-folder-heading" className="font-medium text-text-strong">{t(locale, 'settings.downloadFolder')}</h3>
            <p className="break-all text-small" aria-live="polite">{settings?.downloadDir ?? t(locale, 'settings.systemDownloads')}</p>
            <div className="flex flex-wrap gap-compact">
              <Button label={picking ? t(locale, 'settings.choosingFolder') : t(locale, 'settings.chooseFolder')}
                disabled={!settings || picking} onClick={() => { void selectFolder() }} className={actionClass} />
              {settings?.downloadDir && <Button label={t(locale, 'settings.useSystemDownloads')}
                disabled={picking} onClick={() => { void flowStore.getState().saveSettings({ downloadDir: null }) }} className={actionClass} />}
            </div>
            {pickerError && <p role="alert" className="text-small text-danger">{t(locale, 'settings.folderError')}</p>}
          </section>}
          <section aria-labelledby="settings-engine-heading" className="space-y-compact border-t border-border pt-section">
            <h3 id="settings-engine-heading" className="font-medium text-text-strong">{t(locale, 'settings.engineTitle')}</h3>
            <p className="text-small">{t(locale, 'settings.engineDescription')}</p>
            <div className="flex flex-wrap gap-compact">
              <Button label={engineBusy === 'checking' ? t(locale, 'settings.checking') : t(locale, 'settings.checkEngine')}
                disabled={engineBusy !== null} onClick={() => { void flowStore.getState().checkEngineUpdate() }} className={actionClass} />
              <Button label={engineBusy === 'updating' ? t(locale, 'settings.updating') : t(locale, 'settings.updateEngine')}
                disabled={engineBusy !== null} onClick={() => { void flowStore.getState().updateEngine() }} className={actionClass} />
            </div>
            {engineInfo && <p role="status" className="text-small">{t(locale, engineInfo.updateAvailable ? 'settings.engineAvailable' : 'settings.engineCurrent')}
              {' '}{engineInfo.current}{engineInfo.updateAvailable ? ` → ${engineInfo.latest}` : ''}</p>}
            {engineError && <p role="alert" className="text-small text-danger">{t(locale, `errors.${engineError.code}`)}</p>}
          </section>
          <section aria-labelledby="settings-app-heading" className="space-y-compact border-t border-border pt-section">
            <h3 id="settings-app-heading" className="font-medium text-text-strong">{t(locale, 'settings.appUpdates')}</h3>
            <p className="text-small">{t(locale, 'settings.appUpdatesDescription')}</p>
          </section>
          <section aria-labelledby="settings-developer-heading" className="space-y-compact border-t border-border pt-section">
            <h3 id="settings-developer-heading" className="font-medium text-text-strong">{t(locale, 'settings.developer')}</h3>
            <p className="text-small">{t(locale, 'settings.developerPlaceholder')}</p>
          </section>
        </div>
      </Card>
    </Page>
  )
}
