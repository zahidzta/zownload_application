// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AnalyzeResult, AppError } from '../../shared/contract'

/** Gate 0B inputs. The simulator uses their saved observations, never the live sites. */
export const analysisUrls = {
  single: 'https://www.youtube.com/watch?v=uW13KuRrg1g',
  playlist: 'https://www.youtube.com/playlist?list=PL6B3937A5D230E335',
  mixed: 'https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335',
  invalid: 'not-a-url',
  unsupported: 'https://example.com/zownload-unsupported',
  notFound: 'https://archive.org/details/zownload-fixture-intentionally-missing-0b02',
  restricted:
    'https://archive.org/download/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik/disc1/01.01.%20Bells%20Of%20Rostov.mp3',
} as const

export type AnalysisScenario =
  | { type: 'result'; url: string; result: AnalyzeResult }
  | { type: 'error'; url: string; error: AppError }

/** Small inline SVGs keep the previews offline and avoid bundling borrowed artwork. */
function mockThumbnail(label: string, color: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180" viewBox="0 0 320 180"><rect width="320" height="180" fill="${color}"/><circle cx="160" cy="90" r="32" fill="#ffffff" fill-opacity=".2"/><path d="m151 72 28 18-28 18z" fill="#ffffff"/><text x="160" y="151" fill="#ffffff" text-anchor="middle" font-family="sans-serif" font-size="17">${label}</text></svg>`
  return `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`
}

/** Metadata below is from the saved 0B-13 JSON, apart from inline mock images. */
export const offlineAnalysisScenarios = {
  single: {
    type: 'result',
    url: analysisUrls.single,
    result: {
      kind: 'single',
      url: analysisUrls.single,
      title: '10號風...',
      author: 'vgocyl',
      thumbnail: mockThumbnail('Single video', '#34475d'),
      durationSec: 15,
      site: 'YouTube',
      videoHeights: [720, 360, 144],
      audioOutputBitrates: [320, 256, 192, 128],
    },
  },
  playlist: {
    type: 'result',
    url: analysisUrls.playlist,
    result: {
      kind: 'playlist',
      url: analysisUrls.playlist,
      title: 'Official Blender Open Movies',
      author: 'Blender',
      thumbnail: mockThumbnail('Blender playlist', '#43506c'),
      site: 'YouTube',
      itemCount: 17,
      itemTitles: [
        'SINGULARITY - Painterly Space Adventure',
        'WING IT! - Blender Open Movie',
        'CHARGE - Blender Open Movie',
        'Sprite Fright - Blender Open Movie',
        'Coffee Run - Blender Open Movie',
        'Spring - Blender Open Movie',
        'HERO – Blender Grease Pencil Showcase',
        'The Daily Dweebs - 8K UHD Stereoscopic 3D',
        'Agent 327: Operation Barbershop',
        'Caminandes 3: Llamigos',
        'Glass Half - Blender animated cartoon',
        'Cosmos Laundromat - First Cycle. Official Blender Foundation release.',
        '"Caminandes 2: Gran Dillama" - Blender Animated Short',
        'Tears of Steel - Blender VFX Open Movie',
        'Sintel - Open Movie by Blender Foundation',
        'Big Buck Bunny',
        'Elephants Dream',
      ],
    },
  },
  mixed: {
    type: 'result',
    url: analysisUrls.mixed,
    result: {
      kind: 'single',
      url: analysisUrls.mixed,
      title: 'WING IT! - Blender Open Movie',
      author: 'Blender Studio',
      thumbnail: mockThumbnail('Mixed watch URL', '#4d5269'),
      durationSec: 238,
      site: 'YouTube',
      videoHeights: [1080, 720, 480, 360, 240, 144],
      audioOutputBitrates: [320, 256, 192, 128],
    },
  },
  invalid: {
    type: 'error',
    url: analysisUrls.invalid,
    error: {
      code: 'invalid_url',
      detail: "ERROR: [generic] 'not-a-url' is not a valid URL",
    },
  },
  unsupported: {
    type: 'error',
    url: analysisUrls.unsupported,
    error: {
      code: 'unsupported_site',
      detail: 'Synthetic offline scenario: example.com has no supported extractor.',
    },
  },
  notFound: {
    type: 'error',
    url: analysisUrls.notFound,
    error: {
      code: 'not_found',
      detail:
        'ERROR: [archive.org] zownload-fixture-intentionally-missing-0b02: Unable to download webpage: HTTP Error 404: Not Found (caused by <HTTPError 404: Not Found>)',
    },
  },
  restricted: {
    type: 'error',
    url: analysisUrls.restricted,
    error: {
      code: 'private_or_restricted',
      detail:
        'ERROR: [generic] 01.01. Bells Of Rostov: Unable to download webpage: HTTP Error 401: Unauthorized (caused by <HTTPError 401: Unauthorized>)',
    },
  },
} satisfies Record<keyof typeof analysisUrls, AnalysisScenario>
