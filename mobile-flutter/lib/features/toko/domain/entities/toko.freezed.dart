// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'toko.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Toko {

 String get id; String get nama; String? get bidangUsaha; String? get kategori;
/// Create a copy of Toko
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TokoCopyWith<Toko> get copyWith => _$TokoCopyWithImpl<Toko>(this as Toko, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Toko&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.bidangUsaha, bidangUsaha) || other.bidangUsaha == bidangUsaha)&&(identical(other.kategori, kategori) || other.kategori == kategori));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,bidangUsaha,kategori);

@override
String toString() {
  return 'Toko(id: $id, nama: $nama, bidangUsaha: $bidangUsaha, kategori: $kategori)';
}


}

/// @nodoc
abstract mixin class $TokoCopyWith<$Res>  {
  factory $TokoCopyWith(Toko value, $Res Function(Toko) _then) = _$TokoCopyWithImpl;
@useResult
$Res call({
 String id, String nama, String? bidangUsaha, String? kategori
});




}
/// @nodoc
class _$TokoCopyWithImpl<$Res>
    implements $TokoCopyWith<$Res> {
  _$TokoCopyWithImpl(this._self, this._then);

  final Toko _self;
  final $Res Function(Toko) _then;

/// Create a copy of Toko
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? nama = null,Object? bidangUsaha = freezed,Object? kategori = freezed,}) {
  return _then(Toko(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,bidangUsaha: freezed == bidangUsaha ? _self.bidangUsaha : bidangUsaha // ignore: cast_nullable_to_non_nullable
as String?,kategori: freezed == kategori ? _self.kategori : kategori // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Toko].
extension TokoPatterns on Toko {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Toko value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Toko() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Toko value)  $default,){
final _that = this;
switch (_that) {
case _Toko():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Toko value)?  $default,){
final _that = this;
switch (_that) {
case _Toko() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String nama,  String? bidangUsaha,  String? kategori)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Toko() when $default != null:
return $default(_that.id,_that.nama,_that.bidangUsaha,_that.kategori);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String nama,  String? bidangUsaha,  String? kategori)  $default,) {final _that = this;
switch (_that) {
case _Toko():
return $default(_that.id,_that.nama,_that.bidangUsaha,_that.kategori);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String nama,  String? bidangUsaha,  String? kategori)?  $default,) {final _that = this;
switch (_that) {
case _Toko() when $default != null:
return $default(_that.id,_that.nama,_that.bidangUsaha,_that.kategori);case _:
  return null;

}
}

}

/// @nodoc


class _Toko implements Toko {
  const _Toko({required this.id, required this.nama, this.bidangUsaha, this.kategori});
  

@override final  String id;
@override final  String nama;
@override final  String? bidangUsaha;
@override final  String? kategori;

/// Create a copy of Toko
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TokoCopyWith<_Toko> get copyWith => __$TokoCopyWithImpl<_Toko>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Toko&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.bidangUsaha, bidangUsaha) || other.bidangUsaha == bidangUsaha)&&(identical(other.kategori, kategori) || other.kategori == kategori));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,bidangUsaha,kategori);

@override
String toString() {
  return 'Toko(id: $id, nama: $nama, bidangUsaha: $bidangUsaha, kategori: $kategori)';
}


}

/// @nodoc
abstract mixin class _$TokoCopyWith<$Res> implements $TokoCopyWith<$Res> {
  factory _$TokoCopyWith(_Toko value, $Res Function(_Toko) _then) = __$TokoCopyWithImpl;
@override @useResult
$Res call({
 String id, String nama, String? bidangUsaha, String? kategori
});




}
/// @nodoc
class __$TokoCopyWithImpl<$Res>
    implements _$TokoCopyWith<$Res> {
  __$TokoCopyWithImpl(this._self, this._then);

  final _Toko _self;
  final $Res Function(_Toko) _then;

/// Create a copy of Toko
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nama = null,Object? bidangUsaha = freezed,Object? kategori = freezed,}) {
  return _then(_Toko(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,bidangUsaha: freezed == bidangUsaha ? _self.bidangUsaha : bidangUsaha // ignore: cast_nullable_to_non_nullable
as String?,kategori: freezed == kategori ? _self.kategori : kategori // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
