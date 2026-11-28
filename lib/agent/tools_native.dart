import 'dart:convert';

import '../native/native_bridge.dart';
import 'tool.dart';

/// 定位 + 蓝牙 + 浏览器 工具（都走原生 Android API，容器替不了）。
void registerNativeTools(ToolRegistry reg) {
  reg.register(GetLocationTool());
  reg.register(BluetoothStateTool());
  reg.register(BluetoothScanTool());
  reg.register(BluetoothConnectTool());
  reg.register(BluetoothReadTool());
  reg.register(BluetoothWriteTool());
  reg.register(BluetoothSubscribeTool());
  reg.register(BrowserOpenTool());
  reg.register(BrowserExecJsTool());
  reg.register(BrowserSnapshotTool());
}

/// 定位：读最后已知位置。
class GetLocationTool extends AgentTool {
  @override
  String get name => 'getLocation';

  @override
  String get description => '读当前设备大致位置（最后已知的 GPS/网络定位）。首次需授权定位权限；拿不到说明定位服务没开。';

  @override
  Map<String, String> get parameters => {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final r = await NativeBridge.getLocation();
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '定位失败').toString());
    return ToolResult(
      true,
      '纬度 ${r['lat']}，经度 ${r['lng']}，精度 ±${(r['accuracy'] as num?)?.toStringAsFixed(0) ?? '?'}m（${r['provider']}）',
    );
  }
}

/// 蓝牙状态。
class BluetoothStateTool extends AgentTool {
  @override
  String get name => 'bluetoothState';

  @override
  String get description => '查蓝牙开关状态与设备名。';

  @override
  Map<String, String> get parameters => {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final r = await NativeBridge.bluetoothState();
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '蓝牙不可用').toString());
    return ToolResult(true, '蓝牙${r['enabled'] == true ? '已开' : '已关'}，设备名 ${r['name']}');
  }
}

/// 扫描 BLE 设备。
class BluetoothScanTool extends AgentTool {
  @override
  String get name => 'bluetoothScan';

  @override
  String get description => '扫描附近蓝牙/BLE 设备，返回名称、地址、信号强度。Android 12+ 需蓝牙权限。';

  @override
  Map<String, String> get parameters => {'seconds': '扫描时长（秒），默认 5'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final sec = int.tryParse(args['seconds'] ?? '') ?? 5;
    final r = await NativeBridge.bluetoothScan(sec);
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '扫描失败').toString());
    final devs = (r['devices'] as List?) ?? const [];
    if (devs.isEmpty) return const ToolResult(true, '没扫到设备');
    return ToolResult(
      true,
      '扫到 ${devs.length} 个设备',
      view: 'list',
      title: '蓝牙设备',
      viewData: {
        'items': [
          for (final d in devs)
            {'title': d['name'], 'subtitle': d['address'], 'badge': '${d['rssi']} dBm'}
        ],
      },
    );
  }
}

/// 连接 BLE 设备。
class BluetoothConnectTool extends AgentTool {
  @override
  String get name => 'bluetoothConnect';

  @override
  String get description => '连接一个蓝牙 BLE 设备（用 bluetoothScan 拿到的 address），返回服务/特征 UUID 列表。';

  @override
  Map<String, String> get parameters => {'address': '设备 MAC 地址'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final addr = (args['address'] ?? '').trim();
    if (addr.isEmpty) return const ToolResult(false, 'address 不能为空');
    final r = await NativeBridge.bluetoothConnect(addr);
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '连接失败').toString());
    final svcs = (r['services'] as List?) ?? const [];
    final buf = StringBuffer();
    for (final s in svcs) {
      buf.writeln('服务 ${s['uuid']}');
      for (final c in (s['chars'] as List? ?? const [])) {
        buf.writeln('  特征 $c');
      }
    }
    return ToolResult(true, '已连接，服务列表：\n$buf');
  }
}

/// 读特征。
class BluetoothReadTool extends AgentTool {
  @override
  String get name => 'bluetoothRead';

  @override
  String get description => '读一个蓝牙特征值。service 可留空。返回 base64 与可读文本。';

