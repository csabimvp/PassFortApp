import GRDB

extension VaultDatabase {
  /// Schema v2 (M5 sync, `m5-sync.md` A.5): the full HLC and the sync bookkeeping on every record.
  ///
  /// **Not a format change:** no sealed byte changes, `schema_version` stays 1, nothing is
  /// re-sealed, and no column the manifest MAC covers (`uuid`, `version`, `sealed`) is touched --
  /// a migrated vault still verifies against its stored MAC.
  ///
  /// - `hlc_counter`, `hlc_device`: the rest of the HLC whose wall time `updated_at` already
  ///   holds. v1 rows were single-device, so counter 0 and the all-zero device is exactly what
  ///   they meant.
  /// - `synced_version`: the version the server last confirmed; `NULL` = never on the server.
  ///   A row is **dirty** when `synced_version IS NULL OR synced_version != version`, so every
  ///   pre-sync row starts dirty -- enabling sync pushes everything, which is right.
  /// - `synced_seq`: the server `seq` of that version.
  static func migrateV2Sync(_ db: Database) throws {
    try db.execute(
      sql: """
        ALTER TABLE records ADD COLUMN hlc_counter    INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE records ADD COLUMN hlc_device     BLOB    NOT NULL DEFAULT x'00000000000000000000000000000000';
        ALTER TABLE records ADD COLUMN synced_version INTEGER;
        ALTER TABLE records ADD COLUMN synced_seq     INTEGER;
        """)
  }
}
