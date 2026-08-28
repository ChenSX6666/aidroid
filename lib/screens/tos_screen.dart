import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';

class TosScreen extends StatefulWidget {
  const TosScreen({super.key});

  @override
  State<TosScreen> createState() => _TosScreenState();
}

class _TosScreenState extends State<TosScreen> {
  bool _agreed = false;

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tos_accepted', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
    }
  }

  void _decline() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('您需要同意服务协议才能使用 Aidroid。确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              if (Platform.isAndroid) {
                SystemNavigator.pop();
              } else {
                exit(0);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D7CB5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'A',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Aidroid',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '手机智能助手',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '服务协议 & 隐私政策',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSection('服务协议', [
                        'Aidroid 是一个手机智能助手应用，提供 AI 对话和手机自动化操控功能。',
                        '本应用需要 Root 权限以执行手机操控命令，仅在用户明确授权后使用。',
                        '用户应遵守相关法律法规，不得将本应用用于任何违法用途。',
                        '开发者对本应用的稳定性不作任何明示或暗示的保证。',
                      ]),
                      const SizedBox(height: 12),
                      _buildSection('免责声明', [
                        '本软件为免费开源项目，仅供学习、研究和技术交流使用。',
                        '使用者因使用本软件所产生的任何后果（包括但不限于：账号封禁、数据丢失、法律纠纷、财产损失等），均由使用者本人独立承担，开发者不承担任何形式的责任。',
                        '开发者与使用者之间不构成任何服务关系、委托关系或合作关系。使用者下载、安装、使用本软件即视为完全理解并接受本免责声明的全部内容。',
                        '禁止用于：自动化刷量/刷单/薅羊毛、绕过安全机制、侵犯他人隐私、未经授权操控他人设备、传播违法信息等任何违法违规用途。',
                        '自动化操作第三方应用可能违反其服务协议，使用者应自行评估风险。若因此产生纠纷，与开发者无关。',
                      ]),
                      const SizedBox(height: 12),
                      _buildSection('隐私政策', [
                        '本应用不会收集、存储或上传您的个人身份信息到任何远程服务器。',
                        'API Key 等敏感信息仅加密存储在您的设备本地。',
                        '对话记录存储在您的设备本地，不会上传至任何第三方。',
                        '应用不会追踪您的使用行为或设备信息。',
                        '您有权随时删除所有本地数据（卸载应用即可）。',
                      ]),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _agreed = !_agreed),
                            child: Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _agreed
                                      ? const Color(0xFF0D7CB5)
                                      : const Color(0xFF9CA3AF),
                                  width: 2,
                                ),
                                color: _agreed
                                    ? const Color(0xFF0D7CB5)
                                    : Colors.transparent,
                              ),
                              child: _agreed
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          ),
                          Flexible(
                            child: GestureDetector(
                              onTap: () => setState(() => _agreed = !_agreed),
                              child: Text(
                                '我已阅读并同意服务协议和隐私政策',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _agreed ? _accept : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7CB5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('同意并继续', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _decline,
                  child: Text(
                    '不同意并退出',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('  ', style: TextStyle(fontSize: 13)),
              const Text('  ', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
