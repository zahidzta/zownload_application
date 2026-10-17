/**
 * zownload — UI <-> engine contract (TypeScript side).
 * Must mirror src-tauri/src/contract.rs. All JSON is camelCase.
 *
 * Rules of the game:
 *  - The UI NEVER knows which engine runs (desktop sidecar / Android Kotlin).
 *  - A download is always started with `enqueue_download`.
 *    "Redownload" from History = enqueue_download(entry.request). No special command.
 *  - Rust throttles progress events (max ~5 per second per item).
 *  - YouTube needs a JS runtime for yt-dlp: QuickJS on ALL platforms for now
 *    (`--js-runtimes quickjs:<path>`). The UI never sees this; a missing or
 *    broken runtime surfaces as the "engine_missing" error.
 *  - Redownload shows up in the queue card like any download (status
 *    "analyzing" first, then "queued"/"downloading").
 *  - Finished items leave the queue. Failures are persisted separately as
 *    ErrorNotification records until the user dismisses them.
 */

// ───────────────────────── Core types ─────────────────────────

export type Format = "mp3" | "mp4";

/**
 * Quality choice.
 *  - Playlist: only "max" | "min".
 *      mp4 max = best video + best audio      mp4 min = worst video + best audio
 *      mp3 max = best source + 320 kbps MP3   mp3 min = best source + 128 kbps MP3
 *  - Single:   "video" (mp4, height in px) or "audio" (MP3 output bitrate).
 *    Single MP3 always uses the best source audio. On redownload, if the exact
 *    video quality no longer exists, the engine uses the closest lower one.
 */
export type Quality =
  | { type: "max" }
  | { type: "min" }
  | { type: "video"; height: number }
  | { type: "audio"; bitrate: number };

/** The four things we persist for history and need to start a download. */
export interface DownloadRequest {
  url: string;
  format: Format;
  quality: Quality;
  isPlaylist: boolean;
}

// ───────────────────────── Analyze ─────────────────────────

export type AnalyzeResult =
  | {
      kind: "single";
      url: string;
      title: string;
      author: string;
      thumbnail: string | null;
      durationSec: number;
      site: string; // e.g. "YouTube"
      videoHeights: number[]; // for the mp4 combo box, e.g. [1080, 720, 480]
      audioOutputBitrates: number[]; // fixed MP3 output presets: [320, 256, 192, 128]
    }
  | {
      kind: "playlist";
      url: string;
      title: string;
      author: string;
      thumbnail: string | null;
      site: string;
      itemCount: number;
      itemTitles: string[]; // the list card under the download card
    };

// ───────────────────────── Queue ─────────────────────────

export type ItemStatus =
  | "analyzing" // enqueued (e.g. from redownload), fetching info
  | "queued"
  | "downloading"
  | "postProcessing" // ffmpeg metadata/extraction/merge; pause is disabled
  | "paused" // UI shows "Paused", never a frozen bar
  | "packaging" // zip writing/finalization; pause is disabled
  | "done" // transient; item is removed after history is written
  | "failed"; // transient; error notification is persisted, then item is removed

export type Progress =
  | { kind: "single"; percent: number } // 0..100
  | {
      kind: "playlist";
      done: number; // shows "5/10"
      failed: number; // shows "10 correct, 5 failed" when > 0
      total: number; // 0 until analyzed
      currentTitle: string | null;
      currentPercent: number;
    };

export interface QueueItem {
  id: string; // uuid
  request: DownloadRequest;
  title: string | null; // null while analyzing
  thumbnail: string | null;
  status: ItemStatus;
  progress: Progress;
  error: AppError | null;
}

// ───────────────────────── History ─────────────────────────

/**
 * Stored: url, format, isPlaylist, quality (= `request`) plus `title`, which
 * is display-only so the History card shows something readable.
 * Newest first = highest id first. Rust keeps (url, format, isPlaylist,
 * quality) unique: on a repeat download it deletes the old row and inserts a
 * new one, so the entry moves to the top without creating a duplicate.
 */
export interface HistoryEntry {
  id: number;
  request: DownloadRequest;
  title: string | null;
}

/** Persisted until dismissed, even though the failed item leaves the queue. */
export interface ErrorNotification {
  id: string; // id of the queue item that failed
  title: string | null;
  error: AppError;
}

// ───────────────────────── Settings ─────────────────────────

export type Language = "en" | "es";

export interface Settings {
  language: Language;
  zipPlaylists: boolean; // true: one .zip. false: files one by one, named after each element
  /** null = system Downloads folder. Ignored on Android (MediaStore). */
  downloadDir: string | null;
}

// ───────────────────────── Engine updates ─────────────────────────

export interface EngineUpdateInfo {
  current: string; // yt-dlp version in use
  latest: string;
  updateAvailable: boolean;
}

// ───────────────────────── Errors ─────────────────────────

/** UI maps `code` to an i18n key: `errors.<code>` and shows it in red under the input. */
export type ErrorCode =
  | "invalid_url"
  | "unsupported_site"
  | "private_or_restricted"
  | "not_found"
  | "no_internet"
  | "disk_full"
  | "permission_denied"
  | "engine_missing"
  | "unknown";

export interface AppError {
  code: ErrorCode;
  detail: string | null; // raw message, for logs / "show details"
}

// ───────────────────────── Commands (UI -> Rust) ─────────────────────────
// Tauri maps camelCase JS args to snake_case Rust params automatically.
// Every command can reject with an AppError.

export interface Commands {
  analyze_url: { args: { url: string }; result: AnalyzeResult };

  enqueue_download: { args: { request: DownloadRequest }; result: string }; // returns queue item id
  pause_download: { args: { id: string }; result: void };
  resume_download: { args: { id: string }; result: void };
  remove_download: { args: { id: string }; result: void }; // cancel + delete from queue
  get_queue: { args: Record<string, never>; result: QueueItem[] };

  get_history: { args: Record<string, never>; result: HistoryEntry[] };
  delete_history_entry: { args: { id: number }; result: void };
  clear_history: { args: Record<string, never>; result: void };

  get_error_notifications: { args: Record<string, never>; result: ErrorNotification[] };
  dismiss_error_notification: { args: { id: string }; result: void };

  get_settings: { args: Record<string, never>; result: Settings };
  set_settings: { args: { settings: Settings }; result: void };

  engine_check_update: { args: Record<string, never>; result: EngineUpdateInfo };
  engine_update: { args: Record<string, never>; result: EngineUpdateInfo };
}

// ───────────────────────── Events (Rust -> UI) ─────────────────────────

export interface Events {
  /** Full item snapshot; progress is throttled. Insert if the id is new. */
  "queue:item-updated": QueueItem;
  "queue:item-removed": string; // id
  /** Something finished/changed: refetch with get_history. */
  "history:changed": null;
  /** A persistent error was added or dismissed; refetch notifications. */
  "error-notifications:changed": null;
}

// ───────────────────────── Typed helpers ─────────────────────────

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export function call<K extends keyof Commands>(
  cmd: K,
  args: Commands[K]["args"],
): Promise<Commands[K]["result"]> {
  return invoke<Commands[K]["result"]>(cmd, args);
}

export function on<K extends keyof Events>(
  name: K,
  handler: (payload: Events[K]) => void,
): Promise<UnlistenFn> {
  return listen<Events[K]>(name, (e) => handler(e.payload));
}

// Usage:
//   const info = await call("analyze_url", { url });
//   const id   = await call("enqueue_download", { request });
//   const off  = await on("queue:item-updated", (item) => store.upsert(item));
