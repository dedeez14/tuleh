// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sesi.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Sesi {

 String get id; String? get nomor; String? get dibukaPada;
/// Create a copy of Sesi
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SesiCopyWith<Sesi> get copyWith => _$SesiCopyWithImpl<Sesi>(this as Sesi, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Sesi&&(identical(other.id, id) || other.id == id)&&(identical(other.nomor, nomor) || other.nomor == nomor)&&(identical(other.dibukaPada, dibukaPada) || other.dibukaPada == dibukaPada));
}


@override
int get hashCode => Object.hash(runtimeType,id,nomor,dibukaPada);

@override
String toString() {
  return 'Sesi(id: $id, nomor: $nomor, dibukaPada: $dibukaPada)';
}


}

/// @nodoc
abstract mixin class $SesiCopyWith<$Res>  {
  factory $SesiCopyWith(Sesi value, $Res Function(Sesi) _then) = _$SesiCopyWithImpl;
@useResult
$Res call({
 String id, String? nomor, String? dibukaPada
});




}
/// @nodoc
class _$SesiCopyWithImpl<$Res>
    implements $SesiCopyWith<$Res> {
  _$SesiCopyWithImpl(this._self, this._then);

  final Sesi _self;
  final $Res Function(Sesi) _then;

/// Create a copy of Sesi
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? nomor = freezed,Object? dibukaPada = freezed,}) {
  return _then(Sesi(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nomor: freezed == nomor ? _self.nomor : nomor // ignore: cast_nullable_to_non_nullable
as String?,dibukaPada: freezed == dibukaPada ? _self.dibukaPada : dibukaPada // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Sesi].
extension SesiPatterns on Sesi {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Sesi value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Sesi() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Sesi value)  $default,){
final _that = this;
switch (_that) {
case _Sesi():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Sesi value)?  $default,){
final _that = this;
switch (_that) {
case _Sesi() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? nomor,  String? dibukaPada)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Sesi() when $default != null:
return $default(_that.id,_that.nomor,_that.dibukaPada);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? nomor,  String? dibukaPada)  $default,) {final _that = this;
switch (_that) {
case _Sesi():
return $default(_that.id,_that.nomor,_that.dibukaPada);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? nomor,  String? dibukaPada)?  $default,) {final _that = this;
switch (_that) {
case _Sesi() when $default != null:
return $default(_that.id,_that.nomor,_that.dibukaPada);case _:
  return null;

}
}

}

/// @nodoc


class _Sesi implements Sesi {
  const _Sesi({required this.id, this.nomor, this.dibukaPada});
  

@override final  String id;
@override final  String? nomor;
@override final  String? dibukaPada;

/// Create a copy of Sesi
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SesiCopyWith<_Sesi> get copyWith => __$SesiCopyWithImpl<_Sesi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Sesi&&(identical(other.id, id) || other.id == id)&&(identical(other.nomor, nomor) || other.nomor == nomor)&&(identical(other.dibukaPada, dibukaPada) || other.dibukaPada == dibukaPada));
}


@override
int get hashCode => Object.hash(runtimeType,id,nomor,dibukaPada);

@override
String toString() {
  return 'Sesi(id: $id, nomor: $nomor, dibukaPada: $dibukaPada)';
}


}

/// @nodoc
abstract mixin class _$SesiCopyWith<$Res> implements $SesiCopyWith<$Res> {
  factory _$SesiCopyWith(_Sesi value, $Res Function(_Sesi) _then) = __$SesiCopyWithImpl;
@override @useResult
$Res call({
 String id, String? nomor, String? dibukaPada
});




}
/// @nodoc
class __$SesiCopyWithImpl<$Res>
    implements _$SesiCopyWith<$Res> {
  __$SesiCopyWithImpl(this._self, this._then);

  final _Sesi _self;
  final $Res Function(_Sesi) _then;

/// Create a copy of Sesi
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nomor = freezed,Object? dibukaPada = freezed,}) {
  return _then(_Sesi(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nomor: freezed == nomor ? _self.nomor : nomor // ignore: cast_nullable_to_non_nullable
as String?,dibukaPada: freezed == dibukaPada ? _self.dibukaPada : dibukaPada // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
