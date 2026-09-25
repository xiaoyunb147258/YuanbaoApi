package dev.yuanbao2api.util

import java.net.Inet4Address
import java.net.NetworkInterface

object NetUtil {
    fun getLocalIp(): String {
        val candidates = mutableListOf<Pair<String, String>>()
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()) {
                if (!nif.isUp || nif.isLoopback) continue
                for (addr in nif.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        candidates.add(nif.name.lowercase() to ip)
                    }
                }
            }
        } catch (_: Exception) {}
        candidates.firstOrNull { it.first.startsWith("wlan") }?.let { return it.second }
        candidates.firstOrNull { it.first.startsWith("eth") || it.first.startsWith("ap") }?.let { return it.second }
        candidates.firstOrNull()?.let { return it.second }
        return "127.0.0.1"
    }
}
