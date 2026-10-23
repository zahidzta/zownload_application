// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { afterEach, expect, test, vi } from 'vitest'
import { analysisUrls } from '../../src/transport/fixtures'
import { createSimulatorTransport } from '../../src/transport/simulator'

afterEach(() => vi.unstubAllGlobals())

test('observed short video has contract-shaped metadata and an inline thumbnail', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)

  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.single })

  expect(result).toMatchObject({
    kind: 'single',
    url: analysisUrls.single,
    title: '10號風...',
    author: 'vgocyl',
    durationSec: 15,
    site: 'YouTube',
    videoHeights: [720, 360, 144],
    audioOutputBitrates: [320, 256, 192, 128],
  })
  expect(result.thumbnail).toMatch(/^data:image\/svg\+xml/)
  expect(result).not.toHaveProperty('estimates')
  expect(fetchSpy).not.toHaveBeenCalled()
})

test('pure playlist exposes all 17 observed titles without a remote image', async () => {
  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.playlist })

  expect(result.kind).toBe('playlist')
  if (result.kind !== 'playlist') throw new Error('Expected playlist')
  expect(result.itemCount).toBe(17)
  expect(result.itemTitles).toHaveLength(result.itemCount)
  expect(result.itemTitles).toContain('WING IT! - Blender Open Movie')
  expect(result.itemTitles).toContain('CHARGE - Blender Open Movie')
  expect(result.itemTitles.at(-1)).toBe('Elephants Dream')
  expect(result.thumbnail).toMatch(/^data:image\/svg\+xml/)
})

test('watch plus list resolves to its single video even when query order changes', async () => {
  const url = 'https://www.youtube.com/watch?list=PL6B3937A5D230E335&v=u9lj-c29dxI'
  const result = await createSimulatorTransport().call('analyze_url', { url })

  expect(result).toMatchObject({
    kind: 'single',
    url,
    title: 'WING IT! - Blender Open Movie',
    durationSec: 238,
    videoHeights: [1080, 720, 480, 360, 240, 144],
  })
})

test.each([
  [analysisUrls.invalid, 'invalid_url', "ERROR: [generic] 'not-a-url' is not a valid URL"],
  [analysisUrls.unsupported, 'unsupported_site', 'Synthetic offline scenario:'],
  [analysisUrls.notFound, 'not_found', 'HTTP Error 404: Not Found'],
  [analysisUrls.restricted, 'private_or_restricted', 'HTTP Error 401: Unauthorized'],
])('%s rejects with %s and diagnostic detail', async (url, code, detail) => {
  await expect(createSimulatorTransport().call('analyze_url', { url })).rejects.toMatchObject({
    code,
    detail: expect.stringContaining(detail),
  })
})

test('unknown inputs stay typed, and a caller cannot mutate stored fixture arrays', async () => {
  const transport = createSimulatorTransport()
  await expect(transport.call('analyze_url', { url: 'not another URL' })).rejects.toMatchObject({
    code: 'invalid_url',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })
  await expect(transport.call('analyze_url', { url: 'https://www.youtube.com/watch?v=other' })).rejects.toMatchObject({
    code: 'not_found',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })

  const first = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (first.kind !== 'playlist') throw new Error('Expected playlist')
  first.itemTitles[0] = 'Changed by caller'
  const second = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (second.kind !== 'playlist') throw new Error('Expected playlist')
  expect(second.itemTitles[0]).toBe('SINGULARITY - Painterly Space Adventure')
})