  @override
  Map<String, String> get parameters => {
        'address': '设备 MAC',
        'service': '服务 UUID（可留空）',
        'char': '特征 UUID',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final addr = (args['address'] ?? '').trim();
    final svc = (args['service'] ?? '').trim();
    final ch = (args['char'] ?? '').trim();
    if (addr.isEmpty || ch.isEmpty) return const ToolResult(false, 'address 和 char 不能为空');
    final r = await NativeBridge.bluetoothRead(addr, svc.isEmpty ? null : svc, ch);
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '读取失败').toString());
    return ToolResult(true, 'base64: ${r['base64']}\n文本: ${r['text']}');
  }
}

/// 写特征。
class BluetoothWriteTool extends AgentTool {
  @override
  String get name => 'bluetoothWrite';

  @override
  String get description => '写一个蓝牙特征值。data 为要写入的内容（UTF-8 编码）。';

  @override
  Map<String, String> get parameters => {
        'address': '设备 MAC',
        'service': '服务 UUID（可留空）',
        'char': '特征 UUID',
        'data': '要写入的文本',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final addr = (args['address'] ?? '').trim();
    final svc = (args['service'] ?? '').trim();
    final ch = (args['char'] ?? '').trim();
    final data = args['data'] ?? '';
    if (addr.isEmpty || ch.isEmpty) return const ToolResult(false, 'address 和 char 不能为空');
    final b64 = base64Encode(utf8.encode(data));
    final r = await NativeBridge.bluetoothWrite(addr, svc.isEmpty ? null : svc, ch, b64);
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '写入失败').toString());
    return ToolResult(true, '已写入 ${r['written']} 字节');
  }
}

/// 订阅通知。
class BluetoothSubscribeTool extends AgentTool {
  @override
  String get name => 'bluetoothSubscribe';

  @override
  String get description => '订阅一个蓝牙特征的通知，监听几秒后返回收到的数据。';

  @override
  Map<String, String> get parameters => {
        'address': '设备 MAC',
        'service': '服务 UUID（可留空）',
        'char': '特征 UUID',
        'seconds': '监听时长（秒），默认 5',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final addr = (args['address'] ?? '').trim();
    final svc = (args['service'] ?? '').trim();
    final ch = (args['char'] ?? '').trim();
    final sec = int.tryParse(args['seconds'] ?? '') ?? 5;
    if (addr.isEmpty || ch.isEmpty) return const ToolResult(false, 'address 和 char 不能为空');
    final r = await NativeBridge.bluetoothSubscribe(addr, svc.isEmpty ? null : svc, ch, sec);
    if (r['ok'] != true) return ToolResult(false, (r['error'] ?? '订阅失败').toString());
    final notes = (r['notifications'] as List?) ?? const [];
    return ToolResult(true, notes.isEmpty ? '监听到 ${sec}s，没有收到通知' : '收到 ${notes.length} 条通知：\n${notes.join('\n')}');
  }
}

/// 打开内置浏览器。
class BrowserOpenTool extends AgentTool {
  @override
  String get name => 'browserOpen';

  @override
  String get description => '打开内置浏览器访问一个网址。之后可用 browserSnapshot 读页面文本、browserExecJs 执行脚本、用 screenTap 点击。';

  @override
  Map<String, String> get parameters => {'url': '网址'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    if (url.isEmpty) return const ToolResult(false, 'url 不能为空');
    final ok = await NativeBridge.browserOpen(url);
    return ToolResult(ok, ok ? '已打开 $url（可用 browserSnapshot 读内容）' : '打开失败');
  }
}

/// 执行 JS。
class BrowserExecJsTool extends AgentTool {
  @override
  String get name => 'browserExecJs';

  @override
  String get description => '在内置浏览器的当前页面执行一段 JavaScript，返回结果（字符串）。可用于读数据、填表、点击等。';

  @override
  Map<String, String> get parameters => {'js': 'JavaScript 代码'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final js = args['js'] ?? '';
    if (js.isEmpty) return const ToolResult(false, 'js 不能为空');
    final r = await NativeBridge.browserExecJs(js);
    return ToolResult(true, r.isEmpty ? '（无返回值）' : r);
  }
}

/// 页面快照。
class BrowserSnapshotTool extends AgentTool {
  @override
  String get name => 'browserSnapshot';

  @override
  String get description => '读内置浏览器当前页面的纯文本内容（body.innerText），用于理解页面。';

  @override
  Map<String, String> get parameters => {'max': '最大字符数，默认 4000'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final max = int.tryParse(args['max'] ?? '') ?? 4000;
    final r = await NativeBridge.browserSnapshot(max: max);
    return ToolResult(true, r.isEmpty ? '（页面为空或浏览器没打开）' : r);
  }
}
