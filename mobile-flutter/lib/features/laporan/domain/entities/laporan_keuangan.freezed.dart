// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'laporan_keuangan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LaporanKeuangan {

 String get bulan; double get omset; int get jumlahTransaksi; double get pengeluaran; double get laba;
/// Create a copy of LaporanKeuangan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LaporanKeuanganCopyWith<LaporanKeuangan> get copyWith => _$LaporanKeuanganCopyWithImpl<LaporanKeuangan>(this as LaporanKeuangan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LaporanKeuangan&&(identical(other.bulan, bulan) || other.bulan == bulan)&&(identical(other.omset, omset) || other.omset == omset)&&(identical(other.jumlahTransaksi, jumlahTransaksi) || other.jumlahTransaksi == jumlahTransaksi)&&(identical(other.pengeluaran, pengeluaran) || other.pengeluaran == pengeluaran)&&(identical(other.laba, laba) || other.laba == laba));
}


@override
int get hashCode => Object.hash(runtimeType,bulan,omset,jumlahTransaksi,pengeluaran,laba);

@override
String toString() {
  return 'LaporanKeuangan(bulan: $bulan, omset: $omset, jumlahTransaksi: $jumlahTransaksi, pengeluaran: $pengeluaran, laba: $laba)';
}


}

/// @nodoc
abstract mixin class $LaporanKeuanganCopyWith<$Res>  {
  factory $LaporanKeuanganCopyWith(LaporanKeuangan value, $Res Function(LaporanKeuangan) _then) = _$LaporanKeuanganCopyWithImpl;
@useResult
$Res call({
 String bulan, double omset, int jumlahTransaksi, double pengeluaran, double laba
});




}
/// @nodoc
class _$LaporanKeuanganCopyWithImpl<$Res>
    implements $LaporanKeuanganCopyWith<$Res> {
  _$LaporanKeuanganCopyWithImpl(this._self, this._then);

  final LaporanKeuangan _self;
  final $Res Function(LaporanKeuangan) _then;

/// Create a copy of LaporanKeuangan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bulan = null,Object? omset = null,Object? jumlahTransaksi = null,Object? pengeluaran = null,Object? laba = null,}) {
  return _then(LaporanKeuangan(
bulan: null == bulan ? _self.bulan : bulan // ignore: cast_nullable_to_non_nullable
as String,omset: null == omset ? _self.omset : omset // ignore: cast_nullable_to_non_nullable
as double,jumlahTransaksi: null == jumlahTransaksi ? _self.jumlahTransaksi : jumlahTransaksi // ignore: cast_nullable_to_non_nullable
as int,pengeluaran: null == pengeluaran ? _self.pengeluaran : pengeluaran // ignore: cast_nullable_to_non_nullable
as double,laba: null == laba ? _self.laba : laba // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [LaporanKeuangan].
extension LaporanKeuanganPatterns on LaporanKeuangan {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LaporanKeuangan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LaporanKeuangan() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LaporanKeuangan value)  $default,){
final _that = this;
switch (_that) {
case _LaporanKeuangan():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LaporanKeuangan value)?  $default,){
final _that = this;
switch (_that) {
case _LaporanKeuangan() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String bulan,  double omset,  int jumlahTransaksi,  double pengeluaran,  double laba)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LaporanKeuangan() when $default != null:
return $default(_that.bulan,_that.omset,_that.jumlahTransaksi,_that.pengeluaran,_that.laba);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String bulan,  double omset,  int jumlahTransaksi,  double pengeluaran,  double laba)  $default,) {final _that = this;
switch (_that) {
case _LaporanKeuangan():
return $default(_that.bulan,_that.omset,_that.jumlahTransaksi,_that.pengeluaran,_that.laba);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String bulan,  double omset,  int jumlahTransaksi,  double pengeluaran,  double laba)?  $default,) {final _that = this;
switch (_that) {
case _LaporanKeuangan() when $default != null:
return $default(_that.bulan,_that.omset,_that.jumlahTransaksi,_that.pengeluaran,_that.laba);case _:
  return null;

}
}

}

/// @nodoc


class _LaporanKeuangan implements LaporanKeuangan {
  const _LaporanKeuangan({required this.bulan, required this.omset, required this.jumlahTransaksi, required this.pengeluaran, required this.laba});
  

@override final  String bulan;
@override final  double omset;
@override final  int jumlahTransaksi;
@override final  double pengeluaran;
@override final  double laba;

/// Create a copy of LaporanKeuangan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LaporanKeuanganCopyWith<_LaporanKeuangan> get copyWith => __$LaporanKeuanganCopyWithImpl<_LaporanKeuangan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LaporanKeuangan&&(identical(other.bulan, bulan) || other.bulan == bulan)&&(identical(other.omset, omset) || other.omset == omset)&&(identical(other.jumlahTransaksi, jumlahTransaksi) || other.jumlahTransaksi == jumlahTransaksi)&&(identical(other.pengeluaran, pengeluaran) || other.pengeluaran == pengeluaran)&&(identical(other.laba, laba) || other.laba == laba));
}


@override
int get hashCode => Object.hash(runtimeType,bulan,omset,jumlahTransaksi,pengeluaran,laba);

@override
String toString() {
  return 'LaporanKeuangan(bulan: $bulan, omset: $omset, jumlahTransaksi: $jumlahTransaksi, pengeluaran: $pengeluaran, laba: $laba)';
}


}

/// @nodoc
abstract mixin class _$LaporanKeuanganCopyWith<$Res> implements $LaporanKeuanganCopyWith<$Res> {
  factory _$LaporanKeuanganCopyWith(_LaporanKeuangan value, $Res Function(_LaporanKeuangan) _then) = __$LaporanKeuanganCopyWithImpl;
@override @useResult
$Res call({
 String bulan, double omset, int jumlahTransaksi, double pengeluaran, double laba
});




}
/// @nodoc
class __$LaporanKeuanganCopyWithImpl<$Res>
    implements _$LaporanKeuanganCopyWith<$Res> {
  __$LaporanKeuanganCopyWithImpl(this._self, this._then);

  final _LaporanKeuangan _self;
  final $Res Function(_LaporanKeuangan) _then;

/// Create a copy of LaporanKeuangan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bulan = null,Object? omset = null,Object? jumlahTransaksi = null,Object? pengeluaran = null,Object? laba = null,}) {
  return _then(_LaporanKeuangan(
bulan: null == bulan ? _self.bulan : bulan // ignore: cast_nullable_to_non_nullable
as String,omset: null == omset ? _self.omset : omset // ignore: cast_nullable_to_non_nullable
as double,jumlahTransaksi: null == jumlahTransaksi ? _self.jumlahTransaksi : jumlahTransaksi // ignore: cast_nullable_to_non_nullable
as int,pengeluaran: null == pengeluaran ? _self.pengeluaran : pengeluaran // ignore: cast_nullable_to_non_nullable
as double,laba: null == laba ? _self.laba : laba // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
