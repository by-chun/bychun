import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/toast.dart';
import '../native/native_bridge.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});
  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  Future<void> _open() async {
    final ok = await NativeBridge.showOverlay();
    if (!mounted) return;
    showToast(context, ok ? '已打开内存悬浮窗' : '打开失败：先授予悬浮窗权限', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('内存', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.brandSoft, shape: BoxShape.circle),
                child: const Icon(Icons.memory_rounded, size: 30, color: AppColors.brand),
              ),
              const SizedBox(height: 12),
              const Text('内存搜索悬浮窗', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                '点开即在桌面上弹出搜索面板，搜索 / 指针 / 浏览 / 调试 / 已保存 都在悬浮窗里。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 16),
              GlassButton(label: '打开悬浮窗', icon: Icons.open_in_new_rounded, onTap: _open),
            ],
          ),
        ),
      ),
    );
  }
}
