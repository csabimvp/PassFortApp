// The storage seam: what the API needs from Table Storage, and nothing Table-specific. `table.ts`
// implements it over @azure/data-tables; the tests also run it in memory, so the A.3 logic is
// exercised without an emulator, and against a real Table endpoint when one is configured.
import type { Hlc } from "./validate.js";

/** The vault's control row (A.2). */
export interface Meta {
  seq: number;
  headerVersion: number;
  header: Uint8Array;
  authKeyHash: Uint8Array;
  purgedThroughSeq: number;
  failedAuthCount: number;
  lockedUntil: Date | null;
  createdAt: Date;
}

/** One sealed record as stored -- the pull DTO's fields, `sealed` as bytes. */
export interface StoredRecord {
  id: string;
  version: number;
  hlc: Hlc;
  sealed: Uint8Array;
  isDeleted: boolean;
  seq: number;
  writer: string;
}

/** A value with the ETag it was read at -- the optimistic-concurrency token for writing it back. */
export interface Versioned<T> {
  value: T;
  etag: string;
}

/** One record write in a push: create it (`etag: null`), or replace the version read at `etag`. */
export interface RecordWrite {
  record: StoredRecord;
  etag: string | null;
}

export interface VaultStore {
  /** Create a vault's `meta` row. `false` if the vault already exists. */
  createVault(vaultId: string, meta: Meta): Promise<boolean>;
  getMeta(vaultId: string): Promise<Versioned<Meta> | null>;
  getRecord(vaultId: string, id: string): Promise<Versioned<StoredRecord> | null>;
  /**
   * One atomic write: every record in `writes` plus `meta.seq = seq`, each guarded by the ETag it
   * was read at. `"raced"` when any ETag is stale or a create collides -- and then **nothing** was
   * written.
   */
  commitPush(
    vaultId: string,
    metaEtag: string,
    seq: number,
    writes: readonly RecordWrite[],
  ): Promise<"committed" | "raced">;
  /** Every record with `seq > since`, in any order. */
  recordsSince(vaultId: string, since: number): Promise<StoredRecord[]>;
}
