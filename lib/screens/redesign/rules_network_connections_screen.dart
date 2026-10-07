import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../platform/livebridge_platform.dart';
import '../../theme/livebridge_tokens.dart';
import '../../utils/livebridge_haptics.dart';
import '../../widgets/redesign/lb_detail_screen.dart';
import '../../widgets/redesign/lb_icon.dart';
import '../../widgets/redesign/lb_info_title.dart';
import '../../widgets/redesign/lb_list_component.dart';
import '../../widgets/redesign/lb_slider.dart';
import '../../widgets/redesign/lb_toggle.dart';
import '../../widgets/redesign/lb_toast.dart';

class RulesNetworkConnectionsScreen extends StatefulWidget {
  const RulesNetworkConnectionsScreen({super.key});

  @override
  State<RulesNetworkConnectionsScreen> createState() =>
      _RulesNetworkConnectionsScreenState();
}

class _RulesNetworkConnectionsScreenState
    extends State<RulesNetworkConnectionsScreen> {
  static const int _thresholdStepBytesPerSecond = 8 * 1024;
  static const int _thresholdMaxBytesPerSecond = 1024 * 1024;

  bool _vpnEnabled = true;
  bool _externalDevicesEnabled = true;
  bool _ignoreDebuggingDevices = false;
  bool _networkSpeedEnabled = false;
  bool _networkSpeedHideWhenLocked = false;
  bool _savingHideWhenLocked = false;
  int _networkSpeedThresholdBytesPerSecond = 0;
  double _networkSpeedSliderValue = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadState());
    });
  }

  Future<void> _loadState() async {
    try {
      final Future<bool> vpnEnabledFuture =
          LiveBridgePlatform.getSmartVpnEnabled();
      final Future<bool> externalDevicesEnabledFuture =
          LiveBridgePlatform.getSmartExternalDevicesEnabled();
      final Future<bool> ignoreDebuggingFuture =
          LiveBridgePlatform.getSmartExternalDevicesIgnoreDebugging();
      final Future<bool> networkSpeedEnabledFuture =
          LiveBridgePlatform.getNetworkSpeedEnabled();
      final hideWhenLockedFuture =
          LiveBridgePlatform.getNetworkSpeedHideWhenLocked();
      final Future<int> networkSpeedThresholdFuture =
          LiveBridgePlatform.getNetworkSpeedMinThresholdBytesPerSecond();

      final bool vpnEnabled = await vpnEnabledFuture;
      final bool externalDevicesEnabled = await externalDevicesEnabledFuture;
      final bool ignoreDebuggingDevices = await ignoreDebuggingFuture;
      final bool networkSpeedEnabled = await networkSpeedEnabledFuture;
      final hideWhenLocked = await hideWhenLockedFuture;
      final int networkSpeedThresholdBytesPerSecond =
          await networkSpeedThresholdFuture;

      if (!mounted) {
        return;
      }

      setState(() {
        _vpnEnabled = vpnEnabled;
        _externalDevicesEnabled = externalDevicesEnabled;
        _ignoreDebuggingDevices = ignoreDebuggingDevices;
        _networkSpeedEnabled = networkSpeedEnabled;
        _networkSpeedHideWhenLocked = hideWhenLocked;
        _networkSpeedThresholdBytesPerSecond =
            networkSpeedThresholdBytesPerSecond.clamp(
              0,
              _thresholdMaxBytesPerSecond,
            );
        _networkSpeedSliderValue = _sliderPositionForBytesPerSecond(
          _networkSpeedThresholdBytesPerSecond,
        );
      });
    } catch (_) {}
  }

  Future<void> _setVpnEnabled(bool value) async {
    if (value == _vpnEnabled) {
      return;
    }
    setState(() => _vpnEnabled = value);
    await LiveBridgePlatform.setSmartVpnEnabled(value);
  }

  Future<void> _setExternalDevicesEnabled(bool value) async {
    if (value == _externalDevicesEnabled) {
      return;
    }
    setState(() => _externalDevicesEnabled = value);
    await LiveBridgePlatform.setSmartExternalDevicesEnabled(value);
  }

  Future<void> _setIgnoreDebuggingDevices(bool value) async {
    if (value == _ignoreDebuggingDevices) {
      return;
    }
    setState(() => _ignoreDebuggingDevices = value);
    await LiveBridgePlatform.setSmartExternalDevicesIgnoreDebugging(value);
  }

  Future<void> _setNetworkSpeedEnabled(bool value) async {
    if (value == _networkSpeedEnabled) {
      return;
    }
    setState(() => _networkSpeedEnabled = value);
    await LiveBridgePlatform.setNetworkSpeedEnabled(value);
  }

  Future<void> _setHideWhenLocked(bool value) async {
    if (_savingHideWhenLocked || value == _networkSpeedHideWhenLocked) return;
    setState(() => _savingHideWhenLocked = true);
    try {
      final saved = await LiveBridgePlatform.setNetworkSpeedHideWhenLocked(
        value,
      );
      if (!saved) {
        throw StateError("Setting was not saved");
      }
      if (mounted) setState(() => _networkSpeedHideWhenLocked = value);
    } catch (_) {
      if (mounted) {
        showLbToast(context, message: AppStrings.of(context).settingsSaveError);
      }
    } finally {
      if (mounted) setState(() => _savingHideWhenLocked = false);
    }
  }

  Future<void> _setNetworkSpeedThresholdBytesPerSecond(int value) async {
    final int normalized = value.clamp(0, _thresholdMaxBytesPerSecond);
    if (_networkSpeedThresholdBytesPerSecond != normalized && mounted) {
      setState(() => _networkSpeedThresholdBytesPerSecond = normalized);
    }
    await LiveBridgePlatform.setNetworkSpeedMinThresholdBytesPerSecond(
      normalized,
    );
  }

  int _snapThresholdBytesPerSecond(double sliderValue) {
    return (sliderValue.round() * _thresholdStepBytesPerSecond)
        .clamp(0, _thresholdMaxBytesPerSecond)
        .toInt();
  }

  double _sliderPositionForBytesPerSecond(int bytesPerSecond) {
    return (bytesPerSecond / _thresholdStepBytesPerSecond)
        .clamp(0, _thresholdMaxBytesPerSecond / _thresholdStepBytesPerSecond)
        .toDouble();
  }

  String _formatNetworkSpeedBytesPerSecond(int bytesPerSecond) {
    final int value = bytesPerSecond.clamp(0, 1 << 31).toInt();
    if (value <= 0) {
      return AppStrings.of(context).networkSpeedThresholdAlways;
    }
    if (value < 1024 * 1024) {
      return _formatCompactNetworkSpeedValue(value / 1024, 'kB/s');
    }
    if (value < 1024 * 1024 * 1024) {
      return _formatCompactNetworkSpeedValue(value / (1024 * 1024), 'MB/s');
    }
    return _formatCompactNetworkSpeedValue(
      value / (1024 * 1024 * 1024),
      'GB/s',
    );
  }

  String _formatCompactNetworkSpeedValue(double value, String suffix) {
    final String formatted = value < 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(0);
    return '$formatted $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final LbPalette palette = LbPalette.of(context);
    final double sliderMax =
        _thresholdMaxBytesPerSecond / _thresholdStepBytesPerSecond;

    final List<LbListItemData> primaryItems = <LbListItemData>[
      LbListItemData(
        title: strings.vpnsTitle,
        description: strings.vpnsDescription,
        showChevron: false,
        toggleValue: _vpnEnabled,
        onToggle: (bool value) {
          unawaited(_setVpnEnabled(value));
        },
        onTap: () {
          final bool nextValue = !_vpnEnabled;
          unawaited(LiveBridgeHaptics.toggle(nextValue));
          unawaited(_setVpnEnabled(nextValue));
        },
      ),
      LbListItemData(
        title: strings.externalDevicesTitle,
        description: strings.externalDevicesDescription,
        showChevron: false,
        toggleValue: _externalDevicesEnabled,
        onToggle: (bool value) {
          unawaited(_setExternalDevicesEnabled(value));
        },
        onTap: () {
          final bool nextValue = !_externalDevicesEnabled;
          unawaited(LiveBridgeHaptics.toggle(nextValue));
          unawaited(_setExternalDevicesEnabled(nextValue));
        },
      ),
      LbListItemData(
        title: strings.ignoreDebuggingDevicesTitle,
        description: strings.ignoreDebuggingDevicesDescription,
        showChevron: false,
        toggleValue: _ignoreDebuggingDevices,
        enabled: _externalDevicesEnabled,
        onToggle: _externalDevicesEnabled
            ? (bool value) {
                unawaited(_setIgnoreDebuggingDevices(value));
              }
            : null,
        onTap: _externalDevicesEnabled
            ? () {
                final bool nextValue = !_ignoreDebuggingDevices;
                unawaited(LiveBridgeHaptics.toggle(nextValue));
                unawaited(_setIgnoreDebuggingDevices(nextValue));
              }
            : null,
      ),
    ];

    return LbDetailScreen(
      title: strings.networkConnectionsTitle,
      children: <Widget>[
        LbListComponent(
          items: primaryItems,
          rowHeight: LbSpacing.recentRowHeight,
          extendDividersToEnd: true,
        ),
        const SizedBox(height: LbSpacing.md),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(LbRadius.card),
          ),
          child: Column(
            children: <Widget>[
              SizedBox(
                height: LbSpacing.recentRowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: LbSpacing.md),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: LbSpacing.listTextOnlyInset),
                      Expanded(
                        child: LbInfoTitle(
                          title: strings.networkSpeedTitle,
                          description: strings.networkSpeedDescription,
                          titleStyle: LbTextStyles.body.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      LbToggle(
                        value: _networkSpeedEnabled,
                        onChanged: (bool value) {
                          unawaited(_setNetworkSpeedEnabled(value));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: LbSpacing.listTextOnlyInset + LbSpacing.md,
                ),
                child: Divider(
                  height: LbSpacing.recentSeparatorThickness,
                  thickness: LbSpacing.recentSeparatorThickness,
                  color: palette.recentSeparator,
                ),
              ),
              LbListComponent(
                items: [
                  LbListItemData(
                    title: strings.networkSpeedHideWhenLocked,
                    description: strings.networkSpeedHideWhenLockedHelp,
                    toggleValue: _networkSpeedHideWhenLocked,
                    enabled: !_savingHideWhenLocked,
                    onToggle: (value) {
                      unawaited(_setHideWhenLocked(value));
                    },
                    showChevron: false,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LbSpacing.md + LbSpacing.listTextOnlyInset,
                  LbSpacing.md,
                  LbSpacing.md,
                  LbSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: LbInfoTitle(
                            title: strings.networkSpeedThresholdRedesignTitle,
                            description:
                                strings.networkSpeedThresholdDescription,
                            titleStyle: LbTextStyles.body.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: LbSpacing.sliderValueGap),
                        Text(
                          _formatNetworkSpeedBytesPerSecond(
                            _networkSpeedThresholdBytesPerSecond,
                          ),
                          style: LbTextStyles.body.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LbSpacing.sliderSectionGap),
                    Row(
                      children: <Widget>[
                        LbIcon(
                          symbol: LbIconSymbol.dashboardFilled,
                          size: 28,
                          color: palette.textPrimary,
                        ),
                        const SizedBox(width: LbSpacing.md),
                        Expanded(
                          child: LbSlider(
                            value: _networkSpeedSliderValue,
                            min: 0,
                            max: sliderMax,
                            onChanged: (double value) {
                              setState(() {
                                _networkSpeedSliderValue = value;
                                _networkSpeedThresholdBytesPerSecond =
                                    _snapThresholdBytesPerSecond(value);
                              });
                            },
                            onChangeEnd: (double value) {
                              final int nextValue =
                                  _snapThresholdBytesPerSecond(value);
                              setState(() {
                                _networkSpeedSliderValue =
                                    _sliderPositionForBytesPerSecond(nextValue);
                                _networkSpeedThresholdBytesPerSecond =
                                    nextValue;
                              });
                              unawaited(
                                _setNetworkSpeedThresholdBytesPerSecond(
                                  nextValue,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
