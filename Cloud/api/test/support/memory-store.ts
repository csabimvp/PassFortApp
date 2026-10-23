// An in-memory `VaultStore` with the same concurrency contract as Table Storage: every read hands
// out an ETag, and `commitPush` is all-or-nothing against them. Each call yields to the event loop
// first, so concurrent pushes really do interleave between their reads and their commit.
import type { Meta, RecordWrite, StoredRecord, VaultStore, Versioned } from "../../src/lib/store.js";

interface Partition {
  meta: Versioned<Meta>;
  records: Map<string, Versioned<StoredRecord>>;
}

export class MemoryStore implements VaultStore {
  private readonly vaults = new Map<string, Partition>();
  private nextEtag = 0;

  private etag(): string {
    this.nextEtag += 1;
    return `W/"${String(this.nextEtag)}"`;
  }

  async createVault(vaultId: string, meta: Meta): Promise<boolean> {
    await Promise.resolve();
    if (this.vaults.has(vaultId)) return false;
    this.vaults.set(vaultId, {
      meta: { value: structuredClone(meta), etag: this.etag() },
      records: new Map(),
    });
    return true;
  }

  async getMeta(vaultId: string): Promise<Versioned<Meta> | null> {
    await Promise.resolve();
    const meta = this.vaults.get(vaultId)?.meta;
    return meta ? structuredClone(meta) : null;
  }

  async getRecord(vaultId: string, id: string): Promise<Versioned<StoredRecord> | null> {
    await Promise.resolve();
    const record = this.vaults.get(vaultId)?.records.get(id);
    return record ? structuredClone(record) : null;
  }

  async commitPush(
    vaultId: string,
    metaEtag: string,
    seq: number,
    writes: readonly RecordWrite[],
  ): Promise<"committed" | "raced"> {
    await Promise.resolve();
    const vault = this.vaults.get(vaultId);
    if (!vault || vault.meta.etag !== metaEtag) return "raced";
    for (const { record, etag } of writes) {
      const existing = vault.records.get(record.id);
      if (etag === null ? existing !== undefined : existing?.etag !== etag) return "raced";
    }
    // Every guard held: apply it all.
    for (const { record } of writes) {
      vault.records.set(record.id, { value: structuredClone(record), etag: this.etag() });
    }
    vault.meta = { value: { ...vault.meta.value, seq }, etag: this.etag() };
    return "committed";
  }

  async recordsSince(vaultId: string, since: number): Promise<StoredRecord[]> {
    await Promise.resolve();
    const records = this.vaults.get(vaultId)?.records.values() ?? [];
    return [...records].filter((r) => r.value.seq > since).map((r) => structuredClone(r.value));
  }
}
