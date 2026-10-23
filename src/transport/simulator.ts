// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AnalyzeResult, AppError, Commands } from '../../shared/contract'
import { analysisUrls, offlineAnalysisScenarios, type AnalysisScenario } from './fixtures'
import type { AppTransport } from './types'

const youtubeHosts = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com'])

function syntheticError(code: AppError['code'], detail: string): AppError {
  return { code, detail: `Synthetic offline scenario: ${detail}` }
}

function scenarioFor(input: string): AnalysisScenario {
  if (input === offlineAnalysisScenarios.invalid.url) return offlineAnalysisScenarios.invalid

  let parsed: URL
  try {
    parsed = new URL(input)
  } catch {
    return { type: 'error', url: input, error: syntheticError('invalid_url', 'Invalid URL.') }
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return { type: 'error', url: input, error: syntheticError('invalid_url', 'Expected an HTTP(S) URL.') }
  }

  if (youtubeHosts.has(parsed.hostname)) {
    // A watch URL remains one video even when it also carries a list parameter.
    if (parsed.pathname === '/watch') {
      const id = parsed.searchParams.get('v')
      if (id === 'uW13KuRrg1g') return offlineAnalysisScenarios.single
      if (id === 'u9lj-c29dxI') return offlineAnalysisScenarios.mixed
    }
    if (parsed.pathname === '/playlist' && parsed.searchParams.get('list') === 'PL6B3937A5D230E335') {
      return offlineAnalysisScenarios.playlist
    }
    return {
      type: 'error',
      url: input,
      error: syntheticError('not_found', 'No saved YouTube analysis matches this URL.'),
    }
  }

  if (parsed.hostname === 'archive.org') {
    if (parsed.pathname === '/details/zownload-fixture-intentionally-missing-0b02') {
      return offlineAnalysisScenarios.notFound
    }
    if (parsed.pathname === new URL(analysisUrls.restricted).pathname) {
      return offlineAnalysisScenarios.restricted
    }
    return {
      type: 'error',
      url: input,
      error: syntheticError('not_found', 'No saved Archive analysis matches this URL.'),
    }
  }

  if (input === offlineAnalysisScenarios.unsupported.url) return offlineAnalysisScenarios.unsupported
  return {
    type: 'error',
    url: input,
    error: syntheticError('unsupported_site', `No offline extractor for ${parsed.hostname}.`),
  }
}

function copyResult(result: AnalyzeResult, url: string): AnalyzeResult {
  if (result.kind === 'playlist') {
    return { ...result, url, itemTitles: [...result.itemTitles] }
  }
  return {
    ...result,
    url,
    videoHeights: [...result.videoHeights],
    audioOutputBitrates: [...result.audioOutputBitrates],
  }
}

/** In-memory analysis only. Later tasks add queue commands and event delivery. */
export function createSimulatorTransport(): AppTransport {
  return {
    async call<K extends keyof Commands>(command: K, args: Commands[K]['args']): Promise<Commands[K]['result']> {
      if (command !== 'analyze_url') {
        throw syntheticError('unknown', `Simulator command ${command} is not implemented yet.`)
      }

      const url = (args as Commands['analyze_url']['args']).url.trim()
      const scenario = scenarioFor(url)
      if (scenario.type === 'error') throw { ...scenario.error }
      return copyResult(scenario.result, url) as Commands[K]['result']
    },
    async on() {
      // Analysis emits no events. 1B-05 adds subscriptions with queue snapshots.
      return () => {}
    },
  }
}
