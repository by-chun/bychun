package com.chun.by

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.Executors

/**
 * DNS 抓包：VPN 只路由发往虚拟 DNS(10.66.0.1) 的流量，拦截后转发给真实 DNS，
 * 记录每次查询的域名与结果。其他流量不走 VPN，所以不影响上外网。
 *
 * 为什么只抓 DNS：完整抓 TCP 需要实现整套协议栈；域名级抓取已能回答"谁在连哪里"，
 * 且不改动系统代理、不需要证书。HTTP 内容解密是后续独立工作。
 */
class DnsVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private val pool = Executors.newFixedThreadPool(8)
    @Volatile private var running = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopEverything()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_SET_DNS) {
            val d = intent.getStringExtra("dns")?.trim().orEmpty()
            if (d.isNotEmpty()) {
                upstreamDns = d
                autoDetected = false
                noDns = false
                logLine("上游 DNS 已设为 $d")
            }
            return START_NOT_STICKY
        }
        startForegroundSafe()
        startTunnel()
        return START_STICKY
    }

    private fun startForegroundSafe() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL, "Rowan 抓包", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n: Notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("Rowan 抓包")
            .setContentText("正在记录 DNS 查询")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(pi)
            .build()
        startForeground(9001, n)
    }

    private fun startTunnel() {
        if (running) return
        // 上游 DNS：先用系统当前网络的 DNS；取不到就不建 VPN（避免断网），交给用户手填
        if (upstreamDns.isEmpty()) {
            val d = detectSystemDns()
            if (d.isNotEmpty()) {
                upstreamDns = d
                autoDetected = true
                noDns = false
            } else {
                noDns = true
                logLine("系统 DNS 取不到：等待手动填写上游 DNS")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
        }
        val builder = Builder()
            .setSession("Rowan DNS")
            .addAddress("10.66.0.1", 32)
            .addDnsServer("10.66.0.1")
            .addRoute("10.66.0.1", 32)
            .setBlocking(true)
        // 排除自己，避免 VPN 内部再走 VPN 形成回环
        runCatching { builder.addDisallowedApplication(packageName) }
        val fd = try {
            builder.establish()
        } catch (e: Throwable) {
            logLine("建立 VPN 失败：${e.message}")
            stopSelf()
            return
        } ?: return
        tun = fd
        running = true
        runningNow = true
        worker = Thread { loop(fd) }.also { it.start() }
    }

    /** 从当前活动网络（或 VPN）取 DNS，只取 IPv4。 */
    private fun detectSystemDns(): String = runCatching {
        @Suppress("DEPRECATION")
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val net = cm?.activeNetwork
        val lp = net?.let { cm?.getLinkProperties(it) }
        lp?.dnsServers?.firstOrNull { it is Inet4Address }?.hostAddress ?: ""
    }.getOrDefault("")

    private fun loop(fd: ParcelFileDescriptor) {
        val inFd = FileInputStream(fd.fileDescriptor)
        val outFd = FileOutputStream(fd.fileDescriptor)
        val buf = ByteArray(32767)
        while (running) {
            val n = try {
                inFd.read(buf)
            } catch (e: Throwable) {
                break
            }
            if (n <= 0) continue
            val pkt = buf.copyOf(n)
            // 并发处理：DNS 多的时候不能串行排队，否则整个网络像卡死
            runCatching { pool.execute { runCatching { handlePacket(pkt, pkt.size, outFd) } } }
        }
    }

    /** 解析 IPv4 + UDP(53)，记录域名并转发，再把响应写回 TUN。 */
    private fun handlePacket(p: ByteArray, len: Int, out: FileOutputStream) {
        if (len < 28) return
        val version = (p[0].toInt() shr 4) and 0xF
        if (version != 4) return
        val ihl = (p[0].toInt() and 0xF) * 4
        if (len < ihl + 8) return
        if ((p[9].toInt() and 0xFF) != 17) return // 只处理 UDP
        val srcIp = byteArrayOf(p[12], p[13], p[14], p[15])
        val srcPort = ((p[ihl].toInt() and 0xFF) shl 8) or (p[ihl + 1].toInt() and 0xFF)
        val dstPort = ((p[ihl + 2].toInt() and 0xFF) shl 8) or (p[ihl + 3].toInt() and 0xFF)
        if (dstPort != 53) return
        val udpLen = ((p[ihl + 4].toInt() and 0xFF) shl 8) or (p[ihl + 5].toInt() and 0xFF)
        val payloadOff = ihl + 8
        val payloadLen = udpLen - 8
        if (payloadLen <= 0 || payloadOff + payloadLen > len) return

        val query = p.copyOfRange(payloadOff, payloadOff + payloadLen)
        val name = parseQName(query)

        // 转发到真实 DNS
        val resp = try {
            val sock = DatagramSocket()
            protect(sock)
            sock.soTimeout = 1500
            sock.send(DatagramPacket(query, query.size, InetAddress.getByName(upstreamDns), 53))
            val rbuf = ByteArray(4096)
            val rp = DatagramPacket(rbuf, rbuf.size)
            sock.receive(rp)
            sock.close()
            rbuf.copyOfRange(0, rp.length)
        } catch (e: Throwable) {
            logLine("转发失败：${e.message}")
            return
        }

        val ips = parseAnswerIps(resp)
        logLine("$name -> ${ips.joinToString(",").ifEmpty { "?" }}")

        // 回包：交换 src/dst，端口对调
        // 多线程并发处理，回写同一 TUN 流必须串行，否则 UDP 包会交错
        synchronized(out) { writeUdpReply(out, srcIp, srcPort, resp) }
    }

    private fun writeUdpReply(out: FileOutputStream, dstIp: ByteArray, dstPort: Int, payload: ByteArray) {
        val total = 20 + 8 + payload.size
        val pkt = ByteArray(total)
        pkt[0] = 0x45
        pkt[2] = ((total shr 8) and 0xFF).toByte()
        pkt[3] = (total and 0xFF).toByte()
        pkt[8] = 64
        pkt[9] = 17
        // src = 上游 DNS 的 IP 由内核路由决定，这里用 10.66.0.1 作为源即可
        pkt[12] = 10; pkt[13] = 66; pkt[14] = 0; pkt[15] = 1
        System.arraycopy(dstIp, 0, pkt, 16, 4)
        var sum = 0
        var i = 0
        while (i < 20) {
            sum += ((pkt[i].toInt() and 0xFF) shl 8) or (pkt[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        val chk = sum.inv() and 0xFFFF
        pkt[10] = ((chk shr 8) and 0xFF).toByte()
        pkt[11] = (chk and 0xFF).toByte()
        // UDP 头
        pkt[20] = ((53 shr 8) and 0xFF).toByte()
        pkt[21] = (53 and 0xFF).toByte()
        pkt[22] = ((dstPort shr 8) and 0xFF).toByte()
        pkt[23] = (dstPort and 0xFF).toByte()
        val ulen = 8 + payload.size
        pkt[24] = ((ulen shr 8) and 0xFF).toByte()
        pkt[25] = (ulen and 0xFF).toByte()
        pkt[26] = 0
        pkt[27] = 0
        System.arraycopy(payload, 0, pkt, 28, payload.size)
        runCatching { out.write(pkt) }
    }

    private fun parseQName(dns: ByteArray): String {
        if (dns.size < 13) return "?"
        val sb = StringBuilder()
        var i = 12
        var guard = 0
        while (i < dns.size && guard < 64) {
            val l = dns[i].toInt() and 0xFF
            if (l == 0) break
            if (l and 0xC0 == 0xC0) break // 压缩指针
            if (i + 1 + l > dns.size) break
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(dns, i + 1, l, Charsets.US_ASCII))
            i += l + 1
            guard++
        }
        return sb.toString().ifEmpty { "?" }
    }

    private fun parseAnswerIps(dns: ByteArray): List<String> {
        if (dns.size < 12) return emptyList()
        val qd = ((dns[4].toInt() and 0xFF) shl 8) or (dns[5].toInt() and 0xFF)
        val an = ((dns[6].toInt() and 0xFF) shl 8) or (dns[7].toInt() and 0xFF)
        var i = 12
        repeat(qd) {
            while (i < dns.size && dns[i].toInt() != 0) {
                val l = dns[i].toInt() and 0xFF
                i += if (l and 0xC0 == 0xC0) 2 else l + 1
            }
            i += 5
        }
        val out = ArrayList<String>()
        repeat(an) {
            if (i + 12 > dns.size) return out
            if (dns[i].toInt() and 0xC0 == 0xC0) i += 2 else {
                while (i < dns.size && dns[i].toInt() != 0) i += (dns[i].toInt() and 0xFF) + 1
                i++
            }
            val type = ((dns[i].toInt() and 0xFF) shl 8) or (dns[i + 1].toInt() and 0xFF)
            val rdlen = ((dns[i + 8].toInt() and 0xFF) shl 8) or (dns[i + 9].toInt() and 0xFF)
            i += 10
            if (type == 1 && rdlen == 4 && i + 4 <= dns.size) {
                out.add("${dns[i].toInt() and 0xFF}.${dns[i + 1].toInt() and 0xFF}.${dns[i + 2].toInt() and 0xFF}.${dns[i + 3].toInt() and 0xFF}")
            }
            i += rdlen
        }
        return out
    }

    @Synchronized
    private fun logLine(line: String) {
        runCatching {
            val f = File(filesDir, "dns_capture.log")
            if (f.exists() && f.length() > 512 * 1024) f.delete()
            f.appendText("${System.currentTimeMillis()} $line\n")
        }
    }

    private fun stopEverything() {
        running = false
        runningNow = false
        runCatching { worker?.interrupt() }
        runCatching { tun?.close() }
        tun = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        stopEverything()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopEverything()
        runCatching { pool.shutdownNow() }
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "g-dns-capture"
        const val ACTION_STOP = "com.chun.by.VPN_STOP"
        const val ACTION_SET_DNS = "com.chun.by.VPN_SET_DNS"

        /** 当前生效的上游 DNS（空 = 还没取到）。 */
        @Volatile var upstreamDns: String = ""
        /** 是否自动从系统网络取到。 */
        @Volatile var autoDetected: Boolean = true
        /** 自动检测失败，等待手动填写。 */
        @Volatile var noDns: Boolean = false
        /** VPN 是否已建立（DNS 转发在跑）。 */
        @Volatile var runningNow: Boolean = false

        fun logFile(dir: File) = File(dir, "dns_capture.log")
    }
}
