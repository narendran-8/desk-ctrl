package com.deskctrl.deskctrl

fun main() {
    val received = ArrayList<Byte>()
    var starts = 0
    val pump = PcmPump(8)
    val output = { data: ByteArray, offset: Int, count: Int ->
        val n = minOf(count, 3) // simulate AudioTrack partial writes
        received.addAll(data.slice(offset until offset + n))
        n
    }
    check(pump.write(byteArrayOf(1, 2, 3, 4), { true }, output, { starts++ }))
    check(starts == 0) // do not start empty or after only one frame
    check(pump.write(byteArrayOf(5, 6, 7, 8, 9, 10), { true }, output, {
        check(received.size == 8) // start precisely at threshold, before remaining bytes
        starts++
    }))
    check(starts == 1)
    check(received == (1..10).map { it.toByte() })
    repeat(200) { check(pump.write(ByteArray(3840), { true }, output, { starts++ })) }
    check(starts == 1) // continuous frames never stop/restart playback
    check(!PcmPump(8).write(ByteArray(4), { true }, { _, _, _ -> -6 }, {}))
    check(!PcmPump(8).write(ByteArray(4), { false }, output, {}))
    println("PcmPump: prebuffer, partial writes, continuous playback, stop/error passed")
}
