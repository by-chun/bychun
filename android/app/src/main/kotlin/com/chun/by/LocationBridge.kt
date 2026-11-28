package com.chun.by

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat

/**
 * 定位：读系统最后已知位置（GPS / 网络两个 provider）。
 * 不启动持续定位，只取最后一次缓存，够 AI 判断大致位置用。
 * 需要 ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION 权限（运行时申请由 Dart 侧触发）。
 */
object LocationBridge {
    fun hasPermission(ctx: Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

    fun lastLocation(ctx: Context): Map<String, Any> {
        if (!hasPermission(ctx)) {
            return mapOf("ok" to false, "error" to "没有定位权限（需先授权）")
        }
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return mapOf("ok" to false, "error" to "LocationManager 不可用")
        var best: Location? = null
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        for (p in providers) {
            try {
                val loc = lm.getLastKnownLocation(p)
                if (loc != null && (best == null || loc.time > best!!.time)) best = loc
            } catch (_: Throwable) {
            }
        }
        if (best == null) {
            return mapOf("ok" to false, "error" to "拿不到位置（定位服务没开，或还没有缓存位置）")
        }
        val loc = best!!
        return mapOf(
            "ok" to true,
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy,
            "provider" to (loc.provider ?: ""),
            "time" to loc.time,
        )
    }
}
