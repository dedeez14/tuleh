'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { verifySmoke } = require('../tools/verify-smoke.cjs')

const valid = () => ({
  loaded: true, rendererReady: true, loginReady: true, demo: false, version: '0.9.41', log: [],
  gateway: { running: true, version: '0.9.41', external: false, upstream: 'https://tuleh-smoke.invalid' }
})

test('installer smoke: layar masuk dan gateway versi sama lulus', () => {
  assert.doesNotThrow(() => verifySmoke(valid(), '0.9.41'))
})

test('installer smoke: laporan loaded saja tidak cukup untuk menerbitkan rilis', () => {
  for (const delta of [{rendererReady: false}, {loginReady: false}, {demo: true}, {version: '0.9.40'}, {gateway: {running: false}}, {log: ['[3] Boot gagal: ReferenceError']}]) {
    assert.throws(() => verifySmoke({...valid(), ...delta}, '0.9.41'))
  }
})

test('installer smoke: gateway lama, eksternal, atau mengarah produksi ditolak', () => {
  for (const delta of [{version: '0.9.40'}, {external: true}, {upstream: 'https://tatreport.com'}]) {
    const report = valid()
    Object.assign(report.gateway, delta)
    assert.throws(() => verifySmoke(report, '0.9.41'))
  }
})
