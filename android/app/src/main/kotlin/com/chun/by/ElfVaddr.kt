package com.chun.by

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** 极简 ELF64 辅助：虚拟地址 <-> 文件偏移。 */
object ElfVaddr {
    data class Seg(val vaddr: Long, val offset: Long, val filesz: Long)

    fun segments(f: File): List<Seg> {
        val raf = RandomAccessFile(f, "r")
        try {
            val head = ByteArray(64)
            raf.readFully(head)
            if (head[0] != 0x7F.toByte() || head[1] != 'E'.code.toByte()) return emptyList()
            val bb = ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN)
            val phoff = bb.getLong(0x20)
            val phentsize = bb.getShort(0x36).toInt() and 0xFFFF
            val phnum = bb.getShort(0x38).toInt() and 0xFFFF
            val out = ArrayList<Seg>()
            for (i in 0 until phnum) {
                raf.seek(phoff + i.toLong() * phentsize)
                val ph = ByteArray(phentsize)
                raf.readFully(ph)
                val p = ByteBuffer.wrap(ph).order(ByteOrder.LITTLE_ENDIAN)
                val type = p.getInt(0)
                if (type != 1) continue // PT_LOAD
                val offset = p.getLong(0x08)
                val vaddr = p.getLong(0x10)
                val filesz = p.getLong(0x20)
                out.add(Seg(vaddr, offset, filesz))
            }
            return out
        } finally {
            raf.close()
        }
    }

    fun machine(f: File): Int {
        return try {
            val head = ByteArray(20)
            RandomAccessFile(f, "r").use { it.readFully(head) }
            ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN).getShort(0x12).toInt() and 0xFFFF
        } catch (e: Exception) { 0 }
    }

    fun segsOrEmpty(f: File): List<Seg> = try { segments(f) } catch (e: Exception) { emptyList() }

    fun toFileOffset(segs: List<Seg>, vaddr: Long): Long? {
        for (s in segs) {
            if (vaddr >= s.vaddr && vaddr < s.vaddr + s.filesz) {
                return s.offset + (vaddr - s.vaddr)
            }
        }
        return null
    }

    fun readAt(f: File, offset: Long, size: Int): ByteArray? {
        if (offset < 0) return null
        val raf = RandomAccessFile(f, "r")
        return try {
            if (offset >= raf.length()) return null
            val n = minOf(size.toLong(), raf.length() - offset).toInt()
            raf.seek(offset)
            val b = ByteArray(n)
            raf.readFully(b)
            b
        } catch (e: Exception) {
            null
        } finally {
            raf.close()
        }
    }
}
