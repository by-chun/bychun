package com.chun.by

import java.io.BufferedInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 本机抓包接收器：容器里的 mitmproxy addon 往 http://127.0.0.1:8899/hit POST 一条记录，
 * 这里存进环形缓冲，App 侧的 captureLog 工具/悬浮窗实时读取。
 *
 * addon 示例（Python）：
 *   from mitmproxy import http
 *   import json, urllib.request
 *   def response(flow: http.HTTPFlow):
 *       rec = {"method": flow.request.method, "url": flow.request.pretty_url,
 *              "status": flow.response.status_code,
 *              "req": flow.request.get_text(strict=False)[:2000],
 *              "res": flow.response.get_text(strict=False)[:4000]}
 *       urllib.request.urlopen(urllib.request.Request(
 *           "http://127.0.0.1:8899/hit", json.dumps(rec).encode(),
 *           {"Content-Type": "application/json"}))
 */
object CaptureServer {
    private const val MAX = 500

    data class Hit(
        val ts: Long,
        val method: String,
        val url: String,
        val status: Int,
        val req: String,
        val res: String,
    )

    private val hits = ArrayDeque<Hit>()
    private var server: ServerSocket? = null
    private val pool: ExecutorService = Executors.newFixedThreadPool(3)
    var lastError: String = ""

    @Synchronized
    fun start(port: Int = 8899) {
        if (server != null) return
        pool.execute {
            try {
                val ss = ServerSocket(port, 50, InetAddress.getByName("127.0.0.1"))
                server = ss
                while (!ss.isClosed) {
                    val sock = try {
                        ss.accept()
                    } catch (e: Throwable) {
                        break
                    }
                    pool.execute { handle(sock) }
                }
            } catch (e: Throwable) {
                lastError = e.message ?: "start failed"
            }
        }
    }

    private fun handle(sock: Socket) {
        try {
            sock.soTimeout = 5000
            val input = BufferedInputStream(sock.getInputStream())
            val out = sock.getOutputStream()

            // 读头部：读到 \r\n\r\n 结束
            val headBuf = StringBuilder()
            var last4 = 0
            while (true) {
                val b = input.read()
                if (b < 0) break
                headBuf.append(b.toChar())
                last4 = (last4 shl 8) or b
                if (last4 == 0x0D0A0D0A) break
                if (headBuf.length > 16384) break
            }
            val head = headBuf.toString()
            val len = (Regex("(?i)content-length:\\s*(\\d+)").find(head)?.groupValues?.get(1)?.toIntOrNull() ?: 0)
                .coerceAtMost(256 * 1024)
            val body = ByteArray(len)
            var read = 0
            while (read < len) {
                val n = input.read(body, read, len - read)
                if (n <= 0) break
                read += n
            }
            val text = String(body, 0, read, Charsets.UTF_8)

            val path = head.lineSequence().firstOrNull()?.split(' ')?.getOrNull(1) ?: "/"
            if (path.startsWith("/hits")) {
                val resp = listJson(0, 100)
                val bytes = resp.toByteArray()
                out.write(
                    ("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n" +
                        "Content-Length: ${bytes.size}\r\n\r\n").toByteArray()
                )
                out.write(bytes)
            } else {
                addHit(text)
                val bytes = "{\"ok\":true}".toByteArray()
                out.write(
                    ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" +
                        "Content-Length: ${bytes.size}\r\n\r\n").toByteArray()
                )
                out.write(bytes)
            }
            out.flush()
        } catch (_: Throwable) {
        } finally {
            runCatching { sock.close() }
        }
    }

    @Synchronized
    private fun addHit(json: String) {
        try {
            val o = org.json.JSONObject(json)
            val hit = Hit(
                ts = System.currentTimeMillis(),
                method = o.optString("method", "?"),
                url = o.optString("url", ""),
                status = o.optInt("status", 0),
                req = o.optString("req", ""),
                res = o.optString("res", ""),
            )
            hits.addLast(hit)
            while (hits.size > MAX) hits.removeFirst()
            runCatching {
                val svc = OverlayService.instance
                svc?.showLog("抓包")
                svc?.pushLog("[抓包] ${hit.method} ${hit.status} ${hit.url}")
            }
        } catch (_: Throwable) {
        }
    }

    /** 返回最新 limit 条（跳过最老的 skip 条）。 */
    @Synchronized
    fun listJson(skip: Int, limit: Int): String {
        val arr = org.json.JSONArray()
        val all = hits.toList()
        val from = (all.size - limit - skip).coerceAtLeast(0)
        val to = (all.size - skip).coerceAtMost(all.size)
        for (i in from until to) {
            val h = all[i]
            arr.put(
                org.json.JSONObject()
                    .put("ts", h.ts)
                    .put("method", h.method)
                    .put("url", h.url)
                    .put("status", h.status)
                    .put("req", h.req)
                    .put("res", h.res)
            )
        }
        return org.json.JSONObject().put("ok", true).put("total", all.size).put("items", arr).toString()
    }

    @Synchronized
    fun clear() {
        hits.clear()
    }

    @Synchronized
    fun count(): Int = hits.size
}
