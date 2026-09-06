// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salinan_db.dart';

// ignore_for_file: type=lint
class $SalinanTable extends Salinan
    with TableInfo<$SalinanTable, BarisSalinan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalinanTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kunciMeta = const VerificationMeta('kunci');
  @override
  late final GeneratedColumn<String> kunci = GeneratedColumn<String>(
    'kunci',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ditarikPadaMeta = const VerificationMeta(
    'ditarikPada',
  );
  @override
  late final GeneratedColumn<DateTime> ditarikPada = GeneratedColumn<DateTime>(
    'ditarik_pada',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kunci, json, ditarikPada];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'salinan';
  @override
  VerificationContext validateIntegrity(
    Insertable<BarisSalinan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kunci')) {
      context.handle(
        _kunciMeta,
        kunci.isAcceptableOrUnknown(data['kunci']!, _kunciMeta),
      );
    } else if (isInserting) {
      context.missing(_kunciMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('ditarik_pada')) {
      context.handle(
        _ditarikPadaMeta,
        ditarikPada.isAcceptableOrUnknown(
          data['ditarik_pada']!,
          _ditarikPadaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ditarikPadaMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kunci};
  @override
  BarisSalinan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BarisSalinan(
      kunci: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kunci'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      ditarikPada: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ditarik_pada'],
      )!,
    );
  }

  @override
  $SalinanTable createAlias(String alias) {
    return $SalinanTable(attachedDatabase, alias);
  }
}

