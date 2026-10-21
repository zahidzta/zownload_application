// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { call, on, type QueueItem } from '../shared/contract'

export default function App() {
  const [url, setUrl] = useState('')
  const [queue, setQueue] = useState<QueueItem[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('Loading queue from Rust…')
  const [lastId, setLastId] = useState<string | null>(null)
  const mounted = useRef(false)
  const loadVersion = useRef(0)

  async function refreshQueue() {
    const version = ++loadVersion.current
    try {
      const items = await call('get_queue', {})
      if (!mounted.current || version !== loadVersion.current) return
      setQueue(items)
      setMessage((current) =>
        current === 'Loading queue from Rust…'
          ? items.length === 0 ? 'Queue ready.' : 'Queue restored from Rust.'
          : current,
      )
    } catch (error) {
      if (!mounted.current || version !== loadVersion.current) return
      setQueue(null)
      setMessage(`Queue bridge unavailable: ${String(error)}`)
    }
  }

  useEffect(() => {
    mounted.current = true
    let disposed = false
    const unsubscribe: Array<() => void> = []
    async function connect() {
      try {
        const offUpdated = await on('queue:item-updated', () => { void refreshQueue() })
        if (disposed) { offUpdated(); return }
        unsubscribe.push(offUpdated)
        const offRemoved = await on('queue:item-removed', () => { void refreshQueue() })
        if (disposed) { offRemoved(); return }
        unsubscribe.push(offRemoved)
      } catch (error) {
        if (!disposed) setMessage(`Queue subscription unavailable: ${String(error)}`)
      } finally {
        if (!disposed) await refreshQueue()
      }
    }
    void connect()
    return () => {
      disposed = true
      mounted.current = false
      loadVersion.current += 1
      unsubscribe.forEach((off) => off())
    }
  }, [])

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
      setMessage('MP3 published in Downloads. Open it on the device to check playback.')
    } catch (error) {
      setMessage(`Start failed: ${String(error)}`)
    } finally {
      setBusy(false)
      void refreshQueue()
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
        <button type="submit" disabled={busy || queue === null || queue.length !== 0}>
          Start one item
        </button>
      </form>

      <section className="panel" aria-labelledby="status-heading">
        <div className="status-heading">
          <h2 id="status-heading">Status</h2>
          <button type="button" className="secondary" onClick={() => { void refreshQueue() }} disabled={busy}>
            Refresh from Rust
          </button>
        </div>
        <p className="status" role="status">{busy ? 'Working…' : message}</p>
        <dl>
          <div><dt>Queue items</dt><dd>{queue === null ? 'Unknown' : queue.length}</dd></div>
          <div><dt>Item ID</dt><dd className="identifier">{item?.id ?? lastId ?? '—'}</dd></div>
          <div><dt>Item state</dt><dd>{item?.status === 'paused' ? 'Paused' : item?.status ?? '—'}</dd></div>
          <div><dt>Progress</dt><dd>{item?.progress.kind === 'single' ? `${item.progress.percent}%` : '—'}</dd></div>
        </dl>
      </section>
    </main>
  )
}
