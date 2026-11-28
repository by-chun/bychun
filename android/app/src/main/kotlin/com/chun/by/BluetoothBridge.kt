package com.chun.by

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import androidx.core.content.ContextCompat
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * 蓝牙 BLE：扫描 / 连接 / 读特征 / 写特征 / 订阅通知。
 * 统一用一个 GattCallback 收所有事件，读/写/订阅各自用 CountDownLatch 阻塞等结果，
 * 方便 AI 工具一次调用拿到返回值。
 * Android 12+ 需 BLUETOOTH_SCAN / BLUETOOTH_CONNECT；11- 需位置权限。
 */
object BluetoothBridge {
    // 每个已连接设备的会话状态
    private class GattSession {
        var gatt: BluetoothGatt? = null
        val readLatch = AtomicReference<CountDownLatch?>()
        val writeLatch = AtomicReference<CountDownLatch?>()
        val readValue = AtomicReference<ByteArray?>()
        var writeOk = false
        val notify = AtomicReference<StringBuilder>()
        var connected = false
    }

    private val sessions = ConcurrentHashMap<String, GattSession>()

    @SuppressLint("MissingPermission")
    fun hasPermission(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 31) {
            return ContextCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        }
        return LocationBridge.hasPermission(ctx)
    }

    @SuppressLint("MissingPermission")
    private fun adapter(ctx: Context): BluetoothAdapter? {
        if (!hasPermission(ctx)) return null
        val bm = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter
    }

    fun state(ctx: Context): Map<String, Any> {
        val a = adapter(ctx) ?: return mapOf("ok" to false, "error" to "蓝牙不可用或无权限")
        return mapOf("ok" to true, "enabled" to a.isEnabled, "name" to (a.name ?: ""))
    }

    @SuppressLint("MissingPermission")
    fun scan(ctx: Context, seconds: Int): Map<String, Any> {
        val a = adapter(ctx) ?: return mapOf("ok" to false, "error" to "蓝牙不可用或无权限")
        if (!a.isEnabled) return mapOf("ok" to false, "error" to "蓝牙没开")
        val found = ConcurrentHashMap<String, ScanResult>()
        val latch = CountDownLatch(1)
        var scanner: android.bluetooth.le.BluetoothLeScanner? = null
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                found[result.device.address] = result
            }
            override fun onScanFailed(errorCode: Int) { latch.countDown() }
        }
        try {
            scanner = a.bluetoothLeScanner
            scanner?.startScan(cb)
        } catch (e: Throwable) {
            return mapOf("ok" to false, "error" to "开始扫描失败：${e.message}")
        }
        val stop = Runnable { runCatching { scanner?.stopScan(cb) }; latch.countDown() }
        Thread { try { Thread.sleep(seconds * 1000L) } catch (_: Throwable) {} finally { stop.run() } }.start()
        try { latch.await((seconds + 3).toLong(), TimeUnit.SECONDS) } catch (_: Throwable) {}
        runCatching { scanner?.stopScan(cb) }
        val list = found.values.sortedByDescending { it.rssi }.map {
            mapOf("name" to (it.device.name ?: "（未知）"), "address" to (it.device.address ?: ""), "rssi" to it.rssi)
        }
        return mapOf("ok" to true, "devices" to list)
    }

    @SuppressLint("MissingPermission")
    fun connect(ctx: Context, address: String): Map<String, Any> {
        val a = adapter(ctx) ?: return mapOf("ok" to false, "error" to "蓝牙不可用或无权限")
        disconnect(address)
        val dev = a.getRemoteDevice(address)
        val session = GattSession()
        sessions[address] = session
        val latch = CountDownLatch(1)
        @Suppress("DEPRECATION")
        val gatt = dev.connectGatt(ctx, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    session.connected = true
                    g.discoverServices()
                } else {
                    session.connected = false
                    session.readLatch.get()?.countDown()
                    session.writeLatch.get()?.countDown()
                    latch.countDown()
                }
            }
            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                latch.countDown()
            }
            override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                session.readValue.set(c.value)
                session.readLatch.get()?.countDown()
            }
            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                session.writeOk = status == BluetoothGatt.GATT_SUCCESS
                session.writeLatch.get()?.countDown()
            }
            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
                session.notify.get().append(Base64.encodeToString(c.value ?: ByteArray(0), Base64.NO_WRAP)).append("\n")
            }
        }) ?: run {
            sessions.remove(address)
            return mapOf("ok" to false, "error" to "connectGatt 返回 null")
        }
        session.gatt = gatt
        session.notify.set(StringBuilder())
        try { latch.await(15, TimeUnit.SECONDS) } catch (_: Throwable) {}
        if (!session.connected) {
            sessions.remove(address)
            runCatching { gatt.disconnect(); gatt.close() }
            return mapOf("ok" to false, "error" to "连接失败或断开")
        }
        val services = gatt.services.map { s ->
            mapOf("uuid" to s.uuid.toString(), "chars" to s.characteristics.map { it.uuid.toString() })
        }
        return mapOf("ok" to true, "services" to services)
    }

    private fun sessionOf(address: String): GattSession? = sessions[address]

    private fun findChar(g: BluetoothGatt, sUuid: String?, cUuid: String): BluetoothGattCharacteristic? {
        for (s in g.services) {
            if (sUuid != null && s.uuid.toString() != sUuid) continue
            for (c in s.characteristics) if (c.uuid.toString() == cUuid) return c
        }
        return null
    }

    @SuppressLint("MissingPermission")
    fun read(address: String, sUuid: String?, cUuid: String): Map<String, Any> {
        val s = sessionOf(address) ?: return mapOf("ok" to false, "error" to "未连接（先 connect）")
        val g = s.gatt ?: return mapOf("ok" to false, "error" to "未连接")
        val c = findChar(g, sUuid, cUuid) ?: return mapOf("ok" to false, "error" to "没找到该特征")
        val latch = CountDownLatch(1)
        s.readLatch.set(latch)
        s.readValue.set(null)
        val ok = g.readCharacteristic(c)
        if (!ok) return mapOf("ok" to false, "error" to "发起读取失败")
        try { latch.await(10, TimeUnit.SECONDS) } catch (_: Throwable) {}
        val v = s.readValue.get() ?: c.value
        val text = v?.let { String(it, Charsets.UTF_8) }
        return mapOf(
            "ok" to true,
            "base64" to Base64.encodeToString(v ?: ByteArray(0), Base64.NO_WRAP),
            "text" to (text ?: ""),
        )
    }

    @SuppressLint("MissingPermission")
    fun write(address: String, sUuid: String?, cUuid: String, data: ByteArray, wait: Boolean): Map<String, Any> {
        val s = sessionOf(address) ?: return mapOf("ok" to false, "error" to "未连接（先 connect）")
        val g = s.gatt ?: return mapOf("ok" to false, "error" to "未连接")
        val c = findChar(g, sUuid, cUuid) ?: return mapOf("ok" to false, "error" to "没找到该特征")
        c.value = data
        c.writeType = if (wait) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        val latch = CountDownLatch(1)
        s.writeLatch.set(latch)
        s.writeOk = false
        val ok = g.writeCharacteristic(c)
        if (!ok) return mapOf("ok" to false, "error" to "发起写入失败")
        if (wait) {
            try { latch.await(10, TimeUnit.SECONDS) } catch (_: Throwable) {}
            if (!s.writeOk) return mapOf("ok" to false, "error" to "写入无响应")
        }
        return mapOf("ok" to true, "written" to data.size)
    }

    @SuppressLint("MissingPermission")
    fun subscribe(address: String, sUuid: String?, cUuid: String, seconds: Int): Map<String, Any> {
        val s = sessionOf(address) ?: return mapOf("ok" to false, "error" to "未连接（先 connect）")
        val g = s.gatt ?: return mapOf("ok" to false, "error" to "未连接")
        val c = findChar(g, sUuid, cUuid) ?: return mapOf("ok" to false, "error" to "没找到该特征")
        s.notify.set(StringBuilder())
        g.setCharacteristicNotification(c, true)
        // 有些设备还要写 0x0100 到 CCCD descriptor 才真正收到通知
        c.descriptors.firstOrNull { it.uuid.toString().endsWith("2902") }?.let { d ->
            d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            g.writeDescriptor(d)
        }
        try { Thread.sleep(seconds * 1000L) } catch (_: Throwable) {}
        val raw = s.notify.get().toString().trim()
        return mapOf("ok" to true, "notifications" to raw.split("\n").filter { it.isNotEmpty() })
    }

    fun disconnect(address: String): Map<String, Any> {
        val s = sessions.remove(address)
        s?.gatt?.let { runCatching { it.disconnect(); it.close() } }
        return mapOf("ok" to true)
    }
}
