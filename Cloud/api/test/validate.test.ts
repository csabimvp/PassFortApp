// validate.ts: framing, sizes, UUIDs and version rules (m5-sync.md Phase 2 checkpoint).
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { describe, it } from "node:test";
import {
  MAX_PUSH_RECORDS,
  MAX_SEALED_BYTES,
  checkSealed,
  decodeBase64,
  isInvalid,
  isUuid,
  validatePushBatch,
  type PushWire,
} from "../src/lib/validate.js";

const push = (overrides: Partial<PushWire> = {}): PushWire => ({
  id: randomUUID(),
  baseVersion: 0,
  version: 1,
  hlc: { wallMillis: Date.now(), counter: 0, deviceId: randomUUID() },
  sealed: randomBytes(296).toString("base64"),
  isDeleted: false,
  ...overrides,
});

const codeOf = (records: PushWire[]): string | null => {
  const result = validatePushBatch(records);
  return isInvalid(result) ? result.code : null;
};

describe("checkSealed", () => {
  it("accepts 296 bytes and rejects 295 and 297 (framing)", () => {
    assert.equal(checkSealed(new Uint8Array(296)), null);
    assert.equal(checkSealed(new Uint8Array(295))?.code, "bad_request");
    assert.equal(checkSealed(new Uint8Array(297))?.code, "bad_request");
  });

  it("accepts the 65,320-byte cap and calls anything larger too_large", () => {
    assert.equal(checkSealed(new Uint8Array(MAX_SEALED_BYTES)), null);
    assert.equal(checkSealed(new Uint8Array(65_321))?.code, "too_large");
    assert.equal(checkSealed(new Uint8Array(65_576))?.code, "too_large"); // the next bucket
  });
});

describe("scalars", () => {
  it("takes lower-case UUIDs only", () => {
    assert.ok(isUuid(randomUUID()));
    assert.ok(!isUuid(randomUUID().toUpperCase()));
    assert.ok(!isUuid("not-a-uuid"));
  });

  it("decodes strict padded base64 and refuses the rest", () => {
    assert.deepEqual(decodeBase64("AAEC"), new Uint8Array([0, 1, 2]));
    assert.equal(decodeBase64("AAE"), null); // unpadded
    assert.equal(decodeBase64("AA-_"), null); // url-safe alphabet
  });
});

describe("validatePushBatch", () => {
  it("decodes a good batch", () => {
    const wire = push();
    const result = validatePushBatch([wire]);
    assert.ok(!isInvalid(result));
    assert.equal(result[0]?.sealed.length, 296);
  });

  it("refuses an empty batch and one record over the limit", () => {
    assert.equal(codeOf([]), "bad_request");
    assert.equal(codeOf(Array.from({ length: MAX_PUSH_RECORDS }, () => push())), null);
    assert.equal(codeOf(Array.from({ length: MAX_PUSH_RECORDS + 1 }, () => push())), "bad_request");
  });

  it("refuses version <= baseVersion, duplicates, bad ids and bad HLCs", () => {
    assert.equal(codeOf([push({ baseVersion: 3, version: 3 })]), "bad_request");
    const twice = push();
    assert.equal(codeOf([twice, { ...twice }]), "bad_request");
    assert.equal(codeOf([push({ id: "x" })]), "bad_request");
    assert.equal(
      codeOf([push({ hlc: { wallMillis: -1, counter: 0, deviceId: randomUUID() } })]),
      "bad_request",
    );
    assert.equal(codeOf([push({ baseVersion: 1.5, version: 2 })]), "bad_request");
  });

  it("refuses bad base64 and bad framing, and reports oversize as too_large", () => {
    assert.equal(codeOf([push({ sealed: "!!!!" })]), "bad_request");
    assert.equal(codeOf([push({ sealed: randomBytes(297).toString("base64") })]), "bad_request");
    assert.equal(codeOf([push({ sealed: randomBytes(65_576).toString("base64") })]), "too_large");
  });

  it("never echoes the input in a message", () => {
    const marker = "bWFya2VyLXZhbHVl"; // valid base64, badly framed
    const result = validatePushBatch([push({ sealed: marker })]);
    assert.ok(isInvalid(result));
    assert.ok(!result.message.includes(marker));
  });
});
