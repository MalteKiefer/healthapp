/**
 * Throttled queue for lazy at-access encryption migration.
 *
 * Stage 2 re-encrypts existing plaintext rows in the background the first
 * time a client reads them. Without throttling we'd spam the API with one
 * migrate-content PATCH per legacy row visible on a list page. This keyed
 * FIFO queue processes one job at a time with a fixed inter-request delay.
 */

type Job = () => Promise<void>;

const QUEUES = new Map<string, { jobs: Job[]; running: boolean }>();
const DEFAULT_DELAY_MS = 500;

export function enqueueMigration(
  key: string,
  job: Job,
  delayMs: number = DEFAULT_DELAY_MS,
): void {
  let q = QUEUES.get(key);
  if (!q) {
    q = { jobs: [], running: false };
    QUEUES.set(key, q);
  }
  q.jobs.push(job);
  if (!q.running) {
    void drain(key, delayMs);
  }
}

async function drain(key: string, delayMs: number): Promise<void> {
  const q = QUEUES.get(key);
  if (!q) return;
  q.running = true;
  while (q.jobs.length > 0) {
    const job = q.jobs.shift()!;
    try {
      await job();
    } catch (err) {
      // Swallow — migration is best-effort. Next read retries.
      console.warn(`migrationQueue[${key}]: job failed`, err);
    }
    if (q.jobs.length > 0) {
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  q.running = false;
}
