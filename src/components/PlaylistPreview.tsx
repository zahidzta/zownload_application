// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useId } from 'react'
import { useStore } from 'zustand'
import type { AnalyzeResult, Quality } from '../../shared/contract'
import { t, type Locale } from '../i18n'
import type { DownloadFlowStore } from './InputCard'

type PlaylistResult = Extract<AnalyzeResult, { kind: 'playlist' }>

interface PlaylistPreviewProps {
  locale: Locale
  result: PlaylistResult
  flowStore: DownloadFlowStore
}

export function PlaylistPreview({ locale, result, flowStore }: PlaylistPreviewProps) {
  const { format, selectedQuality, enqueuing, selectQuality, back, enqueue } = useStore(flowStore)
  const titleId = useId()
  const qualityId = useId()
  const listId = useId()
  const listHeadingId = useId()
  const countLabel = `${result.itemCount} ${t(locale, 'download.itemCount')}`

  return (
    <>
      <button type="button" onClick={back} disabled={enqueuing}
        className="-mt-3 mb-1 inline-flex min-h-11 items-center gap-2 text-body text-text hover:text-text-strong disabled:opacity-50 lg:-mt-2 lg:mb-2">
        <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5 fill-none stroke-current stroke-2">
          <path d="m12 5-7 7 7 7M5 12h14" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {t(locale, 'download.back')}
      </button>
      <section aria-labelledby={titleId} className="min-w-0 rounded-card border border-border bg-card p-5 lg:p-7">
        <div className="grid min-w-0 gap-6 lg:grid-cols-2 lg:gap-8">
          <div className="min-w-0 rounded-card border border-border bg-field p-5 text-center">
            {result.thumbnail ? (
              <img src={result.thumbnail} alt="" className="aspect-square w-full rounded-control bg-canvas object-contain" />
            ) : (
              <div role="img" aria-label={t(locale, 'download.thumbnailUnavailable')}
                className="flex aspect-square w-full items-center justify-center rounded-control bg-canvas p-4 text-small text-text-muted">
                {t(locale, 'download.thumbnailUnavailable')}
              </div>
            )}
            <p className="mt-4 mb-0 min-w-0 truncate text-body font-semibold text-text-strong">{result.title}</p>
            <p className="mt-1 mb-0 min-w-0 truncate text-small text-text">{result.author}</p>
            <p className="mt-1 mb-0 text-small uppercase text-text-muted">{countLabel}</p>
          </div>
          <div className="flex min-w-0 flex-col">
            <h2 id={titleId} className="min-w-0 wrap-break-word text-[1.75rem] leading-tight font-semibold text-text-strong lg:text-[2.25rem]">{result.title}</h2>
            <p className="mt-2 mb-0 min-w-0 wrap-break-word text-body text-text lg:text-[1.25rem]">{result.author}</p>
            <div className="mt-5 grid grid-cols-2 gap-3 lg:mt-7">
              <div className="min-w-0 rounded-control border border-border bg-field p-3 lg:p-4">
                <span className="block text-small text-text-muted">{t(locale, 'download.itemCount')}</span>
                <strong className="mt-1 block text-body font-medium text-text-strong">{result.itemCount}</strong>
              </div>
              <div className="min-w-0 rounded-control border border-border bg-field p-3 lg:p-4">
                <span className="block text-small text-text-muted">{t(locale, 'input.formatLabel')}</span>
                <strong className="mt-1 block text-body font-medium text-text-strong">{format.toUpperCase()}</strong>
              </div>
            </div>
            <p className="mt-3 mb-0 min-w-0 wrap-break-word text-small text-text" aria-label={`${t(locale, 'download.site')}: ${result.site}`}>
              {result.site}
            </p>
            <div className="mt-7 lg:mt-auto lg:pt-8">
              <label htmlFor={qualityId} className="mb-2 block text-small font-medium text-text">{t(locale, 'download.quality')}</label>
              <div className="relative">
                <select id={qualityId} value={selectedQuality?.type === 'min' ? 'min' : 'max'}
                  onChange={(event) => selectQuality({ type: event.target.value } as Quality)}
                  disabled={enqueuing}
                  className="min-h-11 w-full appearance-none rounded-control border border-border bg-field px-4 pr-10 text-body text-text-strong lg:min-h-12">
                  <option value="max">{t(locale, 'download.maxQuality')}</option>
                  <option value="min">{t(locale, 'download.minQuality')}</option>
                </select>
                <svg aria-hidden="true" viewBox="0 0 24 24" className="pointer-events-none absolute top-1/2 right-3 size-5 -translate-y-1/2 fill-none stroke-current stroke-2 text-text-strong">
                  <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
              <button type="button" onClick={() => { void enqueue() }} disabled={enqueuing || !selectedQuality}
                className="mt-5 inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-control bg-primary px-4 text-body font-semibold text-white disabled:cursor-not-allowed disabled:bg-primary-disabled disabled:text-text-muted lg:min-h-12">
                <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5 fill-none stroke-current stroke-2">
                  <path d="M12 3v12m0 0 4-4m-4 4-4-4M4 16v4h16v-4" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                {t(locale, enqueuing ? 'download.enqueuing' : 'download.download')}
              </button>
            </div>
          </div>
        </div>
      </section>
      <div className="mt-6 min-w-0 rounded-card border border-border bg-card p-5 lg:p-7">
        <h2 id={listHeadingId} className="text-small font-medium uppercase text-text">{t(locale, 'download.itemsInList')}</h2>
        <div role="region" aria-labelledby={listHeadingId} aria-describedby={listId} tabIndex={0}
          className="mt-4 max-h-[22rem] overflow-y-auto overscroll-contain rounded-control focus-visible:outline-3 lg:max-h-[26rem]">
          <p id={listId} className="sr-only">{countLabel}</p>
          <ol className="m-0 list-decimal space-y-1 pl-8 text-body marker:text-text-muted">
            {result.itemTitles.map((title, index) => (
              <li key={index} className="min-w-0 wrap-break-word py-2 pl-2 text-text-strong">{title}</li>
            ))}
          </ol>
        </div>
      </div>
    </>
  )
}
