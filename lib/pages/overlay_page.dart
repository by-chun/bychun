import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/number_field.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/toast.dart';
import '../native/native_bridge.dart';

class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key});
  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  double _size = 48;
  double _opacity = 0.8;
  bool _enabled = false;

  Future<void> _toggle(bool v) async {
    final ok = v ? await NativeBridge.showOverlay() : await NativeBridge.hideOverlay();
    setState(() => _enabled = v && ok);
    if (!ok && v && mounted) {
      showToast(context, '需要悬浮窗权限', error: false);
    }
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> onChanged, String suffix) {
    return NumberFieldRow(
      label: label,
      value: v,
      min: min,
      max: max,
      suffix: suffix,
      onChanged: onChanged,
    );
  }

  Future<void> _pickImage(String fileName) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return;
    await File(x.path).copy('$dir/$fileName');
    await NativeBridge.setOverlayPref(size: _size.round(), opacity: _opacity);
    if (mounted) {
      showToast(context, '已保存，重新打开悬浮窗生效', error: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('悬浮窗', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Row(children: [
              const Icon(Icons.layers_outlined, size: 20, color: AppColors.brand),
              const SizedBox(width: 12),
              const Expanded(child: Text('启用悬浮球', style: TextStyle(fontSize: 13.5))),
              Switch(value: _enabled, activeThumbColor: AppColors.brand, onChanged: _toggle),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                _slider('悬浮球大小', _size, 32, 80, (v) {
                  setState(() => _size = v);
                  NativeBridge.setOverlayPref(size: v.round(), opacity: _opacity);
                }, 'dp'),
                _slider('透明度', _opacity * 100, 20, 100, (v) {
                  setState(() => _opacity = v / 100);
                  NativeBridge.setOverlayPref(size: _size.round(), opacity: _opacity);
                }, '%'),
                const Divider(height: 1, color: AppColors.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('悬浮球图标', style: TextStyle(fontSize: 12.5)),
                  trailing: const Text('更换', style: TextStyle(fontSize: 12, color: AppColors.brand)),
                  onTap: () => _pickImage('overlay_icon.png'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('面板背景图', style: TextStyle(fontSize: 12.5)),
                  trailing: const Text('更换', style: TextStyle(fontSize: 12, color: AppColors.brand)),
                  onTap: () => _pickImage('overlay_bg.png'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
