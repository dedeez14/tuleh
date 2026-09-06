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

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, BarisOutbox> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urutMeta = const VerificationMeta('urut');
  @override
  late final GeneratedColumn<int> urut = GeneratedColumn<int>(
    'urut',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _clientRefMeta = const VerificationMeta(
    'clientRef',
  );
  @override
  late final GeneratedColumn<String> clientRef = GeneratedColumn<String>(
    'client_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _jenisMeta = const VerificationMeta('jenis');
  @override
  late final GeneratedColumn<String> jenis = GeneratedColumn<String>(
    'jenis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokoIdMeta = const VerificationMeta('tokoId');
  @override
  late final GeneratedColumn<String> tokoId = GeneratedColumn<String>(
    'toko_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _percobaanMeta = const VerificationMeta(
    'percobaan',
  );
  @override
  late final GeneratedColumn<int> percobaan = GeneratedColumn<int>(
    'percobaan',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cobaLagiSetelahMeta = const VerificationMeta(
    'cobaLagiSetelah',
  );
  @override
  late final GeneratedColumn<DateTime> cobaLagiSetelah =
      GeneratedColumn<DateTime>(
        'coba_lagi_setelah',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('MENUNGGU'),
  );
  static const VerificationMeta _galatTerakhirMeta = const VerificationMeta(
    'galatTerakhir',
  );
  @override
  late final GeneratedColumn<String> galatTerakhir = GeneratedColumn<String>(
    'galat_terakhir',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasilJsonMeta = const VerificationMeta(
    'hasilJson',
  );
  @override
  late final GeneratedColumn<String> hasilJson = GeneratedColumn<String>(
    'hasil_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dibuatMeta = const VerificationMeta('dibuat');
  @override
  late final GeneratedColumn<DateTime> dibuat = GeneratedColumn<DateTime>(
    'dibuat',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    urut,
    clientRef,
    jenis,
    tokoId,
    path,
    bodyJson,
    percobaan,
    cobaLagiSetelah,
    status,
    galatTerakhir,
    hasilJson,
    dibuat,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<BarisOutbox> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('urut')) {
      context.handle(
        _urutMeta,
        urut.isAcceptableOrUnknown(data['urut']!, _urutMeta),
      );
    }
    if (data.containsKey('client_ref')) {
      context.handle(
        _clientRefMeta,
        clientRef.isAcceptableOrUnknown(data['client_ref']!, _clientRefMeta),
      );
    } else if (isInserting) {
      context.missing(_clientRefMeta);
    }
    if (data.containsKey('jenis')) {
      context.handle(
        _jenisMeta,
        jenis.isAcceptableOrUnknown(data['jenis']!, _jenisMeta),
      );
    } else if (isInserting) {
      context.missing(_jenisMeta);
    }
    if (data.containsKey('toko_id')) {
      context.handle(
        _tokoIdMeta,
        tokoId.isAcceptableOrUnknown(data['toko_id']!, _tokoIdMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('percobaan')) {
      context.handle(
        _percobaanMeta,
        percobaan.isAcceptableOrUnknown(data['percobaan']!, _percobaanMeta),
      );
    }
    if (data.containsKey('coba_lagi_setelah')) {
      context.handle(
        _cobaLagiSetelahMeta,
        cobaLagiSetelah.isAcceptableOrUnknown(
          data['coba_lagi_setelah']!,
          _cobaLagiSetelahMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('galat_terakhir')) {
      context.handle(
        _galatTerakhirMeta,
        galatTerakhir.isAcceptableOrUnknown(
          data['galat_terakhir']!,
          _galatTerakhirMeta,
        ),
      );
    }
    if (data.containsKey('hasil_json')) {
      context.handle(
        _hasilJsonMeta,
        hasilJson.isAcceptableOrUnknown(data['hasil_json']!, _hasilJsonMeta),
      );
    }
    if (data.containsKey('dibuat')) {
      context.handle(
        _dibuatMeta,
        dibuat.isAcceptableOrUnknown(data['dibuat']!, _dibuatMeta),
      );
    } else if (isInserting) {
      context.missing(_dibuatMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {urut};
  @override
  BarisOutbox map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BarisOutbox(
      urut: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}urut'],
      )!,
      clientRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_ref'],
      )!,
      jenis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jenis'],
      )!,
      tokoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toko_id'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      percobaan: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}percobaan'],
      )!,
      cobaLagiSetelah: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}coba_lagi_setelah'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      galatTerakhir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}galat_terakhir'],
      ),
      hasilJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hasil_json'],
      ),
      dibuat: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dibuat'],
      )!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class BarisOutbox extends DataClass implements Insertable<BarisOutbox> {
  final int urut;
  final String clientRef;
  final String jenis;
  final String? tokoId;
  final String path;
  final String bodyJson;
  final int percobaan;
  final DateTime? cobaLagiSetelah;
  final String status;
  final String? galatTerakhir;
  final String? hasilJson;
  final DateTime dibuat;
  const BarisOutbox({
    required this.urut,
    required this.clientRef,
    required this.jenis,
    this.tokoId,
    required this.path,
    required this.bodyJson,
    required this.percobaan,
    this.cobaLagiSetelah,
    required this.status,
    this.galatTerakhir,
    this.hasilJson,
    required this.dibuat,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['urut'] = Variable<int>(urut);
    map['client_ref'] = Variable<String>(clientRef);
    map['jenis'] = Variable<String>(jenis);
    if (!nullToAbsent || tokoId != null) {
      map['toko_id'] = Variable<String>(tokoId);
    }
    map['path'] = Variable<String>(path);
    map['body_json'] = Variable<String>(bodyJson);
    map['percobaan'] = Variable<int>(percobaan);
    if (!nullToAbsent || cobaLagiSetelah != null) {
      map['coba_lagi_setelah'] = Variable<DateTime>(cobaLagiSetelah);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || galatTerakhir != null) {
      map['galat_terakhir'] = Variable<String>(galatTerakhir);
    }
    if (!nullToAbsent || hasilJson != null) {
      map['hasil_json'] = Variable<String>(hasilJson);
    }
    map['dibuat'] = Variable<DateTime>(dibuat);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      urut: Value(urut),
      clientRef: Value(clientRef),
      jenis: Value(jenis),
      tokoId: tokoId == null && nullToAbsent
          ? const Value.absent()
          : Value(tokoId),
      path: Value(path),
      bodyJson: Value(bodyJson),
      percobaan: Value(percobaan),
      cobaLagiSetelah: cobaLagiSetelah == null && nullToAbsent
          ? const Value.absent()
          : Value(cobaLagiSetelah),
      status: Value(status),
      galatTerakhir: galatTerakhir == null && nullToAbsent
          ? const Value.absent()
          : Value(galatTerakhir),
      hasilJson: hasilJson == null && nullToAbsent
          ? const Value.absent()
          : Value(hasilJson),
      dibuat: Value(dibuat),
    );
  }

  factory BarisOutbox.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BarisOutbox(
      urut: serializer.fromJson<int>(json['urut']),
      clientRef: serializer.fromJson<String>(json['clientRef']),
      jenis: serializer.fromJson<String>(json['jenis']),
      tokoId: serializer.fromJson<String?>(json['tokoId']),
      path: serializer.fromJson<String>(json['path']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      percobaan: serializer.fromJson<int>(json['percobaan']),
      cobaLagiSetelah: serializer.fromJson<DateTime?>(json['cobaLagiSetelah']),
      status: serializer.fromJson<String>(json['status']),
      galatTerakhir: serializer.fromJson<String?>(json['galatTerakhir']),
      hasilJson: serializer.fromJson<String?>(json['hasilJson']),
      dibuat: serializer.fromJson<DateTime>(json['dibuat']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'urut': serializer.toJson<int>(urut),
      'clientRef': serializer.toJson<String>(clientRef),
      'jenis': serializer.toJson<String>(jenis),
      'tokoId': serializer.toJson<String?>(tokoId),
      'path': serializer.toJson<String>(path),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'percobaan': serializer.toJson<int>(percobaan),
      'cobaLagiSetelah': serializer.toJson<DateTime?>(cobaLagiSetelah),
      'status': serializer.toJson<String>(status),
      'galatTerakhir': serializer.toJson<String?>(galatTerakhir),
      'hasilJson': serializer.toJson<String?>(hasilJson),
      'dibuat': serializer.toJson<DateTime>(dibuat),
    };
  }

  BarisOutbox copyWith({
    int? urut,
    String? clientRef,
    String? jenis,
    Value<String?> tokoId = const Value.absent(),
    String? path,
    String? bodyJson,
    int? percobaan,
    Value<DateTime?> cobaLagiSetelah = const Value.absent(),
    String? status,
    Value<String?> galatTerakhir = const Value.absent(),
    Value<String?> hasilJson = const Value.absent(),
    DateTime? dibuat,
  }) => BarisOutbox(
    urut: urut ?? this.urut,
    clientRef: clientRef ?? this.clientRef,
    jenis: jenis ?? this.jenis,
    tokoId: tokoId.present ? tokoId.value : this.tokoId,
    path: path ?? this.path,
    bodyJson: bodyJson ?? this.bodyJson,
    percobaan: percobaan ?? this.percobaan,
    cobaLagiSetelah: cobaLagiSetelah.present
        ? cobaLagiSetelah.value
        : this.cobaLagiSetelah,
    status: status ?? this.status,
    galatTerakhir: galatTerakhir.present
        ? galatTerakhir.value
        : this.galatTerakhir,
    hasilJson: hasilJson.present ? hasilJson.value : this.hasilJson,
    dibuat: dibuat ?? this.dibuat,
  );
  BarisOutbox copyWithCompanion(OutboxCompanion data) {
    return BarisOutbox(
      urut: data.urut.present ? data.urut.value : this.urut,
      clientRef: data.clientRef.present ? data.clientRef.value : this.clientRef,
      jenis: data.jenis.present ? data.jenis.value : this.jenis,
      tokoId: data.tokoId.present ? data.tokoId.value : this.tokoId,
      path: data.path.present ? data.path.value : this.path,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      percobaan: data.percobaan.present ? data.percobaan.value : this.percobaan,
      cobaLagiSetelah: data.cobaLagiSetelah.present
          ? data.cobaLagiSetelah.value
          : this.cobaLagiSetelah,
      status: data.status.present ? data.status.value : this.status,
      galatTerakhir: data.galatTerakhir.present
          ? data.galatTerakhir.value
          : this.galatTerakhir,
      hasilJson: data.hasilJson.present ? data.hasilJson.value : this.hasilJson,
      dibuat: data.dibuat.present ? data.dibuat.value : this.dibuat,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BarisOutbox(')
          ..write('urut: $urut, ')
          ..write('clientRef: $clientRef, ')
          ..write('jenis: $jenis, ')
          ..write('tokoId: $tokoId, ')
          ..write('path: $path, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('percobaan: $percobaan, ')
          ..write('cobaLagiSetelah: $cobaLagiSetelah, ')
          ..write('status: $status, ')
          ..write('galatTerakhir: $galatTerakhir, ')
          ..write('hasilJson: $hasilJson, ')
          ..write('dibuat: $dibuat')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    urut,
    clientRef,
    jenis,
    tokoId,
    path,
    bodyJson,
    percobaan,
    cobaLagiSetelah,
    status,
    galatTerakhir,
    hasilJson,
    dibuat,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BarisOutbox &&
          other.urut == this.urut &&
          other.clientRef == this.clientRef &&
          other.jenis == this.jenis &&
          other.tokoId == this.tokoId &&
          other.path == this.path &&
          other.bodyJson == this.bodyJson &&
          other.percobaan == this.percobaan &&
          other.cobaLagiSetelah == this.cobaLagiSetelah &&
          other.status == this.status &&
          other.galatTerakhir == this.galatTerakhir &&
          other.hasilJson == this.hasilJson &&
          other.dibuat == this.dibuat);
}

class OutboxCompanion extends UpdateCompanion<BarisOutbox> {
  final Value<int> urut;
  final Value<String> clientRef;
  final Value<String> jenis;
  final Value<String?> tokoId;
  final Value<String> path;
  final Value<String> bodyJson;
  final Value<int> percobaan;
  final Value<DateTime?> cobaLagiSetelah;
  final Value<String> status;
  final Value<String?> galatTerakhir;
  final Value<String?> hasilJson;
  final Value<DateTime> dibuat;
  const OutboxCompanion({
    this.urut = const Value.absent(),
    this.clientRef = const Value.absent(),
    this.jenis = const Value.absent(),
    this.tokoId = const Value.absent(),
    this.path = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.percobaan = const Value.absent(),
    this.cobaLagiSetelah = const Value.absent(),
    this.status = const Value.absent(),
    this.galatTerakhir = const Value.absent(),
    this.hasilJson = const Value.absent(),
    this.dibuat = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.urut = const Value.absent(),
    required String clientRef,
    required String jenis,
    this.tokoId = const Value.absent(),
    required String path,
    required String bodyJson,
    this.percobaan = const Value.absent(),
    this.cobaLagiSetelah = const Value.absent(),
    this.status = const Value.absent(),
    this.galatTerakhir = const Value.absent(),
    this.hasilJson = const Value.absent(),
    required DateTime dibuat,
  }) : clientRef = Value(clientRef),
       jenis = Value(jenis),
       path = Value(path),
       bodyJson = Value(bodyJson),
       dibuat = Value(dibuat);
  static Insertable<BarisOutbox> custom({
    Expression<int>? urut,
    Expression<String>? clientRef,
    Expression<String>? jenis,
    Expression<String>? tokoId,
    Expression<String>? path,
    Expression<String>? bodyJson,
    Expression<int>? percobaan,
    Expression<DateTime>? cobaLagiSetelah,
    Expression<String>? status,
    Expression<String>? galatTerakhir,
    Expression<String>? hasilJson,
    Expression<DateTime>? dibuat,
  }) {
    return RawValuesInsertable({
      if (urut != null) 'urut': urut,
      if (clientRef != null) 'client_ref': clientRef,
      if (jenis != null) 'jenis': jenis,
      if (tokoId != null) 'toko_id': tokoId,
      if (path != null) 'path': path,
      if (bodyJson != null) 'body_json': bodyJson,
      if (percobaan != null) 'percobaan': percobaan,
      if (cobaLagiSetelah != null) 'coba_lagi_setelah': cobaLagiSetelah,
      if (status != null) 'status': status,
      if (galatTerakhir != null) 'galat_terakhir': galatTerakhir,
      if (hasilJson != null) 'hasil_json': hasilJson,
      if (dibuat != null) 'dibuat': dibuat,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? urut,
    Value<String>? clientRef,
    Value<String>? jenis,
    Value<String?>? tokoId,
    Value<String>? path,
    Value<String>? bodyJson,
    Value<int>? percobaan,
    Value<DateTime?>? cobaLagiSetelah,
    Value<String>? status,
    Value<String?>? galatTerakhir,
    Value<String?>? hasilJson,
    Value<DateTime>? dibuat,
  }) {
    return OutboxCompanion(
      urut: urut ?? this.urut,
      clientRef: clientRef ?? this.clientRef,
      jenis: jenis ?? this.jenis,
      tokoId: tokoId ?? this.tokoId,
      path: path ?? this.path,
      bodyJson: bodyJson ?? this.bodyJson,
      percobaan: percobaan ?? this.percobaan,
      cobaLagiSetelah: cobaLagiSetelah ?? this.cobaLagiSetelah,
      status: status ?? this.status,
      galatTerakhir: galatTerakhir ?? this.galatTerakhir,
      hasilJson: hasilJson ?? this.hasilJson,
      dibuat: dibuat ?? this.dibuat,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (urut.present) {
      map['urut'] = Variable<int>(urut.value);
    }
    if (clientRef.present) {
      map['client_ref'] = Variable<String>(clientRef.value);
    }
    if (jenis.present) {
      map['jenis'] = Variable<String>(jenis.value);
    }
    if (tokoId.present) {
      map['toko_id'] = Variable<String>(tokoId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (percobaan.present) {
      map['percobaan'] = Variable<int>(percobaan.value);
    }
    if (cobaLagiSetelah.present) {
      map['coba_lagi_setelah'] = Variable<DateTime>(cobaLagiSetelah.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (galatTerakhir.present) {
      map['galat_terakhir'] = Variable<String>(galatTerakhir.value);
    }
    if (hasilJson.present) {
      map['hasil_json'] = Variable<String>(hasilJson.value);
    }
    if (dibuat.present) {
      map['dibuat'] = Variable<DateTime>(dibuat.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('urut: $urut, ')
          ..write('clientRef: $clientRef, ')
          ..write('jenis: $jenis, ')
          ..write('tokoId: $tokoId, ')
          ..write('path: $path, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('percobaan: $percobaan, ')
          ..write('cobaLagiSetelah: $cobaLagiSetelah, ')
          ..write('status: $status, ')
          ..write('galatTerakhir: $galatTerakhir, ')
          ..write('hasilJson: $hasilJson, ')
          ..write('dibuat: $dibuat')
          ..write(')'))
        .toString();
  }
}

class $TransaksiLokalTable extends TransaksiLokal
    with TableInfo<$TransaksiLokalTable, BarisTransaksiLokal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransaksiLokalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientRefMeta = const VerificationMeta(
    'clientRef',
  );
  @override
  late final GeneratedColumn<String> clientRef = GeneratedColumn<String>(
    'client_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokoIdMeta = const VerificationMeta('tokoId');
  @override
  late final GeneratedColumn<String> tokoId = GeneratedColumn<String>(
    'toko_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nomorLokalMeta = const VerificationMeta(
    'nomorLokal',
  );
  @override
  late final GeneratedColumn<String> nomorLokal = GeneratedColumn<String>(
    'nomor_lokal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nomorServerMeta = const VerificationMeta(
    'nomorServer',
  );
  @override
  late final GeneratedColumn<String> nomorServer = GeneratedColumn<String>(
    'nomor_server',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tipePembayaranMeta = const VerificationMeta(
    'tipePembayaran',
  );
  @override
  late final GeneratedColumn<String> tipePembayaran = GeneratedColumn<String>(
    'tipe_pembayaran',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grandTotalMeta = const VerificationMeta(
    'grandTotal',
  );
  @override
  late final GeneratedColumn<double> grandTotal = GeneratedColumn<double>(
    'grand_total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dibayarMeta = const VerificationMeta(
    'dibayar',
  );
  @override
  late final GeneratedColumn<double> dibayar = GeneratedColumn<double>(
    'dibayar',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _waktuKlienMeta = const VerificationMeta(
    'waktuKlien',
  );
  @override
  late final GeneratedColumn<DateTime> waktuKlien = GeneratedColumn<DateTime>(
    'waktu_klien',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strukJsonMeta = const VerificationMeta(
    'strukJson',
  );
  @override
  late final GeneratedColumn<String> strukJson = GeneratedColumn<String>(
    'struk_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientRef,
    tokoId,
    nomorLokal,
    nomorServer,
    tipePembayaran,
    grandTotal,
    dibayar,
    waktuKlien,
    strukJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaksi_lokal';
  @override
  VerificationContext validateIntegrity(
    Insertable<BarisTransaksiLokal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_ref')) {
      context.handle(
        _clientRefMeta,
        clientRef.isAcceptableOrUnknown(data['client_ref']!, _clientRefMeta),
      );
    } else if (isInserting) {
      context.missing(_clientRefMeta);
    }
    if (data.containsKey('toko_id')) {
      context.handle(
        _tokoIdMeta,
        tokoId.isAcceptableOrUnknown(data['toko_id']!, _tokoIdMeta),
      );
    }
    if (data.containsKey('nomor_lokal')) {
      context.handle(
        _nomorLokalMeta,
        nomorLokal.isAcceptableOrUnknown(data['nomor_lokal']!, _nomorLokalMeta),
      );
    } else if (isInserting) {
      context.missing(_nomorLokalMeta);
    }
    if (data.containsKey('nomor_server')) {
      context.handle(
        _nomorServerMeta,
        nomorServer.isAcceptableOrUnknown(
          data['nomor_server']!,
          _nomorServerMeta,
        ),
      );
    }
    if (data.containsKey('tipe_pembayaran')) {
      context.handle(
        _tipePembayaranMeta,
        tipePembayaran.isAcceptableOrUnknown(
          data['tipe_pembayaran']!,
          _tipePembayaranMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tipePembayaranMeta);
    }
    if (data.containsKey('grand_total')) {
      context.handle(
        _grandTotalMeta,
        grandTotal.isAcceptableOrUnknown(data['grand_total']!, _grandTotalMeta),
      );
    } else if (isInserting) {
      context.missing(_grandTotalMeta);
    }
    if (data.containsKey('dibayar')) {
      context.handle(
        _dibayarMeta,
        dibayar.isAcceptableOrUnknown(data['dibayar']!, _dibayarMeta),
      );
    } else if (isInserting) {
      context.missing(_dibayarMeta);
    }
    if (data.containsKey('waktu_klien')) {
      context.handle(
        _waktuKlienMeta,
        waktuKlien.isAcceptableOrUnknown(data['waktu_klien']!, _waktuKlienMeta),
      );
    } else if (isInserting) {
      context.missing(_waktuKlienMeta);
    }
    if (data.containsKey('struk_json')) {
      context.handle(
        _strukJsonMeta,
        strukJson.isAcceptableOrUnknown(data['struk_json']!, _strukJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_strukJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientRef};
  @override
  BarisTransaksiLokal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BarisTransaksiLokal(
      clientRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_ref'],
      )!,
      tokoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toko_id'],
      ),
      nomorLokal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nomor_lokal'],
      )!,
      nomorServer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nomor_server'],
      ),
      tipePembayaran: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tipe_pembayaran'],
      )!,
      grandTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}grand_total'],
      )!,
      dibayar: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dibayar'],
      )!,
      waktuKlien: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}waktu_klien'],
      )!,
      strukJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}struk_json'],
      )!,
    );
  }

  @override
  $TransaksiLokalTable createAlias(String alias) {
    return $TransaksiLokalTable(attachedDatabase, alias);
  }
}

class BarisTransaksiLokal extends DataClass
    implements Insertable<BarisTransaksiLokal> {
  final String clientRef;
  final String? tokoId;
  final String nomorLokal;
  final String? nomorServer;
  final String tipePembayaran;
  final double grandTotal;
  final double dibayar;
  final DateTime waktuKlien;
  final String strukJson;
  const BarisTransaksiLokal({
    required this.clientRef,
    this.tokoId,
    required this.nomorLokal,
    this.nomorServer,
    required this.tipePembayaran,
    required this.grandTotal,
    required this.dibayar,
    required this.waktuKlien,
    required this.strukJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_ref'] = Variable<String>(clientRef);
    if (!nullToAbsent || tokoId != null) {
      map['toko_id'] = Variable<String>(tokoId);
    }
    map['nomor_lokal'] = Variable<String>(nomorLokal);
    if (!nullToAbsent || nomorServer != null) {
      map['nomor_server'] = Variable<String>(nomorServer);
    }
    map['tipe_pembayaran'] = Variable<String>(tipePembayaran);
    map['grand_total'] = Variable<double>(grandTotal);
    map['dibayar'] = Variable<double>(dibayar);
    map['waktu_klien'] = Variable<DateTime>(waktuKlien);
    map['struk_json'] = Variable<String>(strukJson);
    return map;
  }

  TransaksiLokalCompanion toCompanion(bool nullToAbsent) {
    return TransaksiLokalCompanion(
      clientRef: Value(clientRef),
      tokoId: tokoId == null && nullToAbsent
          ? const Value.absent()
          : Value(tokoId),
      nomorLokal: Value(nomorLokal),
      nomorServer: nomorServer == null && nullToAbsent
          ? const Value.absent()
          : Value(nomorServer),
      tipePembayaran: Value(tipePembayaran),
      grandTotal: Value(grandTotal),
      dibayar: Value(dibayar),
      waktuKlien: Value(waktuKlien),
      strukJson: Value(strukJson),
    );
  }

  factory BarisTransaksiLokal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BarisTransaksiLokal(
      clientRef: serializer.fromJson<String>(json['clientRef']),
      tokoId: serializer.fromJson<String?>(json['tokoId']),
      nomorLokal: serializer.fromJson<String>(json['nomorLokal']),
      nomorServer: serializer.fromJson<String?>(json['nomorServer']),
      tipePembayaran: serializer.fromJson<String>(json['tipePembayaran']),
      grandTotal: serializer.fromJson<double>(json['grandTotal']),
      dibayar: serializer.fromJson<double>(json['dibayar']),
      waktuKlien: serializer.fromJson<DateTime>(json['waktuKlien']),
      strukJson: serializer.fromJson<String>(json['strukJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientRef': serializer.toJson<String>(clientRef),
      'tokoId': serializer.toJson<String?>(tokoId),
      'nomorLokal': serializer.toJson<String>(nomorLokal),
      'nomorServer': serializer.toJson<String?>(nomorServer),
      'tipePembayaran': serializer.toJson<String>(tipePembayaran),
      'grandTotal': serializer.toJson<double>(grandTotal),
      'dibayar': serializer.toJson<double>(dibayar),
      'waktuKlien': serializer.toJson<DateTime>(waktuKlien),
      'strukJson': serializer.toJson<String>(strukJson),
    };
  }

  BarisTransaksiLokal copyWith({
    String? clientRef,
    Value<String?> tokoId = const Value.absent(),
    String? nomorLokal,
    Value<String?> nomorServer = const Value.absent(),
    String? tipePembayaran,
    double? grandTotal,
    double? dibayar,
    DateTime? waktuKlien,
    String? strukJson,
  }) => BarisTransaksiLokal(
    clientRef: clientRef ?? this.clientRef,
    tokoId: tokoId.present ? tokoId.value : this.tokoId,
    nomorLokal: nomorLokal ?? this.nomorLokal,
    nomorServer: nomorServer.present ? nomorServer.value : this.nomorServer,
    tipePembayaran: tipePembayaran ?? this.tipePembayaran,
    grandTotal: grandTotal ?? this.grandTotal,
    dibayar: dibayar ?? this.dibayar,
    waktuKlien: waktuKlien ?? this.waktuKlien,
    strukJson: strukJson ?? this.strukJson,
  );
  BarisTransaksiLokal copyWithCompanion(TransaksiLokalCompanion data) {
    return BarisTransaksiLokal(
      clientRef: data.clientRef.present ? data.clientRef.value : this.clientRef,
      tokoId: data.tokoId.present ? data.tokoId.value : this.tokoId,
      nomorLokal: data.nomorLokal.present
          ? data.nomorLokal.value
          : this.nomorLokal,
      nomorServer: data.nomorServer.present
          ? data.nomorServer.value
          : this.nomorServer,
      tipePembayaran: data.tipePembayaran.present
          ? data.tipePembayaran.value
          : this.tipePembayaran,
      grandTotal: data.grandTotal.present
          ? data.grandTotal.value
          : this.grandTotal,
      dibayar: data.dibayar.present ? data.dibayar.value : this.dibayar,
      waktuKlien: data.waktuKlien.present
          ? data.waktuKlien.value
          : this.waktuKlien,
      strukJson: data.strukJson.present ? data.strukJson.value : this.strukJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BarisTransaksiLokal(')
          ..write('clientRef: $clientRef, ')
          ..write('tokoId: $tokoId, ')
          ..write('nomorLokal: $nomorLokal, ')
          ..write('nomorServer: $nomorServer, ')
          ..write('tipePembayaran: $tipePembayaran, ')
          ..write('grandTotal: $grandTotal, ')
          ..write('dibayar: $dibayar, ')
          ..write('waktuKlien: $waktuKlien, ')
          ..write('strukJson: $strukJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientRef,
    tokoId,
    nomorLokal,
    nomorServer,
    tipePembayaran,
    grandTotal,
    dibayar,
    waktuKlien,
    strukJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BarisTransaksiLokal &&
          other.clientRef == this.clientRef &&
          other.tokoId == this.tokoId &&
          other.nomorLokal == this.nomorLokal &&
          other.nomorServer == this.nomorServer &&
          other.tipePembayaran == this.tipePembayaran &&
          other.grandTotal == this.grandTotal &&
          other.dibayar == this.dibayar &&
          other.waktuKlien == this.waktuKlien &&
          other.strukJson == this.strukJson);
}

class TransaksiLokalCompanion extends UpdateCompanion<BarisTransaksiLokal> {
  final Value<String> clientRef;
  final Value<String?> tokoId;
  final Value<String> nomorLokal;
  final Value<String?> nomorServer;
  final Value<String> tipePembayaran;
  final Value<double> grandTotal;
  final Value<double> dibayar;
  final Value<DateTime> waktuKlien;
  final Value<String> strukJson;
  final Value<int> rowid;
  const TransaksiLokalCompanion({
    this.clientRef = const Value.absent(),
    this.tokoId = const Value.absent(),
    this.nomorLokal = const Value.absent(),
    this.nomorServer = const Value.absent(),
    this.tipePembayaran = const Value.absent(),
    this.grandTotal = const Value.absent(),
    this.dibayar = const Value.absent(),
    this.waktuKlien = const Value.absent(),
    this.strukJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransaksiLokalCompanion.insert({
    required String clientRef,
    this.tokoId = const Value.absent(),
    required String nomorLokal,
    this.nomorServer = const Value.absent(),
    required String tipePembayaran,
    required double grandTotal,
    required double dibayar,
    required DateTime waktuKlien,
    required String strukJson,
    this.rowid = const Value.absent(),
  }) : clientRef = Value(clientRef),
       nomorLokal = Value(nomorLokal),
       tipePembayaran = Value(tipePembayaran),
       grandTotal = Value(grandTotal),
       dibayar = Value(dibayar),
       waktuKlien = Value(waktuKlien),
       strukJson = Value(strukJson);
  static Insertable<BarisTransaksiLokal> custom({
    Expression<String>? clientRef,
    Expression<String>? tokoId,
    Expression<String>? nomorLokal,
    Expression<String>? nomorServer,
    Expression<String>? tipePembayaran,
    Expression<double>? grandTotal,
    Expression<double>? dibayar,
    Expression<DateTime>? waktuKlien,
    Expression<String>? strukJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientRef != null) 'client_ref': clientRef,
      if (tokoId != null) 'toko_id': tokoId,
      if (nomorLokal != null) 'nomor_lokal': nomorLokal,
      if (nomorServer != null) 'nomor_server': nomorServer,
      if (tipePembayaran != null) 'tipe_pembayaran': tipePembayaran,
      if (grandTotal != null) 'grand_total': grandTotal,
      if (dibayar != null) 'dibayar': dibayar,
      if (waktuKlien != null) 'waktu_klien': waktuKlien,
      if (strukJson != null) 'struk_json': strukJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransaksiLokalCompanion copyWith({
    Value<String>? clientRef,
    Value<String?>? tokoId,
    Value<String>? nomorLokal,
    Value<String?>? nomorServer,
    Value<String>? tipePembayaran,
    Value<double>? grandTotal,
    Value<double>? dibayar,
    Value<DateTime>? waktuKlien,
    Value<String>? strukJson,
    Value<int>? rowid,
  }) {
    return TransaksiLokalCompanion(
      clientRef: clientRef ?? this.clientRef,
      tokoId: tokoId ?? this.tokoId,
      nomorLokal: nomorLokal ?? this.nomorLokal,
      nomorServer: nomorServer ?? this.nomorServer,
      tipePembayaran: tipePembayaran ?? this.tipePembayaran,
      grandTotal: grandTotal ?? this.grandTotal,
      dibayar: dibayar ?? this.dibayar,
      waktuKlien: waktuKlien ?? this.waktuKlien,
      strukJson: strukJson ?? this.strukJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientRef.present) {
      map['client_ref'] = Variable<String>(clientRef.value);
    }
    if (tokoId.present) {
      map['toko_id'] = Variable<String>(tokoId.value);
    }
    if (nomorLokal.present) {
      map['nomor_lokal'] = Variable<String>(nomorLokal.value);
    }
    if (nomorServer.present) {
      map['nomor_server'] = Variable<String>(nomorServer.value);
    }
    if (tipePembayaran.present) {
      map['tipe_pembayaran'] = Variable<String>(tipePembayaran.value);
    }
    if (grandTotal.present) {
      map['grand_total'] = Variable<double>(grandTotal.value);
    }
    if (dibayar.present) {
      map['dibayar'] = Variable<double>(dibayar.value);
    }
    if (waktuKlien.present) {
      map['waktu_klien'] = Variable<DateTime>(waktuKlien.value);
    }
    if (strukJson.present) {
      map['struk_json'] = Variable<String>(strukJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransaksiLokalCompanion(')
          ..write('clientRef: $clientRef, ')
          ..write('tokoId: $tokoId, ')
          ..write('nomorLokal: $nomorLokal, ')
          ..write('nomorServer: $nomorServer, ')
          ..write('tipePembayaran: $tipePembayaran, ')
          ..write('grandTotal: $grandTotal, ')
          ..write('dibayar: $dibayar, ')
          ..write('waktuKlien: $waktuKlien, ')
          ..write('strukJson: $strukJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StokDeltaTable extends StokDelta
    with TableInfo<$StokDeltaTable, BarisStokDelta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StokDeltaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _clientRefMeta = const VerificationMeta(
    'clientRef',
  );
  @override
  late final GeneratedColumn<String> clientRef = GeneratedColumn<String>(
    'client_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idProdukMeta = const VerificationMeta(
    'idProduk',
  );
  @override
  late final GeneratedColumn<String> idProduk = GeneratedColumn<String>(
    'id_produk',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deltaMeta = const VerificationMeta('delta');
  @override
  late final GeneratedColumn<double> delta = GeneratedColumn<double>(
    'delta',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, clientRef, idProduk, delta];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stok_delta';
  @override
  VerificationContext validateIntegrity(
    Insertable<BarisStokDelta> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('client_ref')) {
      context.handle(
        _clientRefMeta,
        clientRef.isAcceptableOrUnknown(data['client_ref']!, _clientRefMeta),
      );
    } else if (isInserting) {
      context.missing(_clientRefMeta);
    }
    if (data.containsKey('id_produk')) {
      context.handle(
        _idProdukMeta,
        idProduk.isAcceptableOrUnknown(data['id_produk']!, _idProdukMeta),
      );
    } else if (isInserting) {
      context.missing(_idProdukMeta);
    }
    if (data.containsKey('delta')) {
      context.handle(
        _deltaMeta,
        delta.isAcceptableOrUnknown(data['delta']!, _deltaMeta),
      );
    } else if (isInserting) {
      context.missing(_deltaMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BarisStokDelta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BarisStokDelta(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clientRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_ref'],
      )!,
      idProduk: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id_produk'],
      )!,
      delta: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}delta'],
      )!,
    );
  }

  @override
  $StokDeltaTable createAlias(String alias) {
    return $StokDeltaTable(attachedDatabase, alias);
  }
}

class BarisStokDelta extends DataClass implements Insertable<BarisStokDelta> {
  final int id;
  final String clientRef;
  final String idProduk;
  final double delta;
  const BarisStokDelta({
    required this.id,
    required this.clientRef,
    required this.idProduk,
    required this.delta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['client_ref'] = Variable<String>(clientRef);
    map['id_produk'] = Variable<String>(idProduk);
    map['delta'] = Variable<double>(delta);
    return map;
  }

  StokDeltaCompanion toCompanion(bool nullToAbsent) {
    return StokDeltaCompanion(
      id: Value(id),
      clientRef: Value(clientRef),
      idProduk: Value(idProduk),
      delta: Value(delta),
    );
  }

  factory BarisStokDelta.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BarisStokDelta(
      id: serializer.fromJson<int>(json['id']),
      clientRef: serializer.fromJson<String>(json['clientRef']),
      idProduk: serializer.fromJson<String>(json['idProduk']),
      delta: serializer.fromJson<double>(json['delta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clientRef': serializer.toJson<String>(clientRef),
      'idProduk': serializer.toJson<String>(idProduk),
      'delta': serializer.toJson<double>(delta),
    };
  }

  BarisStokDelta copyWith({
    int? id,
    String? clientRef,
    String? idProduk,
    double? delta,
  }) => BarisStokDelta(
    id: id ?? this.id,
    clientRef: clientRef ?? this.clientRef,
    idProduk: idProduk ?? this.idProduk,
    delta: delta ?? this.delta,
  );
  BarisStokDelta copyWithCompanion(StokDeltaCompanion data) {
    return BarisStokDelta(
      id: data.id.present ? data.id.value : this.id,
      clientRef: data.clientRef.present ? data.clientRef.value : this.clientRef,
      idProduk: data.idProduk.present ? data.idProduk.value : this.idProduk,
      delta: data.delta.present ? data.delta.value : this.delta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BarisStokDelta(')
          ..write('id: $id, ')
          ..write('clientRef: $clientRef, ')
          ..write('idProduk: $idProduk, ')
          ..write('delta: $delta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, clientRef, idProduk, delta);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BarisStokDelta &&
          other.id == this.id &&
          other.clientRef == this.clientRef &&
          other.idProduk == this.idProduk &&
          other.delta == this.delta);
}

class StokDeltaCompanion extends UpdateCompanion<BarisStokDelta> {
  final Value<int> id;
  final Value<String> clientRef;
  final Value<String> idProduk;
  final Value<double> delta;
  const StokDeltaCompanion({
    this.id = const Value.absent(),
    this.clientRef = const Value.absent(),
    this.idProduk = const Value.absent(),
    this.delta = const Value.absent(),
  });
  StokDeltaCompanion.insert({
    this.id = const Value.absent(),
    required String clientRef,
    required String idProduk,
    required double delta,
  }) : clientRef = Value(clientRef),
       idProduk = Value(idProduk),
       delta = Value(delta);
  static Insertable<BarisStokDelta> custom({
    Expression<int>? id,
    Expression<String>? clientRef,
    Expression<String>? idProduk,
    Expression<double>? delta,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientRef != null) 'client_ref': clientRef,
      if (idProduk != null) 'id_produk': idProduk,
      if (delta != null) 'delta': delta,
    });
  }

  StokDeltaCompanion copyWith({
    Value<int>? id,
    Value<String>? clientRef,
    Value<String>? idProduk,
    Value<double>? delta,
  }) {
    return StokDeltaCompanion(
      id: id ?? this.id,
      clientRef: clientRef ?? this.clientRef,
      idProduk: idProduk ?? this.idProduk,
      delta: delta ?? this.delta,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clientRef.present) {
      map['client_ref'] = Variable<String>(clientRef.value);
    }
    if (idProduk.present) {
      map['id_produk'] = Variable<String>(idProduk.value);
    }
    if (delta.present) {
      map['delta'] = Variable<double>(delta.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StokDeltaCompanion(')
          ..write('id: $id, ')
          ..write('clientRef: $clientRef, ')
          ..write('idProduk: $idProduk, ')
          ..write('delta: $delta')
          ..write(')'))
        .toString();
  }
}

abstract class _$SalinanDb extends GeneratedDatabase {
  _$SalinanDb(QueryExecutor e) : super(e);
  $SalinanDbManager get managers => $SalinanDbManager(this);
  late final $SalinanTable salinan = $SalinanTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $TransaksiLokalTable transaksiLokal = $TransaksiLokalTable(this);
  late final $StokDeltaTable stokDelta = $StokDeltaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    salinan,
    outbox,
    transaksiLokal,
    stokDelta,
  ];
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
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> urut,
      required String clientRef,
      required String jenis,
      Value<String?> tokoId,
      required String path,
      required String bodyJson,
      Value<int> percobaan,
      Value<DateTime?> cobaLagiSetelah,
      Value<String> status,
      Value<String?> galatTerakhir,
      Value<String?> hasilJson,
      required DateTime dibuat,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> urut,
      Value<String> clientRef,
      Value<String> jenis,
      Value<String?> tokoId,
      Value<String> path,
      Value<String> bodyJson,
      Value<int> percobaan,
      Value<DateTime?> cobaLagiSetelah,
      Value<String> status,
      Value<String?> galatTerakhir,
      Value<String?> hasilJson,
      Value<DateTime> dibuat,
    });

class $$OutboxTableFilterComposer extends Composer<_$SalinanDb, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get urut => $composableBuilder(
    column: $table.urut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jenis => $composableBuilder(
    column: $table.jenis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokoId => $composableBuilder(
    column: $table.tokoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get percobaan => $composableBuilder(
    column: $table.percobaan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cobaLagiSetelah => $composableBuilder(
    column: $table.cobaLagiSetelah,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get galatTerakhir => $composableBuilder(
    column: $table.galatTerakhir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hasilJson => $composableBuilder(
    column: $table.hasilJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dibuat => $composableBuilder(
    column: $table.dibuat,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$SalinanDb, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get urut => $composableBuilder(
    column: $table.urut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jenis => $composableBuilder(
    column: $table.jenis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokoId => $composableBuilder(
    column: $table.tokoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get percobaan => $composableBuilder(
    column: $table.percobaan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cobaLagiSetelah => $composableBuilder(
    column: $table.cobaLagiSetelah,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get galatTerakhir => $composableBuilder(
    column: $table.galatTerakhir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hasilJson => $composableBuilder(
    column: $table.hasilJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dibuat => $composableBuilder(
    column: $table.dibuat,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$SalinanDb, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get urut =>
      $composableBuilder(column: $table.urut, builder: (column) => column);

  GeneratedColumn<String> get clientRef =>
      $composableBuilder(column: $table.clientRef, builder: (column) => column);

  GeneratedColumn<String> get jenis =>
      $composableBuilder(column: $table.jenis, builder: (column) => column);

  GeneratedColumn<String> get tokoId =>
      $composableBuilder(column: $table.tokoId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<int> get percobaan =>
      $composableBuilder(column: $table.percobaan, builder: (column) => column);

  GeneratedColumn<DateTime> get cobaLagiSetelah => $composableBuilder(
    column: $table.cobaLagiSetelah,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get galatTerakhir => $composableBuilder(
    column: $table.galatTerakhir,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hasilJson =>
      $composableBuilder(column: $table.hasilJson, builder: (column) => column);

  GeneratedColumn<DateTime> get dibuat =>
      $composableBuilder(column: $table.dibuat, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$SalinanDb,
          $OutboxTable,
          BarisOutbox,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (BarisOutbox, BaseReferences<_$SalinanDb, $OutboxTable, BarisOutbox>),
          BarisOutbox,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$SalinanDb db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> urut = const Value.absent(),
                Value<String> clientRef = const Value.absent(),
                Value<String> jenis = const Value.absent(),
                Value<String?> tokoId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<int> percobaan = const Value.absent(),
                Value<DateTime?> cobaLagiSetelah = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> galatTerakhir = const Value.absent(),
                Value<String?> hasilJson = const Value.absent(),
                Value<DateTime> dibuat = const Value.absent(),
              }) => OutboxCompanion(
                urut: urut,
                clientRef: clientRef,
                jenis: jenis,
                tokoId: tokoId,
                path: path,
                bodyJson: bodyJson,
                percobaan: percobaan,
                cobaLagiSetelah: cobaLagiSetelah,
                status: status,
                galatTerakhir: galatTerakhir,
                hasilJson: hasilJson,
                dibuat: dibuat,
              ),
          createCompanionCallback:
              ({
                Value<int> urut = const Value.absent(),
                required String clientRef,
                required String jenis,
                Value<String?> tokoId = const Value.absent(),
                required String path,
                required String bodyJson,
                Value<int> percobaan = const Value.absent(),
                Value<DateTime?> cobaLagiSetelah = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> galatTerakhir = const Value.absent(),
                Value<String?> hasilJson = const Value.absent(),
                required DateTime dibuat,
              }) => OutboxCompanion.insert(
                urut: urut,
                clientRef: clientRef,
                jenis: jenis,
                tokoId: tokoId,
                path: path,
                bodyJson: bodyJson,
                percobaan: percobaan,
                cobaLagiSetelah: cobaLagiSetelah,
                status: status,
                galatTerakhir: galatTerakhir,
                hasilJson: hasilJson,
                dibuat: dibuat,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, BarisOutbox>(table),
                  BaseReferences<_$SalinanDb, $OutboxTable, BarisOutbox>(
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

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$SalinanDb,
      $OutboxTable,
      BarisOutbox,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (BarisOutbox, BaseReferences<_$SalinanDb, $OutboxTable, BarisOutbox>),
      BarisOutbox,
      PrefetchHooks Function()
    >;
typedef $$TransaksiLokalTableCreateCompanionBuilder =
    TransaksiLokalCompanion Function({
      required String clientRef,
      Value<String?> tokoId,
      required String nomorLokal,
      Value<String?> nomorServer,
      required String tipePembayaran,
      required double grandTotal,
      required double dibayar,
      required DateTime waktuKlien,
      required String strukJson,
      Value<int> rowid,
    });
typedef $$TransaksiLokalTableUpdateCompanionBuilder =
    TransaksiLokalCompanion Function({
      Value<String> clientRef,
      Value<String?> tokoId,
      Value<String> nomorLokal,
      Value<String?> nomorServer,
      Value<String> tipePembayaran,
      Value<double> grandTotal,
      Value<double> dibayar,
      Value<DateTime> waktuKlien,
      Value<String> strukJson,
      Value<int> rowid,
    });

class $$TransaksiLokalTableFilterComposer
    extends Composer<_$SalinanDb, $TransaksiLokalTable> {
  $$TransaksiLokalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokoId => $composableBuilder(
    column: $table.tokoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nomorLokal => $composableBuilder(
    column: $table.nomorLokal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nomorServer => $composableBuilder(
    column: $table.nomorServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipePembayaran => $composableBuilder(
    column: $table.tipePembayaran,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get grandTotal => $composableBuilder(
    column: $table.grandTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get dibayar => $composableBuilder(
    column: $table.dibayar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get waktuKlien => $composableBuilder(
    column: $table.waktuKlien,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strukJson => $composableBuilder(
    column: $table.strukJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransaksiLokalTableOrderingComposer
    extends Composer<_$SalinanDb, $TransaksiLokalTable> {
  $$TransaksiLokalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokoId => $composableBuilder(
    column: $table.tokoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nomorLokal => $composableBuilder(
    column: $table.nomorLokal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nomorServer => $composableBuilder(
    column: $table.nomorServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipePembayaran => $composableBuilder(
    column: $table.tipePembayaran,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get grandTotal => $composableBuilder(
    column: $table.grandTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get dibayar => $composableBuilder(
    column: $table.dibayar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get waktuKlien => $composableBuilder(
    column: $table.waktuKlien,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strukJson => $composableBuilder(
    column: $table.strukJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransaksiLokalTableAnnotationComposer
    extends Composer<_$SalinanDb, $TransaksiLokalTable> {
  $$TransaksiLokalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientRef =>
      $composableBuilder(column: $table.clientRef, builder: (column) => column);

  GeneratedColumn<String> get tokoId =>
      $composableBuilder(column: $table.tokoId, builder: (column) => column);

  GeneratedColumn<String> get nomorLokal => $composableBuilder(
    column: $table.nomorLokal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nomorServer => $composableBuilder(
    column: $table.nomorServer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tipePembayaran => $composableBuilder(
    column: $table.tipePembayaran,
    builder: (column) => column,
  );

  GeneratedColumn<double> get grandTotal => $composableBuilder(
    column: $table.grandTotal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get dibayar =>
      $composableBuilder(column: $table.dibayar, builder: (column) => column);

  GeneratedColumn<DateTime> get waktuKlien => $composableBuilder(
    column: $table.waktuKlien,
    builder: (column) => column,
  );

  GeneratedColumn<String> get strukJson =>
      $composableBuilder(column: $table.strukJson, builder: (column) => column);
}

class $$TransaksiLokalTableTableManager
    extends
        RootTableManager<
          _$SalinanDb,
          $TransaksiLokalTable,
          BarisTransaksiLokal,
          $$TransaksiLokalTableFilterComposer,
          $$TransaksiLokalTableOrderingComposer,
          $$TransaksiLokalTableAnnotationComposer,
          $$TransaksiLokalTableCreateCompanionBuilder,
          $$TransaksiLokalTableUpdateCompanionBuilder,
          (
            BarisTransaksiLokal,
            BaseReferences<
              _$SalinanDb,
              $TransaksiLokalTable,
              BarisTransaksiLokal
            >,
          ),
          BarisTransaksiLokal,
          PrefetchHooks Function()
        > {
  $$TransaksiLokalTableTableManager(_$SalinanDb db, $TransaksiLokalTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransaksiLokalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransaksiLokalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransaksiLokalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientRef = const Value.absent(),
                Value<String?> tokoId = const Value.absent(),
                Value<String> nomorLokal = const Value.absent(),
                Value<String?> nomorServer = const Value.absent(),
                Value<String> tipePembayaran = const Value.absent(),
                Value<double> grandTotal = const Value.absent(),
                Value<double> dibayar = const Value.absent(),
                Value<DateTime> waktuKlien = const Value.absent(),
                Value<String> strukJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransaksiLokalCompanion(
                clientRef: clientRef,
                tokoId: tokoId,
                nomorLokal: nomorLokal,
                nomorServer: nomorServer,
                tipePembayaran: tipePembayaran,
                grandTotal: grandTotal,
                dibayar: dibayar,
                waktuKlien: waktuKlien,
                strukJson: strukJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientRef,
                Value<String?> tokoId = const Value.absent(),
                required String nomorLokal,
                Value<String?> nomorServer = const Value.absent(),
                required String tipePembayaran,
                required double grandTotal,
                required double dibayar,
                required DateTime waktuKlien,
                required String strukJson,
                Value<int> rowid = const Value.absent(),
              }) => TransaksiLokalCompanion.insert(
                clientRef: clientRef,
                tokoId: tokoId,
                nomorLokal: nomorLokal,
                nomorServer: nomorServer,
                tipePembayaran: tipePembayaran,
                grandTotal: grandTotal,
                dibayar: dibayar,
                waktuKlien: waktuKlien,
                strukJson: strukJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransaksiLokalTable, BarisTransaksiLokal>(table),
                  BaseReferences<
                    _$SalinanDb,
                    $TransaksiLokalTable,
                    BarisTransaksiLokal
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransaksiLokalTableProcessedTableManager =
    ProcessedTableManager<
      _$SalinanDb,
      $TransaksiLokalTable,
      BarisTransaksiLokal,
      $$TransaksiLokalTableFilterComposer,
      $$TransaksiLokalTableOrderingComposer,
      $$TransaksiLokalTableAnnotationComposer,
      $$TransaksiLokalTableCreateCompanionBuilder,
      $$TransaksiLokalTableUpdateCompanionBuilder,
      (
        BarisTransaksiLokal,
        BaseReferences<_$SalinanDb, $TransaksiLokalTable, BarisTransaksiLokal>,
      ),
      BarisTransaksiLokal,
      PrefetchHooks Function()
    >;
typedef $$StokDeltaTableCreateCompanionBuilder =
    StokDeltaCompanion Function({
      Value<int> id,
      required String clientRef,
      required String idProduk,
      required double delta,
    });
typedef $$StokDeltaTableUpdateCompanionBuilder =
    StokDeltaCompanion Function({
      Value<int> id,
      Value<String> clientRef,
      Value<String> idProduk,
      Value<double> delta,
    });

class $$StokDeltaTableFilterComposer
    extends Composer<_$SalinanDb, $StokDeltaTable> {
  $$StokDeltaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idProduk => $composableBuilder(
    column: $table.idProduk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StokDeltaTableOrderingComposer
    extends Composer<_$SalinanDb, $StokDeltaTable> {
  $$StokDeltaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idProduk => $composableBuilder(
    column: $table.idProduk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StokDeltaTableAnnotationComposer
    extends Composer<_$SalinanDb, $StokDeltaTable> {
  $$StokDeltaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientRef =>
      $composableBuilder(column: $table.clientRef, builder: (column) => column);

  GeneratedColumn<String> get idProduk =>
      $composableBuilder(column: $table.idProduk, builder: (column) => column);

  GeneratedColumn<double> get delta =>
      $composableBuilder(column: $table.delta, builder: (column) => column);
}

class $$StokDeltaTableTableManager
    extends
        RootTableManager<
          _$SalinanDb,
          $StokDeltaTable,
          BarisStokDelta,
          $$StokDeltaTableFilterComposer,
          $$StokDeltaTableOrderingComposer,
          $$StokDeltaTableAnnotationComposer,
          $$StokDeltaTableCreateCompanionBuilder,
          $$StokDeltaTableUpdateCompanionBuilder,
          (
            BarisStokDelta,
            BaseReferences<_$SalinanDb, $StokDeltaTable, BarisStokDelta>,
          ),
          BarisStokDelta,
          PrefetchHooks Function()
        > {
  $$StokDeltaTableTableManager(_$SalinanDb db, $StokDeltaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StokDeltaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StokDeltaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StokDeltaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> clientRef = const Value.absent(),
                Value<String> idProduk = const Value.absent(),
                Value<double> delta = const Value.absent(),
              }) => StokDeltaCompanion(
                id: id,
                clientRef: clientRef,
                idProduk: idProduk,
                delta: delta,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String clientRef,
                required String idProduk,
                required double delta,
              }) => StokDeltaCompanion.insert(
                id: id,
                clientRef: clientRef,
                idProduk: idProduk,
                delta: delta,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StokDeltaTable, BarisStokDelta>(table),
                  BaseReferences<_$SalinanDb, $StokDeltaTable, BarisStokDelta>(
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

typedef $$StokDeltaTableProcessedTableManager =
    ProcessedTableManager<
      _$SalinanDb,
      $StokDeltaTable,
      BarisStokDelta,
      $$StokDeltaTableFilterComposer,
      $$StokDeltaTableOrderingComposer,
      $$StokDeltaTableAnnotationComposer,
      $$StokDeltaTableCreateCompanionBuilder,
      $$StokDeltaTableUpdateCompanionBuilder,
      (
        BarisStokDelta,
        BaseReferences<_$SalinanDb, $StokDeltaTable, BarisStokDelta>,
      ),
      BarisStokDelta,
      PrefetchHooks Function()
    >;

class $SalinanDbManager {
  final _$SalinanDb _db;
  $SalinanDbManager(this._db);
  $$SalinanTableTableManager get salinan =>
      $$SalinanTableTableManager(_db, _db.salinan);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$TransaksiLokalTableTableManager get transaksiLokal =>
      $$TransaksiLokalTableTableManager(_db, _db.transaksiLokal);
  $$StokDeltaTableTableManager get stokDelta =>
      $$StokDeltaTableTableManager(_db, _db.stokDelta);
}
