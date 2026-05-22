import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';

/// Live tab introduced in Slice 2a. Today it offers the manual "Enter code"
/// path that drives the existing `/session/:joinCode` deep link. Slice 2b
/// adds a real camera-backed QR scanner; until then the Scan QR button is
/// disabled with a hint explaining that.
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _codeController.text.trim().isNotEmpty;

  void _submit() {
    final String code = _codeController.text.trim();
    if (code.isEmpty) {
      return;
    }
    context.go('/session/${Uri.encodeComponent(code)}');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaScaffold(
      title: MedRashStrings.liveTitle,
      bottomNav: true,
      showBack: true,
      child: ListView(
        children: <Widget>[
          Text(
            MedRashStrings.liveIntro,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ArenaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  MedRashStrings.liveEnterCodeTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  MedRashStrings.liveEnterCodeHelper,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: MedRashStrings.liveEnterCodeLabel,
                    hintText: 'ABCD',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                      borderSide: BorderSide(
                        color: tokens.outline,
                        width: tokens.borderWidth,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ArenaButton(
                  label: MedRashStrings.liveJoinCta,
                  icon: Icons.login_outlined,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ArenaCard(
            color: tokens.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  MedRashStrings.liveScanQrTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  MedRashStrings.liveScanQrHelper,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                const ArenaButton(
                  label: MedRashStrings.liveScanQrCta,
                  icon: Icons.qr_code_scanner_outlined,
                  backgroundColor: Colors.white,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
