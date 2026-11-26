package com.chun.by

import android.content.Context
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.BasicConstraints
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.KeyUsage
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.io.File
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Date

/**
 * 生成自签 CA 并装进系统信任区（需 root）。
 *
 * 证书落在 Magisk 模块里，重启后依然生效：
 *   /data/adb/modules/rowan-mitm-ca/system/etc/security/cacerts/<hash>.0
 * Android 14+ 的 conscrypt 走 APEX，模块 system 挂载在多数 ROM 上仍能被读取；
 * 若解密失败再用 overlay 方式补。
 */
object CaInstaller {
    private const val MODULE_ID = "rowan-mitm-ca"
    private const val CN = "CN=Rowan MITM CA, O=Rowan, C=CN"

    fun caDir(ctx: Context) = File(ctx.filesDir, "ca").apply { mkdirs() }
    fun certFile(ctx: Context) = File(caDir(ctx), "ca.pem")
    private fun keyFile(ctx: Context) = File(caDir(ctx), "ca.key")

    fun isInstalled(ctx: Context): Boolean =
        File("/data/adb/modules/$MODULE_ID/system/etc/security/cacerts").let { dir ->
            dir.isDirectory && (dir.listFiles()?.any { it.name.endsWith(".0") } == true)
        }

    /** 生成（或复用）CA，返回证书；私钥写盘供后续 mitmproxy 用。 */
    @Synchronized
    fun ensureCa(ctx: Context): X509Certificate? {
        val cf = certFile(ctx)
        if (cf.exists()) {
            runCatching {
                return parseCert(cf.readBytes())
            }
        }
        return try {
            val kpg = KeyPairGenerator.getInstance("RSA")
            kpg.initialize(2048)
            val kp = kpg.generateKeyPair()
            val now = System.currentTimeMillis()
            val subject = X500Name(CN)
            val builder = JcaX509v3CertificateBuilder(
                subject,
                BigInteger.valueOf(now),
                Date(now - 86_400_000L),
                Date(now + 10L * 365 * 86_400_000L),
                subject,
                kp.public,
            )
            builder.addExtension(Extension.basicConstraints, true, BasicConstraints(true))
            builder.addExtension(
                Extension.keyUsage, true,
                KeyUsage(KeyUsage.keyCertSign or KeyUsage.cRLSign or KeyUsage.digitalSignature),
            )
            val signer = JcaContentSignerBuilder("SHA256withRSA").build(kp.private)
            val cert = JcaX509CertificateConverter().getCertificate(builder.build(signer))

            cf.writeBytes(cert.encoded)
            keyFile(ctx).writeBytes(kp.private.encoded)
            cert
        } catch (e: Throwable) {
            android.util.Log.e("CaInstaller", "ensureCa failed", e)
            null
        }
    }

    private fun parseCert(der: ByteArray): X509Certificate =
        java.security.cert.CertificateFactory.getInstance("X.509")
            .generateCertificate(der.inputStream()) as X509Certificate

    /** OpenSSL 的 subject_hash：subject DER 做 MD5，取前 4 字节按小端拼成 8 位十六进制。 */
    fun subjectHash(cert: X509Certificate): String {
        val md5 = MessageDigest.getInstance("MD5").digest(cert.subjectX500Principal.encoded)
        var v = 0L
        for (i in 3 downTo 0) {
            v = (v shl 8) or (md5[i].toLong() and 0xFF)
        }
        return java.lang.Long.toHexString(v).padStart(8, '0')
    }

    fun pem(cert: X509Certificate): String {
        val b64 = android.util.Base64.encodeToString(cert.encoded, android.util.Base64.NO_WRAP)
        val sb = StringBuilder("-----BEGIN CERTIFICATE-----\n")
        var i = 0
        while (i < b64.length) {
            val end = minOf(i + 64, b64.length)
            sb.append(b64, i, end).append('\n')
            i = end
        }
        sb.append("-----END CERTIFICATE-----\n")
        return sb.toString()
    }

    /**
     * 用 root 把证书装进 Magisk 模块。每次都要 su 授权（高危操作，不记忆）。
     * 返回执行日志。
     */
    fun installToSystem(ctx: Context, onLine: (String) -> Unit): Boolean {
        val cert = ensureCa(ctx)
        if (cert == null) {
            onLine("生成 CA 失败")
            return false
        }
        val hash = subjectHash(cert)
        val pemFile = certFile(ctx).apply { writeText(pem(cert)) }

        val modDir = "/data/adb/modules/$MODULE_ID"
        val caDirSys = "$modDir/system/etc/security/cacerts"
        val propFile = File(caDir(ctx), "module.prop").apply {
            writeText(
                "id=$MODULE_ID\nname=Rowan MITM CA\nversion=1.0\nversionCode=1\n" +
                    "author=wuchun-by\n"
            )
        }
        val cmd = buildString {
            append("mkdir -p '$caDirSys' && ")
            append("cp '${pemFile.absolutePath}' '$caDirSys/$hash.0' && ")
            append("chmod 644 '$caDirSys/$hash.0' && ")
            append("cp '${propFile.absolutePath}' '$modDir/module.prop' && ")
            append("chmod 644 '$modDir/module.prop' && echo OK")
        }
        onLine("CA hash: $hash")
        return try {
            val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
            val out = p.inputStream.bufferedReader().readText()
            p.waitFor()
            val ok = out.contains("OK")
            onLine(if (ok) "已写入 $caDirSys/$hash.0\n重启后生效" else "安装失败：$out")
            ok
        } catch (e: Throwable) {
            onLine("安装失败：${e.message}")
            false
        }
    }

    fun readKey(ctx: Context): PrivateKey? = runCatching {
        keyFile(ctx).takeIf { it.exists() }?.readBytes()?.let { der ->
            val kf = java.security.KeyFactory.getInstance("RSA")
            val spec = java.security.spec.PKCS8EncodedKeySpec(der)
            kf.generatePrivate(spec)
        }
    }.getOrNull()
}
