import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'theme/glass.dart';
import 'state/drawer_ctrl.dart';
import 'widgets/tree_drawer.dart';
import 'pages/chat_page.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    DrawerCtrl.close = () => _scaffoldKey.currentState?.closeDrawer();
    DrawerCtrl.open = () => _scaffoldKey.currentState?.openDrawer();
  }

  @override
  void dispose() {
    DrawerCtrl.close = null;
    DrawerCtrl.open = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 40,
      drawer: Drawer(
        width: 320,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(26)),
        ),
        child: TreeDrawer(
          onClose: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
      ),
      body: Container(
        decoration: glassBackground(),
        child: Stack(
          children: [
            const ChatPage(),
            Positioned(
              left: 12,
              top: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GlassIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
