// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { AppShellView } from './components/AppShell'
import { HeaderView } from './components/Header'
import { InputCard, type DownloadFlowStore } from './components/InputCard'
import { PlaylistPreview } from './components/PlaylistPreview'
import { SettingsShell, type FolderPicker } from './components/SettingsShell'
import { SinglePreview } from './components/SinglePreview'
import type { Locale } from './i18n'
import { useShellStore } from './state/shell'
import type { ShellPage } from './state/shell'
import { createDownloadFlowStore } from './state/downloadFlow'
import { createSimulatorTransport } from './transport/simulator'
import { createBrowserMockStorage, createMemoryMockStorage } from './transport/mockStorage'
import { createRuntimeTransport, usesDesktopNativeTransport } from './transport/runtime'
import { tauriTransport } from './transport/tauri'
import type { AppTransport } from './transport/types'
import { isTauri } from '@tauri-apps/api/core'
import { useStore } from 'zustand'
import { useEffect, useRef } from 'react'
import { t } from './i18n'

function runningMockStorage() {
  try {
    return typeof window === 'undefined' ? createMemoryMockStorage() : createBrowserMockStorage(window.localStorage)
  } catch {
    return createMemoryMockStorage()
  }
}

const native = usesDesktopNativeTransport(isTauri(), typeof navigator === 'undefined' ? '' : navigator.userAgent)
const simulator = native ? null : createSimulatorTransport({ storage: runningMockStorage() })
// Keep browser preview loading inspectable while native analysis runs in Rust.
const previewTransport: AppTransport | null = simulator && {
  call: async (command, args) => {
    if (command === 'analyze_url') await new Promise((resolve) => setTimeout(resolve, 900))
    return simulator.call(command, args)
  },
  on: (name, handler) => simulator.on(name, handler),
}
const appTransport = createRuntimeTransport({
  native, nativeTransport: tauriTransport,
  simulatorTransport: previewTransport,
})
const appFlowStore = createDownloadFlowStore(appTransport)

interface AppViewProps {
  locale: Locale
  page: ShellPage
  onBack: () => void
  onToggleLocale: () => void
  onOpenSettings: () => void
  flowStore?: DownloadFlowStore
  isAndroid?: boolean
  pickFolder?: FolderPicker
}

export function AppView({ locale, page, onBack, onToggleLocale, onOpenSettings, flowStore = appFlowStore,
  isAndroid, pickFolder }: AppViewProps) {
  const step = useStore(flowStore, (state) => state.step)
  const result = useStore(flowStore, (state) => state.result)
  const queueItems = useStore(flowStore, (state) => state.queueItems)
  const queueActionId = useStore(flowStore, (state) => state.queueActionId)
  const historyEntries = useStore(flowStore, (state) => state.historyEntries)
  const historyActionId = useStore(flowStore, (state) => state.historyActionId)
  const notifications = useStore(flowStore, (state) => state.notifications)
  const notificationActionId = useStore(flowStore, (state) => state.notificationActionId)
  const syncError = useStore(flowStore, (state) => state.syncError)
  const actionError = useStore(flowStore, (state) => state.actionError)
  useEffect(() => {
    return flowStore.getState().connectActivity()
  }, [flowStore])
  return (
    <>
      <HeaderView locale={locale} onToggleLocale={onToggleLocale} onOpenSettings={onOpenSettings} />
      <div hidden={page !== 'main'}>
        {syncError && (
          <div className="mx-auto w-full max-w-[86.25rem] px-shell-inline pt-card xl:px-0">
            <div role="alert" className="rounded-control border border-red-400 bg-card p-4 text-small text-red-400">
              {t(locale, 'activity.syncError')}
              <button type="button" className="ml-3 min-h-11 underline" onClick={() => { void flowStore.getState().retryActivity() }}>
                {t(locale, 'activity.retry')}
              </button>
            </div>
          </div>
        )}
        {actionError && (
          <div className="mx-auto w-full max-w-[86.25rem] px-shell-inline pt-card xl:px-0">
            <p role="alert" className="rounded-control border border-danger bg-card p-4 text-small text-danger">
              {t(locale, 'activity.actionError')}
            </p>
          </div>
        )}
        <AppShellView locale={locale} queueItems={queueItems} queueActionId={queueActionId}
          historyEntries={historyEntries} historyActionId={historyActionId}
          notifications={notifications} notificationActionId={notificationActionId}
          onPause={(id) => { void flowStore.getState().pauseQueueItem(id) }}
          onResume={(id) => { void flowStore.getState().resumeQueueItem(id) }}
          onCancel={(id) => { void flowStore.getState().cancelQueueItem(id) }}
          onRedownload={(id) => { void flowStore.getState().redownload(id) }}
          onDeleteHistory={(id) => { void flowStore.getState().deleteHistoryEntry(id) }}
          onClearHistory={() => { void flowStore.getState().clearHistory() }}
          onDismissNotification={(id) => { void flowStore.getState().dismissNotification(id) }}>
          {step === 'input' ? <InputCard locale={locale} flowStore={flowStore} /> : result?.kind === 'single' ? (
            <SinglePreview locale={locale} result={result} flowStore={flowStore} />
          ) : result?.kind === 'playlist' ? (
            <PlaylistPreview locale={locale} result={result} flowStore={flowStore} />
          ) : null}
        </AppShellView>
      </div>
      {page === 'settings' && <SettingsShell locale={locale} onBack={onBack} flowStore={flowStore}
        onChangeLanguage={(language) => { if (language !== locale) onToggleLocale() }}
        isAndroid={isAndroid} pickFolder={pickFolder} />}
    </>
  )
}

export default function App() {
  const locale = useShellStore((state) => state.locale)
  const page = useShellStore((state) => state.page)
  const closeSettings = useShellStore((state) => state.closeSettings)
  const toggleLocale = useShellStore((state) => state.toggleLocale)
  const setLocale = useShellStore((state) => state.setLocale)
  const openSettings = useShellStore((state) => state.openSettings)
  const settings = useStore(appFlowStore, (state) => state.settings)
  const initialSettingsApplied = useRef(false)

  useEffect(() => {
    if (settings && !initialSettingsApplied.current) {
      initialSettingsApplied.current = true
      setLocale(settings.language)
    }
  }, [settings, setLocale])

  function changeLocale() {
    const previous = useShellStore.getState().locale
    const language = previous === 'en' ? 'es' : 'en'
    initialSettingsApplied.current = true
    toggleLocale()
    void appFlowStore.getState().saveSettings({ language }).then((saved) => {
      if (!saved && useShellStore.getState().locale === language) setLocale(previous)
    })
  }

  function returnToMain() {
    closeSettings()
    // The header stays mounted while Settings is open, so focus can return to its trigger.
    document.querySelector<HTMLButtonElement>('header button:last-of-type')?.focus()
  }

  return (
    <AppView
      locale={locale}
      page={page}
      onBack={returnToMain}
      onToggleLocale={changeLocale}
      onOpenSettings={openSettings}
    />
  )
}
