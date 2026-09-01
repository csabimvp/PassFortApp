import GRDB

extension VaultDatabase {
  /// Forward-only. GRDB runs each migration once, in its own transaction, and
  /// records the names it applied. A schema change is always a *new*
  /// `registerMigration("vN")` -- never an edit to one that has shipped (§8.2).
  ///
  /// `eraseDatabaseOnSchemaChange` stays `false`: dropping and rebuilding on a
  /// schema mismatch is a convenience for throwaway app data and data loss for a
  /// password vault.
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.eraseDatabaseOnSchemaChange = false

    migrator.registerMigration("v1") { db in
      try db.create(table: "records") { t in
        t.column("uuid", .blob).primaryKey().notNull()  // 16 raw bytes
        t.column("version", .integer).notNull()  // monotonic; bound into the AAD
        t.column("sealed", .blob).notNull()  // nonce ‖ ciphertext ‖ tag
        t.column("is_deleted", .integer).notNull().defaults(to: 0)
        t.column("updated_at", .integer).notNull()  // HLC-encoded
        t.column("idx_title", .blob)  // blind index -- M5
        t.column("idx_url", .blob)
      }

      // Typed key/value store (§7.4): header, manifest_mac, vault_version,
      // kdf_calibration.
      try db.create(table: "vault_meta") { t in
        t.column("key", .text).primaryKey().notNull()
        t.column("value", .blob).notNull()
      }

      // One vault-wide value for M2 (§7.1): a format/schema change re-seals every
      // record in a migration and steps this number, rather than a per-row column.
      try db.create(table: "schema_version") { t in
        t.column("version", .integer).notNull()
      }
      try db.execute(sql: "INSERT INTO schema_version (version) VALUES (1)")
    }

    return migrator
  }
}
