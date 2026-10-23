// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useId } from 'react'
import { useStore } from 'zustand'
import type { AnalyzeResult, Format, Quality } from '../../shared/contract'
import { t, type Locale } from '../i18n'
import type { DownloadFlowStore } from './InputCard'

type SingleResult = Extract<AnalyzeResult, { kind: 'single' }>

interface SinglePreviewProps {
  locale: Locale
  result: SingleResult
  flowStore: DownloadFlowStore
}

function durationLabel(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds))
  const minutes = Math.floor(total / 60)
  const remainder = String(total % 60).padStart(2, '0')
  return `${minutes}:${remainder}`
}

function estimatedSize(result: SingleResult, format: Format, quality: Quality, locale: Locale): string | null {
  const match = result.estimates?.find((estimate) =>
    estimate.format === format && estimate.quality.type === quality.type &&
    (estimate.quality.type === 'audio' && quality.type === 'audio'
      ? estimate.quality.bitrate === quality.bitrate
      : estimate.quality.type === 'video' && quality.type === 'video' && estimate.quality.height === quality.height),
  )
  if (!match || !Number.isFinite(match.estimatedBytes) || match.estimatedBytes <= 0) return null
  const amount = new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 })
    .format(match.estimatedBytes / 1_000_000)
  return `~${amount} MB`
}

export function SinglePreview({ locale, result, flowStore }: SinglePreviewProps) {
  const { format, selectedQuality, enqueuing, selectQuality, back, enqueue } = useStore(flowStore)
  const titleId = useId()
  const qualityId = useId()
  const qualities: Quality[] = format === 'mp3'
    ? result.audioOutputBitrates.map((bitrate) => ({ type: 'audio', bitrate }))
    : result.videoHeights.map((height) => ({ type: 'video', height }))
  const selectedValue = selectedQuality?.type === 'audio' ? String(selectedQuality.bitrate)
    : selectedQuality?.type === 'video' ? String(selectedQuality.height) : ''

  return (
    <>
      <button
        type="button"
        onClick={back}
        disabled={enqueuing}
        className="-mt-3 mb-1 inline-flex min-h-11 items-center gap-2 text-body text-text hover:text-text-strong disabled:opacity-50 lg:-mt-2 lg:mb-2"
      >
        <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5 fill-none stroke-current stroke-2">
          <path d="m12 5-7 7 7 7M5 12h14" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {t(locale, 'download.back')}
      </button>
      <section aria-labelledby={titleId} className="min-w-0 overflow-hidden rounded-card border border-border bg-field">
        <div className="flex min-w-0 gap-5 p-5 lg:gap-6 lg:p-6">
          {result.thumbnail ? (
            <img src={result.thumbnail} alt="" className="size-[5.75rem] shrink-0 rounded-control bg-canvas object-cover lg:size-[7.5rem]" />
          ) : (
            <div role="img" aria-label={t(locale, 'download.thumbnailUnavailable')}
              className="flex size-[5.75rem] shrink-0 items-center justify-center rounded-control bg-canvas p-2 text-center text-small text-text-muted lg:size-[7.5rem]">
              {t(locale, 'download.thumbnailUnavailable')}
            </div>
          )}
          <div className="min-w-0 flex-1">
            <h2 id={titleId} className="min-w-0 wrap-break-word text-[1.375rem] leading-tight font-semibold text-text-strong lg:text-[1.875rem]">{result.title}</h2>
            <p className="mt-1 mb-2 min-w-0 wrap-break-word text-small text-text lg:mt-3 lg:mb-3 lg:text-body">{result.author}</p>
            <div className="flex min-w-0 flex-wrap gap-2">
              <span className="inline-flex min-h-7 items-center gap-1.5 rounded-full bg-border px-2.5 text-small text-text-strong"
                aria-label={`${t(locale, 'download.duration')}: ${durationLabel(result.durationSec)}`}>
                <svg aria-hidden="true" viewBox="0 0 24 24" className="size-4 fill-none stroke-current stroke-[1.7]">
                  <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" strokeLinecap="round" />
                </svg>
                {durationLabel(result.durationSec)}
              </span>
              <span className="inline-flex min-h-7 min-w-0 items-center gap-1.5 rounded-full bg-border px-2.5 text-small text-text-strong"
                aria-label={`${t(locale, 'download.site')}: ${result.site}`}>
                {result.site}
              </span>
            </div>
          </div>
        </div>
        <div className="flex min-w-0 flex-col gap-2 border-t border-border px-5 py-4 lg:flex-row lg:items-end lg:justify-between lg:gap-4 lg:p-6">
          <div className="min-w-0 lg:w-[20rem] lg:max-w-[calc(100%-12rem)]">
            <label htmlFor={qualityId} className="mb-2 block text-small font-medium text-text">
              {t(locale, 'download.quality')}
              {format === 'mp3' && <span className="ml-2 font-normal text-text-muted">({t(locale, 'download.requestedMaximum')})</span>}
            </label>
            <div className="relative">
              <select
                id={qualityId}
                value={selectedValue}
                onChange={(event) => {
                  const number = Number(event.target.value)
                  selectQuality(format === 'mp3' ? { type: 'audio', bitrate: number } : { type: 'video', height: number })
                }}
                disabled={enqueuing || qualities.length === 0}
                className="min-h-11 w-full min-w-0 appearance-none rounded-control border border-border bg-field px-4 pr-10 text-body text-text-strong disabled:opacity-50 lg:min-h-12"
              >
                {qualities.length === 0 && <option value="">{t(locale, 'download.quality')}</option>}
                {qualities.map((quality) => {
                  const value = quality.type === 'audio' ? quality.bitrate : quality.type === 'video' ? quality.height : 0
                  const size = estimatedSize(result, format, quality, locale)
                  const label = quality.type === 'audio' ? `${value} kbps · MP3` : `${value}p · MP4`
                  return <option key={value} value={value}>{label}{size ? ` · ${size}` : ''}</option>
                })}
              </select>
              <svg aria-hidden="true" viewBox="0 0 24 24" className="pointer-events-none absolute top-1/2 right-3 size-5 -translate-y-1/2 fill-none stroke-current stroke-2 text-text-strong">
                <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
          </div>
          <button
            type="button"
            onClick={() => { void enqueue() }}
            disabled={enqueuing || !selectedQuality}
            className="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-control bg-primary px-4 text-body font-semibold text-white disabled:cursor-not-allowed disabled:bg-primary-disabled disabled:text-text-muted lg:min-h-12 lg:w-fit lg:min-w-[10.75rem] lg:px-5"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5 fill-none stroke-current stroke-2">
              <path d="M12 3v12m0 0 4-4m-4 4-4-4M4 16v4h16v-4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            {t(locale, enqueuing ? 'download.enqueuing' : 'download.download')}
          </button>
        </div>
      </section>
    </>
  )
}
