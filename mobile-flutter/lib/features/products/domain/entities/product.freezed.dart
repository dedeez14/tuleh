// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Product {

 String get id; String get nama; double get harga; String? get tipe; double? get hargaBeli; String? get satuan; String? get kategori; String? get barcode; double? get stok;/// Harga jual normal saat [promo] aktif (untuk dicoret di kartu).
 double? get hargaNormal; bool get promo;/// URL foto produk (server: `gambar`); null = tanpa foto.
 String? get gambar;
/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCopyWith<Product> get copyWith => _$ProductCopyWithImpl<Product>(this as Product, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Product&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.harga, harga) || other.harga == harga)&&(identical(other.tipe, tipe) || other.tipe == tipe)&&(identical(other.hargaBeli, hargaBeli) || other.hargaBeli == hargaBeli)&&(identical(other.satuan, satuan) || other.satuan == satuan)&&(identical(other.kategori, kategori) || other.kategori == kategori)&&(identical(other.barcode, barcode) || other.barcode == barcode)&&(identical(other.stok, stok) || other.stok == stok)&&(identical(other.hargaNormal, hargaNormal) || other.hargaNormal == hargaNormal)&&(identical(other.promo, promo) || other.promo == promo)&&(identical(other.gambar, gambar) || other.gambar == gambar));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,harga,tipe,hargaBeli,satuan,kategori,barcode,stok,hargaNormal,promo,gambar);

@override
String toString() {
  return 'Product(id: $id, nama: $nama, harga: $harga, tipe: $tipe, hargaBeli: $hargaBeli, satuan: $satuan, kategori: $kategori, barcode: $barcode, stok: $stok, hargaNormal: $hargaNormal, promo: $promo, gambar: $gambar)';
}


}

/// @nodoc
abstract mixin class $ProductCopyWith<$Res>  {
  factory $ProductCopyWith(Product value, $Res Function(Product) _then) = _$ProductCopyWithImpl;
@useResult
$Res call({
 String id, String nama, double harga, String? tipe, double? hargaBeli, String? satuan, String? kategori, String? barcode, double? stok, double? hargaNormal, bool promo, String? gambar
});




}
/// @nodoc
class _$ProductCopyWithImpl<$Res>
    implements $ProductCopyWith<$Res> {
  _$ProductCopyWithImpl(this._self, this._then);

  final Product _self;
  final $Res Function(Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? nama = null,Object? harga = null,Object? tipe = freezed,Object? hargaBeli = freezed,Object? satuan = freezed,Object? kategori = freezed,Object? barcode = freezed,Object? stok = freezed,Object? hargaNormal = freezed,Object? promo = null,Object? gambar = freezed,}) {
  return _then(Product(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,harga: null == harga ? _self.harga : harga // ignore: cast_nullable_to_non_nullable
as double,tipe: freezed == tipe ? _self.tipe : tipe // ignore: cast_nullable_to_non_nullable
as String?,hargaBeli: freezed == hargaBeli ? _self.hargaBeli : hargaBeli // ignore: cast_nullable_to_non_nullable
as double?,satuan: freezed == satuan ? _self.satuan : satuan // ignore: cast_nullable_to_non_nullable
as String?,kategori: freezed == kategori ? _self.kategori : kategori // ignore: cast_nullable_to_non_nullable
as String?,barcode: freezed == barcode ? _self.barcode : barcode // ignore: cast_nullable_to_non_nullable
as String?,stok: freezed == stok ? _self.stok : stok // ignore: cast_nullable_to_non_nullable
as double?,hargaNormal: freezed == hargaNormal ? _self.hargaNormal : hargaNormal // ignore: cast_nullable_to_non_nullable
as double?,promo: null == promo ? _self.promo : promo // ignore: cast_nullable_to_non_nullable
as bool,gambar: freezed == gambar ? _self.gambar : gambar // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Product].
extension ProductPatterns on Product {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Product value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Product value)  $default,){
final _that = this;
switch (_that) {
case _Product():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Product value)?  $default,){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String nama,  double harga,  String? tipe,  double? hargaBeli,  String? satuan,  String? kategori,  String? barcode,  double? stok,  double? hargaNormal,  bool promo,  String? gambar)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.nama,_that.harga,_that.tipe,_that.hargaBeli,_that.satuan,_that.kategori,_that.barcode,_that.stok,_that.hargaNormal,_that.promo,_that.gambar);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String nama,  double harga,  String? tipe,  double? hargaBeli,  String? satuan,  String? kategori,  String? barcode,  double? stok,  double? hargaNormal,  bool promo,  String? gambar)  $default,) {final _that = this;
switch (_that) {
case _Product():
return $default(_that.id,_that.nama,_that.harga,_that.tipe,_that.hargaBeli,_that.satuan,_that.kategori,_that.barcode,_that.stok,_that.hargaNormal,_that.promo,_that.gambar);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String nama,  double harga,  String? tipe,  double? hargaBeli,  String? satuan,  String? kategori,  String? barcode,  double? stok,  double? hargaNormal,  bool promo,  String? gambar)?  $default,) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.nama,_that.harga,_that.tipe,_that.hargaBeli,_that.satuan,_that.kategori,_that.barcode,_that.stok,_that.hargaNormal,_that.promo,_that.gambar);case _:
  return null;

}
}

}