class BarisSalinan extends DataClass implements Insertable<BarisSalinan> {
  final String kunci;
  final String json;
  final DateTime ditarikPada;
  const BarisSalinan({
    required this.kunci,
    required this.json,
    required this.ditarikPada,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kunci'] = Variable<String>(kunci);
    map['json'] = Variable<String>(json);
    map['ditarik_pada'] = Variable<DateTime>(ditarikPada);
    return map;
  }

  SalinanCompanion toCompanion(bool nullToAbsent) {
    return SalinanCompanion(
      kunci: Value(kunci),
      json: Value(json),
      ditarikPada: Value(ditarikPada),
    );
  }

  factory BarisSalinan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BarisSalinan(
      kunci: serializer.fromJson<String>(json['kunci']),
      json: serializer.fromJson<String>(json['json']),
      ditarikPada: serializer.fromJson<DateTime>(json['ditarikPada']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kunci': serializer.toJson<String>(kunci),
      'json': serializer.toJson<String>(json),
      'ditarikPada': serializer.toJson<DateTime>(ditarikPada),
    };
  }

  BarisSalinan copyWith({String? kunci, String? json, DateTime? ditarikPada}) =>
      BarisSalinan(
        kunci: kunci ?? this.kunci,
        json: json ?? this.json,
        ditarikPada: ditarikPada ?? this.ditarikPada,
      );
  BarisSalinan copyWithCompanion(SalinanCompanion data) {
    return BarisSalinan(
      kunci: data.kunci.present ? data.kunci.value : this.kunci,
      json: data.json.present ? data.json.value : this.json,
      ditarikPada: data.ditarikPada.present
          ? data.ditarikPada.value
          : this.ditarikPada,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BarisSalinan(')
          ..write('kunci: $kunci, ')
          ..write('json: $json, ')
          ..write('ditarikPada: $ditarikPada')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kunci, json, ditarikPada);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BarisSalinan &&
          other.kunci == this.kunci &&
          other.json == this.json &&
          other.ditarikPada == this.ditarikPada);
}

class SalinanCompanion extends UpdateCompanion<BarisSalinan> {
  final Value<String> kunci;
  final Value<String> json;
  final Value<DateTime> ditarikPada;
  final Value<int> rowid;
  const SalinanCompanion({
    this.kunci = const Value.absent(),
    this.json = const Value.absent(),
    this.ditarikPada = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalinanCompanion.insert({
    required String kunci,
    required String json,
    required DateTime ditarikPada,
    this.rowid = const Value.absent(),
  }) : kunci = Value(kunci),
       json = Value(json),
       ditarikPada = Value(ditarikPada);
  static Insertable<BarisSalinan> custom({
    Expression<String>? kunci,
    Expression<String>? json,
    Expression<DateTime>? ditarikPada,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kunci != null) 'kunci': kunci,
      if (json != null) 'json': json,
      if (ditarikPada != null) 'ditarik_pada': ditarikPada,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalinanCompanion copyWith({
    Value<String>? kunci,
    Value<String>? json,
    Value<DateTime>? ditarikPada,
    Value<int>? rowid,
  }) {
    return SalinanCompanion(
      kunci: kunci ?? this.kunci,
      json: json ?? this.json,
      ditarikPada: ditarikPada ?? this.ditarikPada,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kunci.present) {
      map['kunci'] = Variable<String>(kunci.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (ditarikPada.present) {
      map['ditarik_pada'] = Variable<DateTime>(ditarikPada.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalinanCompanion(')
          ..write('kunci: $kunci, ')
          ..write('json: $json, ')
          ..write('ditarikPada: $ditarikPada, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SalinanDb extends GeneratedDatabase {
  _$SalinanDb(QueryExecutor e) : super(e);
  $SalinanDbManager get managers => $SalinanDbManager(this);
  late final $SalinanTable salinan = $SalinanTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [salinan];
}

typedef $$SalinanTableCreateCompanionBuilder =
    SalinanCompanion Function({
      required String kunci,
      required String json,
      required DateTime ditarikPada,
      Value<int> rowid,
    });
typedef $$SalinanTableUpdateCompanionBuilder =
    SalinanCompanion Function({
      Value<String> kunci,
      Value<String> json,
      Value<DateTime> ditarikPada,
      Value<int> rowid,
    });

class $$SalinanTableFilterComposer
    extends Composer<_$SalinanDb, $SalinanTable> {
  $$SalinanTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kunci => $composableBuilder(
    column: $table.kunci,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ditarikPada => $composableBuilder(
    column: $table.ditarikPada,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SalinanTableOrderingComposer
    extends Composer<_$SalinanDb, $SalinanTable> {
  $$SalinanTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kunci => $composableBuilder(
    column: $table.kunci,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ditarikPada => $composableBuilder(
    column: $table.ditarikPada,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SalinanTableAnnotationComposer
    extends Composer<_$SalinanDb, $SalinanTable> {
  $$SalinanTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kunci =>
      $composableBuilder(column: $table.kunci, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get ditarikPada => $composableBuilder(
    column: $table.ditarikPada,
    builder: (column) => column,
  );
}

class $$SalinanTableTableManager
    extends
        RootTableManager<
          _$SalinanDb,
          $SalinanTable,
          BarisSalinan,
          $$SalinanTableFilterComposer,
          $$SalinanTableOrderingComposer,
          $$SalinanTableAnnotationComposer,
          $$SalinanTableCreateCompanionBuilder,
          $$SalinanTableUpdateCompanionBuilder,
          (
            BarisSalinan,
            BaseReferences<_$SalinanDb, $SalinanTable, BarisSalinan>,
          ),
          BarisSalinan,
          PrefetchHooks Function()
        > {
  $$SalinanTableTableManager(_$SalinanDb db, $SalinanTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalinanTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalinanTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalinanTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kunci = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> ditarikPada = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalinanCompanion(
                kunci: kunci,
                json: json,
                ditarikPada: ditarikPada,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kunci,
                required String json,
                required DateTime ditarikPada,
                Value<int> rowid = const Value.absent(),
              }) => SalinanCompanion.insert(
                kunci: kunci,
                json: json,
                ditarikPada: ditarikPada,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SalinanTable, BarisSalinan>(table),
                  BaseReferences<_$SalinanDb, $SalinanTable, BarisSalinan>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SalinanTableProcessedTableManager =
    ProcessedTableManager<
      _$SalinanDb,
      $SalinanTable,
      BarisSalinan,
      $$SalinanTableFilterComposer,
      $$SalinanTableOrderingComposer,
      $$SalinanTableAnnotationComposer,
      $$SalinanTableCreateCompanionBuilder,
      $$SalinanTableUpdateCompanionBuilder,
      (BarisSalinan, BaseReferences<_$SalinanDb, $SalinanTable, BarisSalinan>),
      BarisSalinan,
      PrefetchHooks Function()
    >;

class $SalinanDbManager {
  final _$SalinanDb _db;
  $SalinanDbManager(this._db);
  $$SalinanTableTableManager get salinan =>
      $$SalinanTableTableManager(_db, _db.salinan);
}
