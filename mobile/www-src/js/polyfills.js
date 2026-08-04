/* Polyfill runtime untuk WebView Android lama (Android 10 rilis dgn Chrome 77).
 * Sintaks modern (?., ??, dll.) ditranspile saat build (esbuild target es2017);
 * berkas ini menambal METODE runtime yang TIDAK ditranspile (mis. replaceAll).
 * DITULIS ES5 MURNI (var/function) agar jalan di WebView versi apa pun, dan
 * WAJIB dimuat paling awal — sebelum demo.js & app.js. */
(function () {
  'use strict'

  // String.prototype.replaceAll (Chrome 85) — dipakai esc() (escape HTML, tiap
  // render) & ekspor CSV. Tanpa ini esc() melempar → layar putih di Android 10.
  if (!String.prototype.replaceAll) {
    String.prototype.replaceAll = function (search, replace) {
      if (Object.prototype.toString.call(search) === '[object RegExp]') {
        return this.replace(search, replace)
      }
      return this.split(String(search)).join(String(replace))
    }
  }

  // Array/String .at() (Chrome 92) — defensif
  if (!Array.prototype.at) {
    var at = function (n) {
      n = Math.trunc(n) || 0
      if (n < 0) n += this.length
      return (n < 0 || n >= this.length) ? undefined : this[n]
    }
    Array.prototype.at = at
    String.prototype.at = at
  }

  // Object.hasOwn (Chrome 93) — defensif
  if (!Object.hasOwn) {
    Object.hasOwn = function (obj, prop) {
      return Object.prototype.hasOwnProperty.call(obj, prop)
    }
  }

  // Object.fromEntries (Chrome 73) — defensif
  if (!Object.fromEntries) {
    Object.fromEntries = function (iter) {
      var obj = {}
      var arr = Array.from(iter)
      for (var i = 0; i < arr.length; i++) { obj[arr[i][0]] = arr[i][1] }
      return obj
    }
  }
})()
