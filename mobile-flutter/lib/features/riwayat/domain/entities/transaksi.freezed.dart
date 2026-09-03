// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaksi.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Transaksi {

 String get id; String get nomor; double get grandTotal; String? get tanggal; String? get status; String? get metode;
/// Create a copy of Transaksi
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransaksiCopyWith<Transaksi> get copyWith => _$TransaksiCopyWithImpl<Transaksi>(this as Transaksi, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Transaksi&&(identical(other.id, id) || other.id == id)&&(identical(other.nomor, nomor) || other.nomor == nomor)&&(identical(other.grandTotal, grandTotal) || other.grandTotal == grandTotal)&&(identical(other.tanggal, tanggal) || other.tanggal == tanggal)&&(identical(other.status, status) || other.status == status)&&(identical(other.metode, metode) || other.metode == metode));
}


@override
int get hashCode => Object.hash(runtimeType,id,nomor,grandTotal,tanggal,status,metode);

@override
String toString() {
  return 'Transaksi(id: $id, nomor: $nomor, grandTotal: $grandTotal, tanggal: $tanggal, status: $status, metode: $metode)';
}


}

/// @nodoc
abstract mixin class $TransaksiCopyWith<$Res>  {
  factory $TransaksiCopyWith(Transaksi value, $Res Function(Transaksi) _then) = _$TransaksiCopyWithImpl;
@useResult
$Res call({
 String id, String nomor, double grandTotal, String? tanggal, String? status, String? metode
});




}
/// @nodoc
class _$TransaksiCopyWithImpl<$Res>
    implements $TransaksiCopyWith<$Res> {
  _$TransaksiCopyWithImpl(this._self, this._then);

  final Transaksi _self;
  final $Res Function(Transaksi) _then;

/// Create a copy of Transaksi
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? nomor = null,Object? grandTotal = null,Object? tanggal = freezed,Object? status = freezed,Object? metode = freezed,}) {
  return _then(Transaksi(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nomor: null == nomor ? _self.nomor : nomor // ignore: cast_nullable_to_non_nullable
as String,grandTotal: null == grandTotal ? _self.grandTotal : grandTotal // ignore: cast_nullable_to_non_nullable
as double,tanggal: freezed == tanggal ? _self.tanggal : tanggal // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,metode: freezed == metode ? _self.metode : metode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Transaksi].
extension TransaksiPatterns on Transaksi {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Transaksi value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Transaksi() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Transaksi value)  $default,){
final _that = this;
switch (_that) {
case _Transaksi():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Transaksi value)?  $default,){
final _that = this;
switch (_that) {
case _Transaksi() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String nomor,  double grandTotal,  String? tanggal,  String? status,  String? metode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Transaksi() when $default != null:
return $default(_that.id,_that.nomor,_that.grandTotal,_that.tanggal,_that.status,_that.metode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String nomor,  double grandTotal,  String? tanggal,  String? status,  String? metode)  $default,) {final _that = this;
switch (_that) {
case _Transaksi():
return $default(_that.id,_that.nomor,_that.grandTotal,_that.tanggal,_that.status,_that.metode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String nomor,  double grandTotal,  String? tanggal,  String? status,  String? metode)?  $default,) {final _that = this;
switch (_that) {
case _Transaksi() when $default != null:
return $default(_that.id,_that.nomor,_that.grandTotal,_that.tanggal,_that.status,_that.metode);case _:
  return null;

}
}

}

/// @nodoc


class _Transaksi implements Transaksi {
  const _Transaksi({required this.id, required this.nomor, required this.grandTotal, this.tanggal, this.status, this.metode});
  

@override final  String id;
@override final  String nomor;
@override final  double grandTotal;
@override final  String? tanggal;
@override final  String? status;
@override final  String? metode;

/// Create a copy of Transaksi
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransaksiCopyWith<_Transaksi> get copyWith => __$TransaksiCopyWithImpl<_Transaksi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Transaksi&&(identical(other.id, id) || other.id == id)&&(identical(other.nomor, nomor) || other.nomor == nomor)&&(identical(other.grandTotal, grandTotal) || other.grandTotal == grandTotal)&&(identical(other.tanggal, tanggal) || other.tanggal == tanggal)&&(identical(other.status, status) || other.status == status)&&(identical(other.metode, metode) || other.metode == metode));
}


@override
int get hashCode => Object.hash(runtimeType,id,nomor,grandTotal,tanggal,status,metode);

@override
String toString() {
  return 'Transaksi(id: $id, nomor: $nomor, grandTotal: $grandTotal, tanggal: $tanggal, status: $status, metode: $metode)';
}


}

/// @nodoc
abstract mixin class _$TransaksiCopyWith<$Res> implements $TransaksiCopyWith<$Res> {
  factory _$TransaksiCopyWith(_Transaksi value, $Res Function(_Transaksi) _then) = __$TransaksiCopyWithImpl;
@override @useResult
$Res call({
 String id, String nomor, double grandTotal, String? tanggal, String? status, String? metode
});




}
/// @nodoc
class __$TransaksiCopyWithImpl<$Res>
    implements _$TransaksiCopyWith<$Res> {
  __$TransaksiCopyWithImpl(this._self, this._then);

  final _Transaksi _self;
  final $Res Function(_Transaksi) _then;

/// Create a copy of Transaksi
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nomor = null,Object? grandTotal = null,Object? tanggal = freezed,Object? status = freezed,Object? metode = freezed,}) {
  return _then(_Transaksi(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nomor: null == nomor ? _self.nomor : nomor // ignore: cast_nullable_to_non_nullable
as String,grandTotal: null == grandTotal ? _self.grandTotal : grandTotal // ignore: cast_nullable_to_non_nullable
as double,tanggal: freezed == tanggal ? _self.tanggal : tanggal // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,metode: freezed == metode ? _self.metode : metode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
