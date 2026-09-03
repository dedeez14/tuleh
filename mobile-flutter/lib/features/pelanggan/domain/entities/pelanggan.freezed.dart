// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pelanggan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Pelanggan {

 String get id; String get nama; String? get kode; String? get telepon; String? get alamat;
/// Create a copy of Pelanggan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PelangganCopyWith<Pelanggan> get copyWith => _$PelangganCopyWithImpl<Pelanggan>(this as Pelanggan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Pelanggan&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.kode, kode) || other.kode == kode)&&(identical(other.telepon, telepon) || other.telepon == telepon)&&(identical(other.alamat, alamat) || other.alamat == alamat));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,kode,telepon,alamat);

@override
String toString() {
  return 'Pelanggan(id: $id, nama: $nama, kode: $kode, telepon: $telepon, alamat: $alamat)';
}


}

/// @nodoc
abstract mixin class $PelangganCopyWith<$Res>  {
  factory $PelangganCopyWith(Pelanggan value, $Res Function(Pelanggan) _then) = _$PelangganCopyWithImpl;
@useResult
$Res call({
 String id, String nama, String? kode, String? telepon, String? alamat
});




}
/// @nodoc
class _$PelangganCopyWithImpl<$Res>
    implements $PelangganCopyWith<$Res> {
  _$PelangganCopyWithImpl(this._self, this._then);

  final Pelanggan _self;
  final $Res Function(Pelanggan) _then;

/// Create a copy of Pelanggan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? nama = null,Object? kode = freezed,Object? telepon = freezed,Object? alamat = freezed,}) {
  return _then(Pelanggan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,kode: freezed == kode ? _self.kode : kode // ignore: cast_nullable_to_non_nullable
as String?,telepon: freezed == telepon ? _self.telepon : telepon // ignore: cast_nullable_to_non_nullable
as String?,alamat: freezed == alamat ? _self.alamat : alamat // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Pelanggan].
extension PelangganPatterns on Pelanggan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Pelanggan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Pelanggan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Pelanggan value)  $default,){
final _that = this;
switch (_that) {
case _Pelanggan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Pelanggan value)?  $default,){
final _that = this;
switch (_that) {
case _Pelanggan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String nama,  String? kode,  String? telepon,  String? alamat)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Pelanggan() when $default != null:
return $default(_that.id,_that.nama,_that.kode,_that.telepon,_that.alamat);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String nama,  String? kode,  String? telepon,  String? alamat)  $default,) {final _that = this;
switch (_that) {
case _Pelanggan():
return $default(_that.id,_that.nama,_that.kode,_that.telepon,_that.alamat);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String nama,  String? kode,  String? telepon,  String? alamat)?  $default,) {final _that = this;
switch (_that) {
case _Pelanggan() when $default != null:
return $default(_that.id,_that.nama,_that.kode,_that.telepon,_that.alamat);case _:
  return null;

}
}

}

/// @nodoc


class _Pelanggan implements Pelanggan {
  const _Pelanggan({required this.id, required this.nama, this.kode, this.telepon, this.alamat});
  

@override final  String id;
@override final  String nama;
@override final  String? kode;
@override final  String? telepon;
@override final  String? alamat;

/// Create a copy of Pelanggan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PelangganCopyWith<_Pelanggan> get copyWith => __$PelangganCopyWithImpl<_Pelanggan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Pelanggan&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.kode, kode) || other.kode == kode)&&(identical(other.telepon, telepon) || other.telepon == telepon)&&(identical(other.alamat, alamat) || other.alamat == alamat));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,kode,telepon,alamat);

@override
String toString() {
  return 'Pelanggan(id: $id, nama: $nama, kode: $kode, telepon: $telepon, alamat: $alamat)';
}


}

/// @nodoc
abstract mixin class _$PelangganCopyWith<$Res> implements $PelangganCopyWith<$Res> {
  factory _$PelangganCopyWith(_Pelanggan value, $Res Function(_Pelanggan) _then) = __$PelangganCopyWithImpl;
@override @useResult
$Res call({
 String id, String nama, String? kode, String? telepon, String? alamat
});




}
/// @nodoc
class __$PelangganCopyWithImpl<$Res>
    implements _$PelangganCopyWith<$Res> {
  __$PelangganCopyWithImpl(this._self, this._then);

  final _Pelanggan _self;
  final $Res Function(_Pelanggan) _then;

/// Create a copy of Pelanggan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nama = null,Object? kode = freezed,Object? telepon = freezed,Object? alamat = freezed,}) {
  return _then(_Pelanggan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,kode: freezed == kode ? _self.kode : kode // ignore: cast_nullable_to_non_nullable
as String?,telepon: freezed == telepon ? _self.telepon : telepon // ignore: cast_nullable_to_non_nullable
as String?,alamat: freezed == alamat ? _self.alamat : alamat // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