/// @nodoc


class _Product implements Product {
  const _Product({required this.id, required this.nama, required this.harga, this.tipe, this.hargaBeli, this.satuan, this.kategori, this.barcode, this.stok, this.hargaNormal, this.promo = false, this.gambar});
  

@override final  String id;
@override final  String nama;
@override final  double harga;
@override final  String? tipe;
@override final  double? hargaBeli;
@override final  String? satuan;
@override final  String? kategori;
@override final  String? barcode;
@override final  double? stok;
/// Harga jual normal saat [promo] aktif (untuk dicoret di kartu).
@override final  double? hargaNormal;
@override@JsonKey() final  bool promo;
/// URL foto produk (server: `gambar`); null = tanpa foto.
@override final  String? gambar;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCopyWith<_Product> get copyWith => __$ProductCopyWithImpl<_Product>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Product&&(identical(other.id, id) || other.id == id)&&(identical(other.nama, nama) || other.nama == nama)&&(identical(other.harga, harga) || other.harga == harga)&&(identical(other.tipe, tipe) || other.tipe == tipe)&&(identical(other.hargaBeli, hargaBeli) || other.hargaBeli == hargaBeli)&&(identical(other.satuan, satuan) || other.satuan == satuan)&&(identical(other.kategori, kategori) || other.kategori == kategori)&&(identical(other.barcode, barcode) || other.barcode == barcode)&&(identical(other.stok, stok) || other.stok == stok)&&(identical(other.hargaNormal, hargaNormal) || other.hargaNormal == hargaNormal)&&(identical(other.promo, promo) || other.promo == promo)&&(identical(other.gambar, gambar) || other.gambar == gambar));
}


@override
int get hashCode => Object.hash(runtimeType,id,nama,harga,tipe,hargaBeli,satuan,kategori,barcode,stok,hargaNormal,promo,gambar);

@override
String toString() {
  return 'Product(id: $id, nama: $nama, harga: $harga, tipe: $tipe, hargaBeli: $hargaBeli, satuan: $satuan, kategori: $kategori, barcode: $barcode, stok: $stok, hargaNormal: $hargaNormal, promo: $promo, gambar: $gambar)';
}


}

/// @nodoc
abstract mixin class _$ProductCopyWith<$Res> implements $ProductCopyWith<$Res> {
  factory _$ProductCopyWith(_Product value, $Res Function(_Product) _then) = __$ProductCopyWithImpl;
@override @useResult
$Res call({
 String id, String nama, double harga, String? tipe, double? hargaBeli, String? satuan, String? kategori, String? barcode, double? stok, double? hargaNormal, bool promo, String? gambar
});




}
/// @nodoc
class __$ProductCopyWithImpl<$Res>
    implements _$ProductCopyWith<$Res> {
  __$ProductCopyWithImpl(this._self, this._then);

  final _Product _self;
  final $Res Function(_Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nama = null,Object? harga = null,Object? tipe = freezed,Object? hargaBeli = freezed,Object? satuan = freezed,Object? kategori = freezed,Object? barcode = freezed,Object? stok = freezed,Object? hargaNormal = freezed,Object? promo = null,Object? gambar = freezed,}) {
  return _then(_Product(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,nama: null == nama ? _self.nama : nama // ignore: cast_nullable_to_non_nullable
as String,harga: null == harga ? _self.harga : harga // ignore: cast_nullable_to_non_nullable
as double,tipe: freezed == tipe ? _self.tipe : tipe // ignore: cast_nullable_to_non_nullable
as String?,hargaBeli: freezed == hargaBeli ? _self.hargaBeli : hargaBeli // ignore: cast_nullable_to_non_nullable
as double?,satuan: freezed == satuan ? _self.satuan : satuan // ignore: cast_nullable_to_non_nullable
as String?,kategori: freezed == kategori ? _self.kategori : kategori // ignore: cast_nullable_to_non_nullable
as String?,barcode: freezed == barcode ? _self.barcode : barcode // ignore: cast_nullable_to_non_nullable
as String?,stok: freezed == stok ? _self.stok : stok // ignore: cast_nullable_to_non_nullable
as double?,hargaNormal: freezed == hargaNormal ? _self.hargaNormal : hargaNormal // ignore: cast_nullable_to_non_nullable
as double?,promo: null == promo ? _self.promo : promo // ignore: cast_nullable_to_non_nullable
as bool,gambar: freezed == gambar ? _self.gambar : gambar // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
