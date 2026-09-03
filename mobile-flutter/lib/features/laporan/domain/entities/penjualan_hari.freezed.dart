// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'penjualan_hari.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PenjualanHari {

 String get tanggal; int get jumlahTransaksi; double get totalOmzet;
/// Create a copy of PenjualanHari
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PenjualanHariCopyWith<PenjualanHari> get copyWith => _$PenjualanHariCopyWithImpl<PenjualanHari>(this as PenjualanHari, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PenjualanHari&&(identical(other.tanggal, tanggal) || other.tanggal == tanggal)&&(identical(other.jumlahTransaksi, jumlahTransaksi) || other.jumlahTransaksi == jumlahTransaksi)&&(identical(other.totalOmzet, totalOmzet) || other.totalOmzet == totalOmzet));
}


@override
int get hashCode => Object.hash(runtimeType,tanggal,jumlahTransaksi,totalOmzet);

@override
String toString() {
  return 'PenjualanHari(tanggal: $tanggal, jumlahTransaksi: $jumlahTransaksi, totalOmzet: $totalOmzet)';
}


}

/// @nodoc
abstract mixin class $PenjualanHariCopyWith<$Res>  {
  factory $PenjualanHariCopyWith(PenjualanHari value, $Res Function(PenjualanHari) _then) = _$PenjualanHariCopyWithImpl;
@useResult
$Res call({
 String tanggal, int jumlahTransaksi, double totalOmzet
});




}
/// @nodoc
class _$PenjualanHariCopyWithImpl<$Res>
    implements $PenjualanHariCopyWith<$Res> {
  _$PenjualanHariCopyWithImpl(this._self, this._then);

  final PenjualanHari _self;
  final $Res Function(PenjualanHari) _then;

/// Create a copy of PenjualanHari
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tanggal = null,Object? jumlahTransaksi = null,Object? totalOmzet = null,}) {
  return _then(PenjualanHari(
tanggal: null == tanggal ? _self.tanggal : tanggal // ignore: cast_nullable_to_non_nullable
as String,jumlahTransaksi: null == jumlahTransaksi ? _self.jumlahTransaksi : jumlahTransaksi // ignore: cast_nullable_to_non_nullable
as int,totalOmzet: null == totalOmzet ? _self.totalOmzet : totalOmzet // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [PenjualanHari].
extension PenjualanHariPatterns on PenjualanHari {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PenjualanHari value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PenjualanHari() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PenjualanHari value)  $default,){
final _that = this;
switch (_that) {
case _PenjualanHari():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PenjualanHari value)?  $default,){
final _that = this;
switch (_that) {
case _PenjualanHari() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String tanggal,  int jumlahTransaksi,  double totalOmzet)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PenjualanHari() when $default != null:
return $default(_that.tanggal,_that.jumlahTransaksi,_that.totalOmzet);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String tanggal,  int jumlahTransaksi,  double totalOmzet)  $default,) {final _that = this;
switch (_that) {
case _PenjualanHari():
return $default(_that.tanggal,_that.jumlahTransaksi,_that.totalOmzet);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String tanggal,  int jumlahTransaksi,  double totalOmzet)?  $default,) {final _that = this;
switch (_that) {
case _PenjualanHari() when $default != null:
return $default(_that.tanggal,_that.jumlahTransaksi,_that.totalOmzet);case _:
  return null;

}
}

}

/// @nodoc


class _PenjualanHari implements PenjualanHari {
  const _PenjualanHari({required this.tanggal, required this.jumlahTransaksi, required this.totalOmzet});
  

@override final  String tanggal;
@override final  int jumlahTransaksi;
@override final  double totalOmzet;

/// Create a copy of PenjualanHari
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PenjualanHariCopyWith<_PenjualanHari> get copyWith => __$PenjualanHariCopyWithImpl<_PenjualanHari>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PenjualanHari&&(identical(other.tanggal, tanggal) || other.tanggal == tanggal)&&(identical(other.jumlahTransaksi, jumlahTransaksi) || other.jumlahTransaksi == jumlahTransaksi)&&(identical(other.totalOmzet, totalOmzet) || other.totalOmzet == totalOmzet));
}


@override
int get hashCode => Object.hash(runtimeType,tanggal,jumlahTransaksi,totalOmzet);

@override
String toString() {
  return 'PenjualanHari(tanggal: $tanggal, jumlahTransaksi: $jumlahTransaksi, totalOmzet: $totalOmzet)';
}


}

/// @nodoc
abstract mixin class _$PenjualanHariCopyWith<$Res> implements $PenjualanHariCopyWith<$Res> {
  factory _$PenjualanHariCopyWith(_PenjualanHari value, $Res Function(_PenjualanHari) _then) = __$PenjualanHariCopyWithImpl;
@override @useResult
$Res call({
 String tanggal, int jumlahTransaksi, double totalOmzet
});




}
/// @nodoc
class __$PenjualanHariCopyWithImpl<$Res>
    implements _$PenjualanHariCopyWith<$Res> {
  __$PenjualanHariCopyWithImpl(this._self, this._then);

  final _PenjualanHari _self;
  final $Res Function(_PenjualanHari) _then;

/// Create a copy of PenjualanHari
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tanggal = null,Object? jumlahTransaksi = null,Object? totalOmzet = null,}) {
  return _then(_PenjualanHari(
tanggal: null == tanggal ? _self.tanggal : tanggal // ignore: cast_nullable_to_non_nullable
as String,jumlahTransaksi: null == jumlahTransaksi ? _self.jumlahTransaksi : jumlahTransaksi // ignore: cast_nullable_to_non_nullable
as int,totalOmzet: null == totalOmzet ? _self.totalOmzet : totalOmzet // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
