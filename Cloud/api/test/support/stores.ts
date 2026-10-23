// The stores a storage suite runs against: always the in-memory one, plus a real Table endpoint
// when `PASSFORT_TEST_TABLES` holds a connection string -- the Azurite service container in CI,
// or a scratch storage account. Nothing to install locally.
import { randomUUID } from "node:crypto";
import type { VaultStore } from "../../src/lib/store.js";
import { TableStore } from "../../src/lib/table.js";
import { MemoryStore } from "./memory-store.js";

export interface StoreUnderTest {
  name: string;
  /** The real Table endpoint, where Table-specific limits (64 KiB Binary, 100-op batches) apply. */
  isTable: boolean;
  make: () => Promise<VaultStore>;
}

export function storesUnderTest(): StoreUnderTest[] {
  const stores: StoreUnderTest[] = [
    { name: "memory", isTable: false, make: () => Promise.resolve(new MemoryStore()) },
  ];
  const connectionString = process.env["PASSFORT_TEST_TABLES"];
  if (connectionString) {
    stores.push({
      name: "table",
      isTable: true,
      make: async () => {
        // A fresh table per suite run, so runs never see each other's vaults.
        const name = `t${randomUUID().replaceAll("-", "")}`;
        const store = TableStore.fromConnectionString(connectionString, name);
        await store.ensureTable();
        return store;
      },
    });
  }
  return stores;
}
