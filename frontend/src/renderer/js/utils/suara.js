// Bunyi "ting" singkat (tanpa berkas audio) — dipakai papan pesanan dan
// pemantau pesanan meja. Gagal diam-diam bila AudioContext tidak tersedia.
let audioCtx = null

export function ting() {
  try {
    audioCtx = audioCtx || new AudioContext()
    const osc = audioCtx.createOscillator()
    const gain = audioCtx.createGain()
    osc.type = 'sine'
    osc.frequency.value = 1046 // C6
    gain.gain.setValueAtTime(0.15, audioCtx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.35)
    osc.connect(gain).connect(audioCtx.destination)
    osc.start()
    osc.stop(audioCtx.currentTime + 0.35)
  } catch {
    // Audio tidak tersedia — abaikan
  }
}
