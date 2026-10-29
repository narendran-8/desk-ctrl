package com.deskctrl.deskctrl

fun testPhoneVolumeLease() {
    var volume = 8
    var saved: Int? = null
    val writes = mutableListOf<Int>()
    fun lease() = PhoneVolumeLease({ volume }, { volume = it; writes.add(it) }, { saved }, { saved = it })
    val owner = lease()
    owner.silence()
    check(volume == 0 && saved == 8)
    owner.silence() // retries do not replace the original with zero
    check(saved == 8 && writes == listOf(0))
    owner.restore()
    check(volume == 8 && saved == null)
    owner.restore()
    check(writes == listOf(0, 8))
    owner.silence()
    owner.restore() // switch back to also playing on phone
    check(volume == 8)

    volume = 0
    owner.silence(); owner.restore()
    check(volume == 0 && saved == null) // already silent stays silent

    volume = 6
    owner.silence()
    lease().restore() // recreated process recovers durable saved value
    check(volume == 6 && saved == null)

    val next = lease()
    next.silence()
    volume = 3 // user deliberately adjusts it outside ViL
    next.restore()
    check(volume == 3 && saved == null)

    volume = 7
    val unsupported = PhoneVolumeLease({ volume }, { /* fixed-volume device */ }, { saved }, { saved = it })
    check(runCatching { unsupported.silence() }.isFailure)
    check(volume == 7 && saved == null)

    val failedSave = PhoneVolumeLease({ volume }, { volume = it }, { null }, { error("disk full") })
    check(runCatching { failedSave.silence() }.isFailure)
    check(volume == 7) // never silence before durable recovery exists
    println("PhoneVolumeLease: silence/restore, retries, toggles, initial mute, killed process, user override, failures passed")
}
