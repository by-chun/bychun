import 'dart:io';

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// 屏幕采集（无障碍，无需 root）：读屏 / 截图 / 点按 / 滑动 / 输入。
/// 采集到的数据交给 AI；OCR/视觉分析等「处理」放容器里。

class ScreenDumpTool extends AgentTool {
  @override
  String get name => 'screenDump';
  @override
  String get description =>
      '读屏：拿当前屏幕所有控件（文字/描述/坐标/是否可点击/可输入），用于判断下一步操作。需先开无障碍。';
  @override
  Map<String, String> get parameters => {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    if (!await NativeBridge.screenEnabled()) {
      await NativeBridge.screenOpenSettings();
      return const ToolResult(false, '无障碍未开启，已打开设置页，请开启「Rowan 读屏」后重试');
    }
    final nodes = await NativeBridge.screenDump();
    if (nodes.isEmpty) return const ToolResult(false, '没读到屏幕（当前界面可能是系统页 / 无控件）');
    final items = <Map<String, String>>[];
    for (final n in nodes) {
      final t = '${n['text'] ?? ''}${(n['desc']?.isNotEmpty ?? false) ? ' · ${n['desc']}' : ''}';
      final c = (n['cls'] ?? '').toString();
      final badge = n['clickable'] == true
          ? '可点'
          : (n['editable'] == true ? '输入' : (n['scrollable'] == true ? '可滚' : ''));
      items.add({
        'title': t.isEmpty ? c : t,
        'subtitle': '$c @ ${n['x']},${n['y']}',
        if (badge.isNotEmpty) 'badge': badge,
      });
    }
    return ToolResult(
      true,
      '读到 ${items.length} 个控件，已列在窗口',
      view: 'list',
      title: '读屏 · ${items.length} 项',
      viewData: {'items': items},
    );
  }
}

class ScreenshotTool extends AgentTool {
  @override
  String get name => 'screenshot';
  @override
  String get description =>
      '截图：取当前屏幕一帧，写到 /sdcard/Rowan/shots/latest.png（单文件每次覆盖，不累积）。'
      '容器里直接读这个路径给视觉模型 / OCR。需无障碍或 root。';
  @override
  Map<String, String> get parameters => {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final bytes = await NativeBridge.screenShot();
    if (bytes == null || bytes.isEmpty) {
      return const ToolResult(false, '截图失败（无障碍未开且无 root）');
    }
    try {
      final f = File('/sdcard/Rowan/shots/latest.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return ToolResult(true,
          '已截图（${bytes.length} 字节）→ /sdcard/Rowan/shots/latest.png（单文件覆盖，不累积）');
    } catch (e) {
      return ToolResult(false, '截图成功但写临时文件失败：$e');
    }
  }
}

class ScreenTapTool extends AgentTool {
  @override
  String get name => 'screenTap';
  @override
  String get description => '点击屏幕坐标（x, y）。需先开无障碍。';
  @override
  Map<String, String> get parameters => {'x': '横坐标', 'y': '纵坐标'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final x = int.tryParse(args['x'] ?? '');
    final y = int.tryParse(args['y'] ?? '');
    if (x == null || y == null) return const ToolResult(false, 'x/y 需为整数');
    final ok = await NativeBridge.screenTap(x, y);
    return ToolResult(ok, ok ? '已点击 ($x, $y)' : '点击失败（无障碍未开）');
  }
}

class ScreenSwipeTool extends AgentTool {
  @override
  String get name => 'screenSwipe';
  @override
  String get description => '滑动屏幕，从 (x1,y1) 到 (x2,y2)。ms 是时长毫秒，默认 300。需先开无障碍。';
  @override
  Map<String, String> get parameters => {
        'x1': '起点横', 'y1': '起点纵', 'x2': '终点横', 'y2': '终点纵', 'ms': '时长，默认300',
      };
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final x1 = int.tryParse(args['x1'] ?? '');
    final y1 = int.tryParse(args['y1'] ?? '');
    final x2 = int.tryParse(args['x2'] ?? '');
    final y2 = int.tryParse(args['y2'] ?? '');
    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      return const ToolResult(false, '坐标需为整数');
    }
    final ms = int.tryParse(args['ms'] ?? '300') ?? 300;
    final ok = await NativeBridge.screenSwipe(x1, y1, x2, y2, ms: ms);
    return ToolResult(ok, ok ? '已滑动' : '滑动失败（无障碍未开）');
  }
}

class ScreenTypeTool extends AgentTool {
  @override
  String get name => 'screenType';
  @override
  String get description => '在当前聚焦的输入框输入文字。需先开无障碍，且要先 screenTap 聚焦到输入框。';
  @override
  Map<String, String> get parameters => {'text': '要输入的文字'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final text = args['text'] ?? '';
    if (text.isEmpty) return const ToolResult(false, 'text 不能为空');
    final ok = await NativeBridge.screenType(text);
    return ToolResult(ok, ok ? '已输入' : '输入失败（无障碍未开或无输入框焦点）');
  }
}

class RecordStartTool extends AgentTool {
  @override
  String get name => 'recordStart';
  @override
  String get description =>
      '开始录屏（MediaProjection），返回 MP4 路径；录完用 recordStop 停止。首次会弹录屏授权框。';
  @override
  Map<String, String> get parameters => {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = await NativeBridge.recordStart();
    if (path == null) return const ToolResult(false, '录屏失败（用户拒绝授权或设备不支持）');
    return ToolResult(true, '已开始录屏：$path\n录完调用 recordStop');
  }
}

class RecordStopTool extends AgentTool {
  @override
  String get name => 'recordStop';
  @override
  String get description => '停止录屏，返回 MP4 路径。';
  @override
  Map<String, String> get parameters => {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = await NativeBridge.recordStop();
    if (path == null) return const ToolResult(false, '当前没有在录屏');
    return ToolResult(true, '已停止，录像文件：$path');
  }
}

void registerScreenTools(ToolRegistry reg) {
  reg.register(ScreenDumpTool());
  reg.register(ScreenshotTool());
  reg.register(ScreenTapTool());
  reg.register(ScreenSwipeTool());
  reg.register(ScreenTypeTool());
  reg.register(RecordStartTool());
  reg.register(RecordStopTool());
}
