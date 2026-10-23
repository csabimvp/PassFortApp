// The A.2 data model on Azure Table Storage: one table, one partition per vault. `TableStore` is
// the production `VaultStore`; everything Table-specific (Int64 values, RowKey prefixes, ETags,
// transactions) stays in this file.
import {
  TableClient,
  odata,
  type TableEntity,
  type TableEntityResult,
  type TransactionAction,
} from "@azure/data-tables";
import type { Meta, RecordWrite, StoredRecord, VaultStore, Versioned } from "./store.js";

export const META_KEY = "meta";
export const RECORD_PREFIX = "rec_";
export const DEVICE_PREFIX = "dev_";
/** The first string after every `rec_…` key: '`' is the character after '_' (A.2 range scan). */
export const RECORD_PREFIX_END = "rec`";

export const recordKey = (id: string): string => `${RECORD_PREFIX}${id}`;
export const deviceKey = (id: string): string => `${DEVICE_PREFIX}${id}`;

type Entity = TableEntityResult<Record<string, unknown>>;

export class TableStore implements VaultStore {
  constructor(private readonly table: TableClient) {}

  /** `allowInsecureConnection` only matters for an emulator's http endpoint. */
  static fromConnectionString(connectionString: string, tableName: string): TableStore {
    const local = /UseDevelopmentStorage=true|127\.0\.0\.1|localhost/.test(connectionString);
    const table = TableClient.fromConnectionString(connectionString, tableName, {
      allowInsecureConnection: local,
    });
    return new TableStore(table);
  }

  /** Create the table if it is missing -- tests and first deploys; Bicep creates it in the cloud. */
  async ensureTable(): Promise<void> {
    await this.table.createTable();
  }

  async createVault(vaultId: string, meta: Meta): Promise<boolean> {
    try {
      await this.table.createEntity(metaEntity(vaultId, meta));
      return true;
    } catch (error) {
      if (statusOf(error) === 409) return false;
      throw error;
    }
  }

  async getMeta(vaultId: string): Promise<Versioned<Meta> | null> {
    const entity = await this.getOrNull(vaultId, META_KEY);
    return entity && { value: readMeta(entity), etag: entity.etag };
  }

  async getRecord(vaultId: string, id: string): Promise<Versioned<StoredRecord> | null> {
    const entity = await this.getOrNull(vaultId, recordKey(id));
    return entity && { value: readRecord(entity), etag: entity.etag };
  }

  async commitPush(
    vaultId: string,
    metaEtag: string,
    seq: number,
    writes: readonly RecordWrite[],
  ): Promise<"committed" | "raced"> {
    const actions: TransactionAction[] = writes.map(({ record, etag }) => {
      const entity = recordEntity(vaultId, record);
      return etag === null ? ["create", entity] : ["update", entity, "Replace", { etag }];
    });
    actions.push([
      "update",
      { partitionKey: vaultId, rowKey: META_KEY, seq: int64(seq) },
      "Merge",
      { etag: metaEtag },
    ]);
    try {
      await this.table.submitTransaction(actions);
      return "committed";
    } catch (error) {
      // 412: an If-Match ETag was stale. 409: a create collided with a row someone else created.
      const status = statusOf(error);
      if (status === 412 || status === 409) return "raced";
      throw error;
    }
  }

  async recordsSince(vaultId: string, since: number): Promise<StoredRecord[]> {
    const filter =
      odata`PartitionKey eq ${vaultId} and RowKey ge ${RECORD_PREFIX} and RowKey lt ${RECORD_PREFIX_END}` +
      ` and seq gt ${String(Math.trunc(since))}L`;
    const rows: StoredRecord[] = [];
    for await (const entity of this.table.listEntities({ queryOptions: { filter } })) {
      rows.push(readRecord(entity));
    }
    return rows;
  }

  /** A point read that returns `null` for 404 instead of throwing. */
  private async getOrNull(partitionKey: string, rowKey: string): Promise<Entity | null> {
    try {
      return await this.table.getEntity(partitionKey, rowKey);
    } catch (error) {
      if (statusOf(error) === 404) return null;
      throw error;
    }
  }
}

// MARK: - Edm.Int64, DateTime, Binary

/** Table Storage's Int64 on the wire. JS numbers are exact to 2^53 -- far past any seq or version. */
interface Int64 {
  value: string;
  type: "Int64";
}

