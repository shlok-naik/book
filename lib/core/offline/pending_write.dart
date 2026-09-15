/// One Supabase write made while the backend was unreachable, waiting in
/// the `PendingWriteQueue` to be replayed.
///
/// Deliberately a *description* of the request rather than a closure — it
/// has to survive the app being killed — and deliberately generic (a
/// table, a row, the column values) rather than one type per command: the
/// repositories already express every shelf write as exactly this shape,
/// so replaying one is sending the same request later.
///
/// Every queued write is an absolute "set these columns" or "delete this
/// row", never a relative change, which is what makes replaying them in
/// order safe: the final state is whatever the reader did last.
sealed class PendingWrite {
  const PendingWrite({required this.id, required this.createdAt});

  /// Unique within the queue; for log lines and removal.
  final String id;

  /// When the reader made the change (UTC).
  final DateTime createdAt;

  Map<String, Object?> toJson();

  /// Null for a stored entry this build doesn't understand (written by a
  /// newer build, or corrupted) — the queue skips it rather than failing.
  static PendingWrite? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final created = DateTime.tryParse('${json['created_at']}');
    if (id is! String || created == null) return null;
    final table = json['table'];
    switch (json['op']) {
      case 'update':
        final rowId = json['row_id'];
        final values = json['values'];
        if (table is! String || rowId is! String || values is! Map) {
          return null;
        }
        return PendingUpdate(
          id: id,
          createdAt: created,
          table: table,
          rowId: rowId,
          values: Map<String, Object?>.from(values),
        );
      case 'insert':
        final values = json['values'];
        if (table is! String || values is! Map) return null;
        return PendingInsert(
          id: id,
          createdAt: created,
          table: table,
          values: Map<String, Object?>.from(values),
        );
      case 'delete':
        final column = json['column'];
        final value = json['value'];
        if (table is! String || column is! String || value is! String) {
          return null;
        }
        return PendingDelete(
          id: id,
          createdAt: created,
          table: table,
          column: column,
          value: value,
        );
      case 'rpc':
        final function = json['function'];
        final params = json['params'];
        if (function is! String || params is! Map) return null;
        return PendingRpc(
          id: id,
          createdAt: created,
          function: function,
          params: Map<String, Object?>.from(params),
        );
    }
    return null;
  }
}

/// `update [table] set [values] where id = [rowId]`.
class PendingUpdate extends PendingWrite {
  const PendingUpdate({
    required super.id,
    required super.createdAt,
    required this.table,
    required this.rowId,
    required this.values,
  });

  final String table;
  final String rowId;
  final Map<String, Object?> values;

  /// This update with [later]'s columns laid over it — see
  /// `PendingWriteQueue.enqueue` on when two updates may be merged.
  PendingUpdate mergedWith(PendingUpdate later) => PendingUpdate(
    id: id,
    createdAt: createdAt,
    table: table,
    rowId: rowId,
    values: {...values, ...later.values},
  );

  @override
  Map<String, Object?> toJson() => {
    'op': 'update',
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'table': table,
    'row_id': rowId,
    'values': values,
  };
}

/// `insert into [table] [values]`.
class PendingInsert extends PendingWrite {
  const PendingInsert({
    required super.id,
    required super.createdAt,
    required this.table,
    required this.values,
  });

  final String table;
  final Map<String, Object?> values;

  @override
  Map<String, Object?> toJson() => {
    'op': 'insert',
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'table': table,
    'values': values,
  };
}

/// `delete from [table] where [column] = [value]`.
class PendingDelete extends PendingWrite {
  const PendingDelete({
    required super.id,
    required super.createdAt,
    required this.table,
    required this.column,
    required this.value,
  });

  final String table;
  final String column;
  final String value;

  @override
  Map<String, Object?> toJson() => {
    'op': 'delete',
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'table': table,
    'column': column,
    'value': value,
  };
}

/// A Postgres function call — `set_shelf_order`, today.
class PendingRpc extends PendingWrite {
  const PendingRpc({
    required super.id,
    required super.createdAt,
    required this.function,
    required this.params,
  });

  final String function;
  final Map<String, Object?> params;

  @override
  Map<String, Object?> toJson() => {
    'op': 'rpc',
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'function': function,
    'params': params,
  };
}
