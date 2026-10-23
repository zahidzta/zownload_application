// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useId } from 'react'
import { useStore } from 'zustand'
import type { Format } from '../../shared/contract'
import { t, type Locale } from '../i18n'
import type { createDownloadFlowStore } from '../state/downloadFlow'
import { Card } from './ui/Card'

export type DownloadFlowStore = ReturnType<typeof createDownloadFlowStore>

interface InputCardProps {
  locale: Locale
  flowStore: DownloadFlowStore
}

export function InputCard({ locale, flowStore }: InputCardProps) {
  const { url, format, analyzing, error, setUrl, setFormat, analyze } = useStore(flowStore)
  const id = useId()
  const urlId = `${id}-url`
  const errorId = `${id}-error`

  return (
    <Card
      title={t(locale, 'input.title')}
      className="min-h-[16.25rem] rounded-card border border-border bg-card p-6 lg:min-h-[21.3125rem] lg:p-card"
      headingClassName="sr-only"
    >
      <form noValidate onSubmit={(event) => { event.preventDefault(); void analyze() }}>
        <label htmlFor={urlId} className="block text-small text-text lg:text-body">
          {t(locale, 'input.urlLabel')}
        </label>
        <input
          id={urlId}
          name="url"
          type="url"
          inputMode="url"
          autoComplete="url"
          spellCheck={false}
          value={url}
          onChange={(event) => setUrl(event.target.value)}
          placeholder={t(locale, 'input.urlPlaceholder')}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? errorId : undefined}
          className="mt-2 block min-h-11 w-full min-w-0 rounded-control border border-border bg-field px-4 text-body text-text-strong placeholder:text-text-muted lg:min-h-14 lg:px-5"
        />
        {error && (
          <p id={errorId} role="alert" className="mt-2 mb-0 text-small text-red-400">
            {t(locale, `errors.${error.code}`)}
          </p>
        )}

        <fieldset className="mt-5 min-w-0 border-0 p-0 lg:mt-6">
          <legend className="mb-2 text-small uppercase text-text lg:text-body">
            {t(locale, 'input.formatLabel')}
          </legend>
          <div className="grid grid-cols-2 gap-control-gap">
            {(['mp3', 'mp4'] as const satisfies readonly Format[]).map((choice) => (
              <label
                key={choice}
                className="flex min-h-11 cursor-pointer items-center justify-center rounded-control border border-border text-center text-small font-medium text-text has-checked:border-selection-border has-checked:bg-selection has-checked:text-accent-text has-[:focus-visible]:outline-3 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-focus lg:min-h-12 lg:text-body"
              >
                <input
                  className="sr-only"
                  type="radio"
                  name={`${id}-format`}
                  value={choice}
                  checked={format === choice}
                  onChange={() => setFormat(choice)}
                />
                {t(locale, `input.${choice}`)}
              </label>
            ))}
          </div>
        </fieldset>

        <button
          type="submit"
          disabled={analyzing}
          className="mt-5 flex min-h-11 w-full items-center justify-center gap-2 rounded-control bg-primary px-4 text-body font-semibold text-white disabled:cursor-wait disabled:bg-primary-disabled disabled:text-text-muted lg:mt-6 lg:min-h-14"
        >
          {analyzing && <span aria-hidden="true" className="size-5 animate-spin rounded-full border-[3px] border-text-muted/40 border-t-text-muted" />}
          {t(locale, analyzing ? 'input.analyzing' : 'input.convert')}
        </button>
      </form>
    </Card>
  )
}