const int64 = (n: number): Int64 => ({ value: String(n), type: "Int64" });

/**
 * Read a numeric property. @azure/data-tables 13.3 returns Int64 as a `bigint` and Int32 as a
 * number; older shapes (a `{ value, type }` wrapper, a string) are accepted too. An Int64 beyond
 * 2^53 would lose precision as a JS number, so it is refused rather than rounded.
 */
export function readNumber(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "bigint") {
    if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < BigInt(Number.MIN_SAFE_INTEGER)) {
      throw new RangeError("Int64 table property outside the safe integer range");
    }
    return Number(value);
  }
  if (typeof value === "object" && value !== null && "value" in value) {
    return Number(value.value);
  }
  if (typeof value === "string") return Number(value);
  throw new TypeError("not a numeric table property");
}

/** A DateTime property: the SDK may return a `Date`, an ISO string, or a typed wrapper. */
function readDate(value: unknown): Date {
  if (value instanceof Date) return value;
  if (typeof value === "string") return new Date(value);
  if (typeof value === "object" && value !== null && "value" in value) {
    return new Date(String(value.value));
  }
  throw new TypeError("not a DateTime table property");
}

/**
 * A Binary property, **copied** into its own `Uint8Array`. The SDK returns a `Buffer` that is a
 * slice of a shared pool; a view onto it, written back to Table Storage, serializes the whole pool
 * (found by the Table-backed suite: re-writing a read `header` failed with PropertyValueTooLarge).
 */
function readBytes(value: unknown): Uint8Array {
  if (value instanceof Uint8Array) return Uint8Array.from(value);
  throw new TypeError("not a binary table property");
}

// MARK: - meta

function metaEntity(vaultId: string, meta: Meta): TableEntity {
  return {
    partitionKey: vaultId,
    rowKey: META_KEY,
    seq: int64(meta.seq),
    headerVersion: int64(meta.headerVersion),
    header: meta.header,
    authKeyHash: meta.authKeyHash,
    purgedThroughSeq: int64(meta.purgedThroughSeq),
    failedAuthCount: meta.failedAuthCount,
    // Table Storage has no null: an absent property is "not locked".
    ...(meta.lockedUntil === null ? {} : { lockedUntil: meta.lockedUntil }),
    createdAt: meta.createdAt,
  };
}

function readMeta(entity: Entity): Meta {
  const lockedUntil = entity["lockedUntil"];
  return {
    seq: readNumber(entity["seq"]),
    headerVersion: readNumber(entity["headerVersion"]),
    header: readBytes(entity["header"]),
    authKeyHash: readBytes(entity["authKeyHash"]),
    purgedThroughSeq: readNumber(entity["purgedThroughSeq"]),
    failedAuthCount: readNumber(entity["failedAuthCount"]),
    lockedUntil: lockedUntil === undefined ? null : readDate(lockedUntil),
    createdAt: readDate(entity["createdAt"]),
  };
}

// MARK: - rec_<id>

function recordEntity(vaultId: string, record: StoredRecord): TableEntity {
  return {
    partitionKey: vaultId,
    rowKey: recordKey(record.id),
    version: int64(record.version),
    hlcWall: int64(record.hlc.wallMillis),
    hlcCounter: record.hlc.counter,
    hlcDevice: record.hlc.deviceId,
    sealed: record.sealed,
    isDeleted: record.isDeleted,
    seq: int64(record.seq),
    writer: record.writer,
  };
}

function readRecord(entity: Entity): StoredRecord {
  return {
    id: (entity.rowKey ?? "").slice(RECORD_PREFIX.length),
    version: readNumber(entity["version"]),
    hlc: {
      wallMillis: readNumber(entity["hlcWall"]),
      counter: readNumber(entity["hlcCounter"]),
      deviceId: String(entity["hlcDevice"]),
    },
    sealed: readBytes(entity["sealed"]),
    isDeleted: entity["isDeleted"] === true,
    seq: readNumber(entity["seq"]),
    writer: String(entity["writer"]),
  };
}

/** The HTTP status on an Azure SDK `RestError`, if there is one. */
function statusOf(error: unknown): number | undefined {
  if (typeof error === "object" && error !== null && "statusCode" in error) {
    return typeof error.statusCode === "number" ? error.statusCode : undefined;
  }
  return undefined;
}
