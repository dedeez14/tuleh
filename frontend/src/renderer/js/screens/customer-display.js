// Renderer window "Display Pelanggan" (desktop) — dimuat via index.html?display=customer.
// Menampilkan customerViewHTML dari state (keranjang/bayar) yang dikirim window
// kasir lewat IPC 'customer:state' (preload customerDisplay.onState).

import { customerViewHTML } from '../components/customer-view.js'
import { api } from '../api.js'

export function mountCustomerDisplay() {
  const root = document.getElementById('app')
  document.body.classList.add('is-customer-window')
  root.innerHTML = customerViewHTML({}) // sambutan awal (menunggu state pertama)

  const splash = document.getElementById('splash')
  if (splash) splash.classList.add('is-hidden')

  if (api.customerDisplay && typeof api.customerDisplay.onState === 'function') {
    api.customerDisplay.onState((state) => {
      root.innerHTML = customerViewHTML(state || {})
    })
  }
}
