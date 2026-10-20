// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
import { useState, type FormEvent } from 'react'
import { call, type QueueItem } from '../shared/contract'

export default function App() {
  const [url, setUrl] = useState('')
  const [queue, setQueue] = useState<QueueItem[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('Check the Rust queue before starting.')
  const [lastId, setLastId] = useState<string | null>(null)

  async function refreshQueue() {
    setBusy(true)
    try {
      const items = await call('get_queue', {})
      setQueue(items)
      setMessage(items.length === 0 ? 'Queue ready.' : 'Queue status loaded from Rust.')
    } catch (error) {
      setQueue(null)
      setMessage(`Queue bridge unavailable: ${String(error)}`)
    } finally {
      setBusy(false)
    }
  }

  async function startOne(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (busy || queue?.length !== 0) return

    setBusy(true)
    try {
      const id = await call('enqueue_download', {
        request: {
          url: url.trim(),
          format: 'mp3',
          quality: { type: 'audio', bitrate: 128 },
          isPlaylist: false,
        },
      })
      setLastId(id)
      setQueue(null)
      setMessage('Rust accepted the item. Refresh status to inspect it.')
    } catch (error) {
      setMessage(`Start failed: ${String(error)}`)
    } finally {
      setBusy(false)
    }
  }

  const item = queue?.[0]

  return (
    <main className="spike">
      <header>
        <span className="eyebrow">Gate 0C · Android spike</span>
        <h1>Zownload</h1>
        <p>One item, MP3 at 128 kbps. This screen is for checking the Android bridge.</p>
      </header>

      <form onSubmit={startOne} className="panel">
        <label htmlFor="source-url">YouTube URL</label>
        <input
          id="source-url"
          type="url"
          inputMode="url"
          placeholder="https://www.youtube.com/watch?v=…"
          value={url}
          onChange={(event) => setUrl(event.currentTarget.value)}
          required
        />
        <button type="submit" disabled={busy || queue?.length !== 0}>
          Start one item
        </button>
      </form>

      <section className="panel" aria-labelledby="status-heading">
        <div className="status-heading">
          <h2 id="status-heading">Status</h2>
          <button type="button" className="secondary" onClick={refreshQueue} disabled={busy}>
            Refresh from Rust
          </button>
        </div>
        <p className="status" role="status">{busy ? 'Working…' : message}</p>
        <dl>
          <div><dt>Queue items</dt><dd>{queue === null ? 'Unknown' : queue.length}</dd></div>
          <div><dt>Item ID</dt><dd className="identifier">{item?.id ?? lastId ?? '—'}</dd></div>
          <div><dt>Item state</dt><dd>{item?.status ?? '—'}</dd></div>
          <div><dt>Progress</dt><dd>{item?.progress.kind === 'single' ? `${item.progress.percent}%` : '—'}</dd></div>
        </dl>
      </section>
    </main>
  )
}
