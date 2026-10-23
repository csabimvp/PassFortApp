// seq.ts: the A.3 push/pull guarantees (m5-sync.md Phase 2 checkpoint) -- gap-free seqs,
// all-or-nothing batches, one winner per race -- on every store in `storesUnderTest()`: always in
// memory, and on a real Table endpoint (with its 64 KiB / 100-operation limits) when configured.
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { before, describe, it } from "node:test";
import { PUSH_ATTEMPTS, pullChanges, pushRecords } from "../src/lib/seq.js";
import type { VaultStore } from "../src/lib/store.js";
import { MAX_PUSH_RECORDS, MAX_SEALED_BYTES, type PushInput } from "../src/lib/validate.js";
import { storesUnderTest } from "./support/stores.js";

const writer = randomUUID();

const record = (id: string, baseVersion: number, version: number, blocks = 1): PushInput => ({
  id,
  baseVersion,
  version,
  hlc: { wallMillis: Date.now(), counter: 0, deviceId: writer },
  sealed: new Uint8Array(randomBytes(40 + 256 * blocks)),
  isDeleted: false,
});

/** No real waiting between retries -- the races are still real. */
const fast = { sleep: () => Promise.resolve() };

for (const under of storesUnderTest()) {
  describe(`push and pull (${under.name} store)`, () => {
    let store: VaultStore;
    before(async () => {
      store = await under.make();
    });

    async function newVault(): Promise<string> {
      const vaultId = randomUUID();
      const created = await store.createVault(vaultId, {
        seq: 0,
        headerVersion: 1,
        header: new Uint8Array(randomBytes(133)),
        authKeyHash: new Uint8Array(randomBytes(32)),
        purgedThroughSeq: 0,
        failedAuthCount: 0,
        lockedUntil: null,
        createdAt: new Date(),
      });
      assert.ok(created);
      return vaultId;
    }

    const metaSeq = async (vaultId: string): Promise<number> => {
      const meta = await store.getMeta(vaultId);
      assert.ok(meta);
      return meta.value.seq;
    };

    it("refuses to create a vault twice", async () => {
      const vaultId = await newVault();
      const meta = await store.getMeta(vaultId);
      assert.ok(meta);
      assert.equal(await store.createVault(vaultId, meta.value), false);
    });

    it("gives three pushes seqs 1, 2, 3 and pulls them back byte-identical", async () => {
      const vaultId = await newVault();
      const sent = [record(randomUUID(), 0, 1), record(randomUUID(), 0, 1), record(randomUUID(), 0, 1)];
      for (const [index, r] of sent.entries()) {
        const result = await pushRecords(store, vaultId, writer, [r]);
        assert.equal(result.kind, "applied");
        assert.equal(result.seq, index + 1);
      }

      const all = await pullChanges(store, vaultId, 0);
      assert.ok(all);
      assert.deepEqual(all.records.map((r) => r.seq), [1, 2, 3]);
      for (const [index, r] of all.records.entries()) {
        assert.deepEqual(r.sealed, sent[index]?.sealed);
        assert.equal(r.writer, writer);
      }
      const none = await pullChanges(store, vaultId, 3);
      assert.ok(none);
      assert.deepEqual(none.records, []);
      assert.equal(none.seq, 3);
    });

    it("updates an existing record from the right base, and refuses a stale one", async () => {
      const vaultId = await newVault();
      const id = randomUUID();
      await pushRecords(store, vaultId, writer, [record(id, 0, 1)]);

      const next = await pushRecords(store, vaultId, writer, [record(id, 1, 2)]);
      assert.equal(next.kind, "applied");

      const stale = await pushRecords(store, vaultId, writer, [record(id, 1, 2)]);
      assert.deepEqual(stale, { kind: "conflict", conflicts: [{ id, serverVersion: 2 }] });
      const recreate = await pushRecords(store, vaultId, writer, [record(id, 0, 1)]);
      assert.deepEqual(recreate, { kind: "conflict", conflicts: [{ id, serverVersion: 2 }] });
      assert.equal(await metaSeq(vaultId), 2); // conflicts consume no seq
    });

    it("writes nothing when any record in the batch conflicts", async () => {
      const vaultId = await newVault();
      const existing = randomUUID();
      await pushRecords(store, vaultId, writer, [record(existing, 0, 1)]);

      const fresh = randomUUID();
      const result = await pushRecords(store, vaultId, writer, [
        record(fresh, 0, 1),
        record(existing, 0, 1), // stale: the server has version 1
      ]);
      assert.equal(result.kind, "conflict");
      assert.equal(await store.getRecord(vaultId, fresh), null);
      assert.equal(await metaSeq(vaultId), 1);
    });

    it("lets exactly one of two racing pushes from the same base win", async () => {
      const vaultId = await newVault();
      const id = randomUUID();
      await pushRecords(store, vaultId, writer, [record(id, 0, 1)]);

      const results = await Promise.all([
        pushRecords(store, vaultId, writer, [record(id, 1, 2)], fast),
        pushRecords(store, vaultId, writer, [record(id, 1, 2)], fast),
      ]);
      assert.deepEqual(results.map((r) => r.kind).sort(), ["applied", "conflict"]);
      assert.equal(await metaSeq(vaultId), 2);
    });

    it("keeps seqs gap-free and unique under a 10-way race on different records", async () => {
      const vaultId = await newVault();
      const results = await Promise.all(
        Array.from({ length: 10 }, () =>
          pushRecords(store, vaultId, writer, [record(randomUUID(), 0, 1)]),
        ),
      );
      const seqs = results.flatMap((r) => (r.kind === "applied" ? [r.seq] : []));
      assert.equal(seqs.length, 10, "with backoff, every pusher lands");
      assert.deepEqual([...seqs].sort((a, b) => a - b), Array.from({ length: 10 }, (_, i) => i + 1));
      assert.equal(await metaSeq(vaultId), 10);
    });

    it("lands a full 99-record batch as one write", async () => {
      const vaultId = await newVault();
      const batch = Array.from({ length: MAX_PUSH_RECORDS }, () => record(randomUUID(), 0, 1));
      const result = await pushRecords(store, vaultId, writer, batch);
      assert.equal(result.kind, "applied");
      assert.deepEqual(result.applied.map((a) => a.seq), batch.map((_, i) => i + 1));
      assert.equal((await pullChanges(store, vaultId, 0))?.records.length, MAX_PUSH_RECORDS);
    });

    it("stores a record at the 65,320-byte cap", async () => {
      const vaultId = await newVault();
      const big = record(randomUUID(), 0, 1, 255);
      assert.equal(big.sealed.length, MAX_SEALED_BYTES);
      assert.equal((await pushRecords(store, vaultId, writer, [big])).kind, "applied");
      const pulled = await pullChanges(store, vaultId, 0);
      assert.deepEqual(pulled?.records[0]?.sealed, big.sealed);
    });

    it("reports an unknown vault", async () => {
      const result = await pushRecords(store, randomUUID(), writer, [record(randomUUID(), 0, 1)]);
      assert.deepEqual(result, { kind: "notFound" });
    });

    it("gives up as unavailable, having written nothing, when a rival wins every attempt", async () => {
      const vaultId = await newVault();
      const ours = randomUUID();
      // Between our reads and every commit, a rival device pushes a record of its own, so the
      // meta ETag we hold is always stale.
      let rivals = 0;
      const contested: VaultStore = {
        createVault: (...args) => store.createVault(...args),
        getMeta: (...args) => store.getMeta(...args),
        getRecord: (...args) => store.getRecord(...args),
        recordsSince: (...args) => store.recordsSince(...args),
        commitPush: async (...args) => {
          rivals += 1;
          await pushRecords(store, vaultId, randomUUID(), [record(randomUUID(), 0, 1)]);
          return store.commitPush(...args);
        },
      };

      const result = await pushRecords(contested, vaultId, writer, [record(ours, 0, 1)], fast);
      assert.equal(result.kind, "unavailable");
      assert.equal(rivals, PUSH_ATTEMPTS);
      assert.equal(await store.getRecord(vaultId, ours), null);
      assert.equal(await metaSeq(vaultId), PUSH_ATTEMPTS); // only the rival's records
    });

    it("pages with limit and hasMore, ascending by seq", async () => {
      const vaultId = await newVault();
      for (let i = 0; i < 5; i++) await pushRecords(store, vaultId, writer, [record(randomUUID(), 0, 1)]);

      const first = await pullChanges(store, vaultId, 0, 2);
      assert.ok(first);
      assert.deepEqual(first.records.map((r) => r.seq), [1, 2]);
      assert.equal(first.hasMore, true);
      const rest = await pullChanges(store, vaultId, 2, 500);
      assert.ok(rest);
      assert.deepEqual(rest.records.map((r) => r.seq), [3, 4, 5]);
      assert.equal(rest.hasMore, false);
      assert.equal(rest.headerVersion, 1);
      assert.equal(rest.purgedThroughSeq, 0);
    });

    it("returns the newest version of an updated record once, at its new seq", async () => {
      const vaultId = await newVault();
      const id = randomUUID();
      await pushRecords(store, vaultId, writer, [record(id, 0, 1)]);
      await pushRecords(store, vaultId, writer, [record(id, 1, 2)]);
      const changes = await pullChanges(store, vaultId, 0);
      assert.deepEqual(changes?.records.map((r) => [r.version, r.seq]), [[2, 2]]);
    });

    it("returns null for an unknown vault and never leaks another vault's records", async () => {
      assert.equal(await pullChanges(store, randomUUID(), 0), null);
      const mine = await newVault();
      const theirs = await newVault();
      await pushRecords(store, theirs, writer, [record(randomUUID(), 0, 1)]);
      assert.deepEqual((await pullChanges(store, mine, 0))?.records, []);
    });
  });
}
