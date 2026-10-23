// Input checks for the push path (m5-sync.md A.2 / A.3): framing, sizes, UUIDs, version rules.
// Pure functions, no I/O. Schema closure (unknown fields -> 400) is the endpoint's job (Phase 3);
// these run on a body that already has the right shape.

/** Nonce (24) + Poly1305 tag (16): the AEAD overhead on every sealed record (§5.4). */
export const SEALED_OVERHEAD = 40;
/** Ciphertext is padded to multiples of this (§14.7). */
export const SEALED_BUCKET = 256;
/** One bucket of ciphertext: the smallest well-framed record. */
export const MIN_SEALED_BYTES = SEALED_OVERHEAD + SEALED_BUCKET; // 296
/** The largest padded size whose Binary property fits Table Storage's 64 KiB (A.2). */
export const MAX_SEALED_BYTES = SEALED_OVERHEAD + SEALED_BUCKET * 255; // 65,320
/** 99 records + the `meta` update = Table Storage's 100-operation transaction limit. */
export const MAX_PUSH_RECORDS = 99;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

/** A failed check: the stable error code (A.3) and a message that never echoes the input. */
export interface Invalid {
  code: "bad_request" | "too_large";
  message: string;
}

const badRequest = (message: string): Invalid => ({ code: "bad_request", message });

/** Lower-case RFC 4122 form only -- the contract's `Uuid`. */
export function isUuid(value: string): boolean {
  return UUID.test(value);
}

/** Strict standard-alphabet, padded base64 -> bytes; `null` for anything else. */
export function decodeBase64(value: string): Uint8Array | null {
  if (!BASE64.test(value)) return null;
  return new Uint8Array(Buffer.from(value, "base64"));
}

/**
 * Size, then framing: `nonce ‖ 256·k ciphertext ‖ tag`. A client-bug tripwire, not a crypto check
 * -- the server can't tell a well-framed forgery from a record, and doesn't need to (every client
 * `pf_open`s what it pulls).
 */
export function checkSealed(sealed: Uint8Array): Invalid | null {
  if (sealed.length > MAX_SEALED_BYTES) {
    return { code: "too_large", message: `sealed records are at most ${String(MAX_SEALED_BYTES)} bytes` };
  }
  if (sealed.length < MIN_SEALED_BYTES || (sealed.length - SEALED_OVERHEAD) % SEALED_BUCKET !== 0) {
    return badRequest("sealed is not a framed record (24-byte nonce, 256-byte blocks, 16-byte tag)");
  }
  return null;
}

/** The HLC as the client sends it. */
export interface Hlc {
  wallMillis: number;
  counter: number;
  deviceId: string;
}

/** One push element after base64 decoding -- what `seq.ts` stores. */
export interface PushInput {
  id: string;
  baseVersion: number;
  version: number;
  hlc: Hlc;
  sealed: Uint8Array;
  isDeleted: boolean;
}

/** One push element as it arrives (the DTO shape, `sealed` still base64). */
export interface PushWire {
  id: string;
  baseVersion: number;
  version: number;
  hlc: Hlc;
  sealed: string;
  isDeleted: boolean;
}

const isCount = (n: number): boolean => Number.isSafeInteger(n) && n >= 0;

/**
 * Validate and decode a push batch: 1-99 records, UUID ids with no duplicates, integral
 * `version > baseVersion >= 0`, a sane HLC, and well-framed `sealed` bytes. Returns the decoded
 * batch, or the first problem found.
 */
export function validatePushBatch(records: readonly PushWire[]): PushInput[] | Invalid {
  if (records.length === 0) return badRequest("a push carries at least one record");
  if (records.length > MAX_PUSH_RECORDS) {
    return badRequest(`a push carries at most ${String(MAX_PUSH_RECORDS)} records`);
  }

  const seen = new Set<string>();
  const decoded: PushInput[] = [];
  for (const [index, record] of records.entries()) {
    const at = `records[${String(index)}]`;
    if (!isUuid(record.id)) return badRequest(`${at}.id is not a lower-case UUID`);
    if (seen.has(record.id)) return badRequest(`${at}.id appears twice in one push`);
    seen.add(record.id);

    if (!isCount(record.baseVersion)) return badRequest(`${at}.baseVersion is not a count`);
    if (!isCount(record.version) || record.version <= record.baseVersion) {
      return badRequest(`${at}.version must be greater than baseVersion`);
    }
    const { hlc } = record;
    if (!isCount(hlc.wallMillis) || !isCount(hlc.counter) || hlc.counter > 0x7fff_ffff) {
      return badRequest(`${at}.hlc is out of range`);
    }
    if (!isUuid(hlc.deviceId)) return badRequest(`${at}.hlc.deviceId is not a lower-case UUID`);

    const sealed = decodeBase64(record.sealed);
    if (sealed === null) return badRequest(`${at}.sealed is not base64`);
    const framing = checkSealed(sealed);
    if (framing !== null) return { code: framing.code, message: `${at}: ${framing.message}` };

    decoded.push({ ...record, hlc: { ...hlc }, sealed });
  }
  return decoded;
}

/** Narrowing helper for `validatePushBatch`'s result. */
export function isInvalid(value: unknown): value is Invalid {
  return typeof value === "object" && value !== null && "code" in value && "message" in value;
}
