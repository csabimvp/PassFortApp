// The A.3 push and pull: the only write path for records, and the per-vault seq that orders them.
// Written to the runbook's algorithm literally -- meta + every pushed record in ONE atomic write,
// guarded by ETags, retried with jittered backoff when a racing writer wins. Storage-agnostic: it
// runs on any `VaultStore` (Table Storage in production, memory in tests).
import type { RecordWrite, StoredRecord, VaultStore } from "./store.js";
import type { PushInput } from "./validate.js";

/** Tries before giving up with 503 (A.3). */
export const PUSH_ATTEMPTS = 5;
/** `limit` on a pull: default and ceiling (A.3 `limit ≤ 500`). */
export const PULL_LIMIT_MAX = 500;

export type PushResult =
  | { kind: "applied"; applied: { id: string; version: number; seq: number }[]; seq: number }
  | { kind: "conflict"; conflicts: { id: string; serverVersion: number }[] }
  | { kind: "notFound" }
  | { kind: "unavailable" };

/** Seams for tests: how to wait between attempts, and where the jitter comes from. */
export interface PushOptions {
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}

const defaultSleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * Push a validated batch for `vaultId`, written by device `writer` (from the JWT, never the body).
 *
 * Every record's `baseVersion` must equal the server's current version (0 = must not exist), or
 * the whole batch is refused with the conflicts and **nothing is written**. Otherwise each record
 * gets the next seq, in request order, and the records plus `meta.seq` land in one atomic write.
 * A lost race re-reads and retries; after `PUSH_ATTEMPTS`, `unavailable`.
 */
export async function pushRecords(
  store: VaultStore,
  vaultId: string,
  writer: string,
  records: readonly PushInput[],
  options: PushOptions = {},
): Promise<PushResult> {
  const sleep = options.sleep ?? defaultSleep;
  const random = options.random ?? Math.random;

  for (let attempt = 1; attempt <= PUSH_ATTEMPTS; attempt++) {
    const meta = await store.getMeta(vaultId);
    if (meta === null) return { kind: "notFound" };
    const current = await Promise.all(records.map((record) => store.getRecord(vaultId, record.id)));

    const conflicts = records.flatMap((record, index) => {
      const serverVersion = current[index]?.value.version ?? 0;
      return serverVersion === record.baseVersion ? [] : [{ id: record.id, serverVersion }];
    });
    if (conflicts.length > 0) return { kind: "conflict", conflicts };

    let seq = meta.value.seq;
    const writes: RecordWrite[] = records.map((record, index) => {
      seq += 1;
      return { record: { ...record, seq, writer }, etag: current[index]?.etag ?? null };
    });

    if ((await store.commitPush(vaultId, meta.etag, seq, writes)) === "committed") {
      const applied = writes.map(({ record }) => ({
        id: record.id,
        version: record.version,
        seq: record.seq,
      }));
      return { kind: "applied", applied, seq };
    }
    // Someone else's push landed between our reads and our write. Back off and re-read.
    await sleep((20 + random() * 60) * attempt);
  }
  return { kind: "unavailable" };
}

export interface Changes {
  records: StoredRecord[];
  /** `meta.seq` -- the server's high-water mark, even when `records` is empty. */
  seq: number;
  hasMore: boolean;
  headerVersion: number;
  purgedThroughSeq: number;
}

/**
 * Records with `seq > since`, ascending, at most `limit` (clamped to 1...500). `null` if the
 * vault does not exist.
 */
export async function pullChanges(
  store: VaultStore,
  vaultId: string,
  since: number,
  limit: number = PULL_LIMIT_MAX,
): Promise<Changes | null> {
  const meta = await store.getMeta(vaultId);
  if (meta === null) return null;

  const rows = await store.recordsSince(vaultId, since);
  rows.sort((a, b) => a.seq - b.seq);

  const pageSize = Math.min(Math.max(Math.trunc(limit), 1), PULL_LIMIT_MAX);
  return {
    records: rows.slice(0, pageSize),
    seq: meta.value.seq,
    hasMore: rows.length > pageSize,
    headerVersion: meta.value.headerVersion,
    purgedThroughSeq: meta.value.purgedThroughSeq,
  };
}
