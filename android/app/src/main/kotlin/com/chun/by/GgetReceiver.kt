package com.chun.by

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File
import java.util.UUID

/**
 * 终端里 `gget` 命令的落地端：shell 函数通过 am broadcast 把 url/name 发过来，
 * 这里在后台下载解压，并把进度追加到 filesDir/tmp/gget.log 供脚本 tail。
 *
 * 用 token 校验来源：token 只存在于 app 私有目录，别的 app 读不到，避免任意 URL 被外部触发。
 */
class GgetReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra("token") ?: return
        val expected = tokenFile(context).takeIf { it.exists() }?.readText()?.trim().orEmpty()
        if (expected.isEmpty() || token != expected) return

        if (intent.action == ACTION_SU) {
            runSuCommand(context, intent.getStringExtra("cmd")?.trim().orEmpty())
            return
        }
        if (intent.action != ACTION) return

        val url = intent.getStringExtra("url")?.trim().orEmpty()
        val name = intent.getStringExtra("name")?.trim().orEmpty()
        if (url.isEmpty() || name.isEmpty()) return

        val log = File(context.filesDir, "tmp/gget.log").apply { parentFile?.mkdirs() }
        log.writeText("")
        // 进程此时在前台（用户在终端里敲命令），直接起线程即可，不走 goAsync 以免 10 秒超时
        Thread {
            val ok = try {
                ProotLauncher.installFromUrl(context, url, name) { line ->
                    log.appendText("$line\n")
                }
            } catch (e: Throwable) {
                log.appendText("ERROR ${e.message}\n")
                false
            }
            log.appendText(if (ok) "DONE:$name\n" else "FAIL:$name\n")
        }.start()
    }

    /** 容器内 gsu：用宿主 su 执行命令，输出写 filesDir/tmp/gsu.out 供脚本回显。 */
    private fun runSuCommand(context: Context, cmd: String) {
        if (cmd.isEmpty()) return
        val out = File(context.filesDir, "tmp/gsu.out").apply { parentFile?.mkdirs() }
        out.writeText("")
        Thread {
            val text = try {
                val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
                val t = p.inputStream.bufferedReader().readText()
                p.waitFor()
                t
            } catch (e: Throwable) {
                "ERROR ${e.message}\n"
            }
            out.writeText(text + "__EXIT__\n")
        }.start()
    }

    companion object {
        const val ACTION = "com.chun.by.GGET"
        const val ACTION_SU = "com.chun.by.GSU"

        private fun tokenFile(ctx: Context) = File(ctx.filesDir, "gget.token")

        /**
         * 生成 gget 命令：$ENV 指向这个文件，交互 shell 启动时自动载入函数定义。
         * 只定义 shell 函数，不落地可执行文件（Android 10+ 禁止 exec app 私有目录）。
         */
        fun ensureShellRc(ctx: Context) {
            val dir = File(ctx.filesDir, "bin").apply { mkdirs() }
            val tf = tokenFile(ctx)
            if (!tf.exists()) tf.writeText(UUID.randomUUID().toString().replace("-", ""))
            val files = ctx.filesDir.absolutePath
            val rc = File(dir, "shellrc")
            rc.writeText(
                """
                gbind() {
                    _conf="$files/bindings.conf"
                    case "${'$'}1" in
                        ""|list)
                            echo "默认: /sdcard:/sdcard"
                            if [ -f "${'$'}_conf" ]; then echo "自定义:"; cat "${'$'}_conf"; fi
                            ;;
                        add)
                            if [ -z "${'$'}2" ]; then echo "用法: gbind add 源:目标"; return 1; fi
                            echo "${'$'}2" >> "${'$'}_conf"
                            echo "已添加 ${'$'}2（新开的容器标签生效）"
                            ;;
                        del)
                            if [ -z "${'$'}2" ]; then echo "用法: gbind del 源:目标"; return 1; fi
                            grep -vxF "${'$'}2" "${'$'}_conf" > "${'$'}_conf.tmp" 2>/dev/null
                            mv "${'$'}_conf.tmp" "${'$'}_conf" 2>/dev/null
                            echo "已删除 ${'$'}2"
                            ;;
                        reset)
                            rm -f "${'$'}_conf"
                            echo "已恢复默认绑定（/sdcard）"
                            ;;
                        *)
                            echo "用法: gbind [list | add 源:目标 | del 源:目标 | reset]"
                            ;;
                    esac
                }
                gsu() {
                    if [ -z "${'$'}1" ]; then echo "用法: gsu <命令>"; return 1; fi
                    _out="$files/tmp/gsu.out"
                    rm -f "${'$'}_out"
                    _token=${'$'}(cat "$files/gget.token")
                    /system/bin/am broadcast -a com.chun.by.GSU --es token "${'$'}_token" --es cmd "${'$'}*" >/dev/null 2>&1
                    _i=0
                    while [ ${'$'}_i -lt 120 ]; do
                        if [ -f "${'$'}_out" ] && grep -q "__EXIT__" "${'$'}_out" 2>/dev/null; then
                            sed "/__EXIT__/d" "${'$'}_out"
                            return 0
                        fi
                        sleep 1
                        _i=$((_i+1))
                    done
                    echo "超时（可能需要先授权 su）"
                    return 1
                }
                gget() {
                    if [ -z "${'$'}1" ]; then echo "用法: gget <rootfs直链> [容器名]"; return 1; fi
                    _url="${'$'}1"
                    _name="${'$'}2"
                    if [ -z "${'$'}_name" ]; then _name=$(basename "${'$'}_url" | sed 's/\..*//'); fi
                    _log="$files/tmp/gget.log"
                    mkdir -p "$files/tmp"
                    rm -f "${'$'}_log"
                    _token=$(cat "$files/gget.token")
                    /system/bin/am broadcast -a com.chun.by.GGET --es token "${'$'}_token" \
                        --es url "${'$'}_url" --es name "${'$'}_name" >/dev/null 2>&1
                    echo "开始安装 ${'$'}_name …"
                    _last=""
                    _i=0
                    while [ ${'$'}_i -lt 1800 ]; do
                        if [ -f "${'$'}_log" ]; then
                            _line=$(tail -n 1 "${'$'}_log")
                            if [ "${'$'}_line" != "${'$'}_last" ]; then echo "${'$'}_line"; _last="${'$'}_line"; fi
                            case "${'$'}_line" in
                                DONE:*) echo "安装完成：${'$'}_name"; return 0 ;;
                                FAIL:*) echo "安装失败：${'$'}_name"; return 1 ;;
                            esac
                        fi
                        sleep 1
                        _i=$((_i+1))
                    done
                    echo "超时"
                    return 1
                }
                """.trimIndent() + "\n"
            )
        }
    }
}
