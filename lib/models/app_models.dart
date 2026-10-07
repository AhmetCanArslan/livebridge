import 'dart:typed_data';

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
    this.isSystem = false,
  });

  final String packageName;
  final String label;
  final Uint8List? icon;
  final bool isSystem;
}

class DeviceInfo {
  const DeviceInfo({
    required this.manufacturer,
    required this.brand,
    required this.marketName,
    required this.model,
    this.rawModel = '',
    this.product = '',
    this.device = '',
    this.board = '',
    this.hardware = '',
    this.bootloader = '',
    this.host = '',
    this.id = '',
    this.tags = '',
    this.type = '',
    this.user = '',
    this.fingerprint = '',
    this.display = '',
  });

  final String manufacturer;
  final String brand;
  final String marketName;
  final String model;
  final String rawModel;
  final String product;
  final String device;
  final String board;
  final String hardware;
  final String bootloader;
  final String host;
  final String id;
  final String tags;
  final String type;
  final String user;
  final String fingerprint;
  final String display;

  bool get isPixel {
    final String all = '$manufacturer $brand $marketName $model'.toLowerCase();
    return all.contains('google') || all.contains('pixel');
  }

  bool get isSamsung {
    final String all = '$manufacturer $brand'.toLowerCase();
    return all.contains('samsung');
  }

  bool get isAospDevice {
    final String all =
        '$manufacturer $brand $marketName $model $rawModel $product $device '
                '$board $hardware $bootloader $host $id $tags $type $user '
                '$fingerprint $display'
            .toLowerCase();
    final bool hasCustomBuildKeys =
        tags.toLowerCase().contains('test-keys') ||
        tags.toLowerCase().contains('dev-keys');
    const List<String> customRomMarkers = <String>[
      'lineage',
      'evolution',
      'evox',
      'crdroid',
      'pixelos',
      'graphene',
      'calyx',
      'arrowos',
      'risingos',
      'yaap',
      'derpfest',
      'paranoid',
      'aospa',
      'omnirom',
      'omni',
      'resurrection',
      'superior',
      'cherish',
      'sparkos',
      'elixir',
      'hentaios',
      'aicp',
      'iodé',
      'iode',
      'aosp',
    ];
    return isPixel ||
        hasCustomBuildKeys ||
        all.contains('nothing') ||
        all.contains('motorola') ||
        customRomMarkers.any(all.contains);
  }

  bool get isVivo {
    final List<String> vendorNames = <String>[
      manufacturer.trim().toLowerCase(),
      brand.trim().toLowerCase(),
    ];
    return vendorNames.any((String name) => name == 'vivo' || name == 'iqoo');
  }

  // vivo firmware can promote notifications without exposing the standard
  // permission toggle. Keep the raw API result for diagnostics, but do not
  // treat this unavailable settings control as a missing prerequisite.
  bool get shouldHideLiveUpdatesPromotion =>
      isSamsung || isAospDevice || isVivo;

  String get label {
    if (marketName.isNotEmpty) return marketName;
    if (model.isNotEmpty) return model;
    if (brand.isNotEmpty) return brand;
    if (manufacturer.isNotEmpty) return manufacturer;
    return 'device';
  }
}

enum PackageMode { all, include, exclude }

extension PackageModeId on PackageMode {
  String get id {
    switch (this) {
      case PackageMode.all:
        return 'all';
      case PackageMode.include:
        return 'include';
      case PackageMode.exclude:
        return 'exclude';
    }
  }

  static PackageMode from(String value) {
    switch (value) {
      case 'include':
        return PackageMode.include;
      case 'exclude':
        return PackageMode.exclude;
      default:
        return PackageMode.all;
    }
  }
}

enum NotificationDedupMode { otpStatus, otpOnly }

extension NotificationDedupModeId on NotificationDedupMode {
  String get id {
    switch (this) {
      case NotificationDedupMode.otpStatus:
        return 'otp_status';
      case NotificationDedupMode.otpOnly:
        return 'otp_only';
    }
  }

  static NotificationDedupMode from(String? value) {
    switch (value) {
      case 'otp_only':
        return NotificationDedupMode.otpOnly;
      default:
        return NotificationDedupMode.otpStatus;
    }
  }
}

enum AppCompactTextSource { title, text }

extension AppCompactTextSourceId on AppCompactTextSource {
  String get id {
    switch (this) {
      case AppCompactTextSource.title:
        return 'title';
      case AppCompactTextSource.text:
        return 'text';
    }
  }

  static AppCompactTextSource from(String? value) {
    switch (value) {
      case 'text':
        return AppCompactTextSource.text;
      default:
        return AppCompactTextSource.title;
    }
  }
}

enum AppNotificationIconSource { notification, app }

extension AppNotificationIconSourceId on AppNotificationIconSource {
  String get id {
    switch (this) {
      case AppNotificationIconSource.notification:
        return 'notification';
      case AppNotificationIconSource.app:
        return 'app';
    }
  }

  static AppNotificationIconSource from(String? value) {
    switch (value) {
      case 'app':
        return AppNotificationIconSource.app;
      default:
        return AppNotificationIconSource.notification;
    }
  }
}

enum AppPresentationTitleSource { notificationTitle, appTitle }

extension AppPresentationTitleSourceId on AppPresentationTitleSource {
  String get id {
    switch (this) {
      case AppPresentationTitleSource.notificationTitle:
        return 'notification_title';
      case AppPresentationTitleSource.appTitle:
        return 'app_title';
    }
  }

  static AppPresentationTitleSource? tryParse(String? value) {
    switch (value) {
      case 'notification_title':
        return AppPresentationTitleSource.notificationTitle;
      case 'app_title':
        return AppPresentationTitleSource.appTitle;
      default:
        return null;
    }
  }
}

enum AppPresentationContentSource { notificationText, notificationTitle }

extension AppPresentationContentSourceId on AppPresentationContentSource {
  String get id {
    switch (this) {
      case AppPresentationContentSource.notificationText:
        return 'notification_text';
      case AppPresentationContentSource.notificationTitle:
        return 'notification_title';
    }
  }

  static AppPresentationContentSource? tryParse(String? value) {
    switch (value) {
      case 'notification_text':
        return AppPresentationContentSource.notificationText;
      case 'notification_title':
        return AppPresentationContentSource.notificationTitle;
      default:
        return null;
    }
  }
}

class AppPresentationOverride {
  const AppPresentationOverride({
    this.compactTextSource = AppCompactTextSource.title,
    this.iconSource = AppNotificationIconSource.notification,
    this.titleSource,
    this.contentSource,
    this.removeOriginalMessage = false,
  });

  final AppCompactTextSource compactTextSource;
  final AppNotificationIconSource iconSource;
  final AppPresentationTitleSource? titleSource;
  final AppPresentationContentSource? contentSource;
  final bool removeOriginalMessage;

  bool get usesExplicitSources =>
      titleSource != null || contentSource != null;

  AppPresentationTitleSource get effectiveTitleSource =>
      titleSource ?? AppPresentationTitleSource.notificationTitle;

  AppPresentationContentSource get effectiveContentSource =>
      contentSource ?? AppPresentationContentSource.notificationText;

  bool get isDefault =>
      compactTextSource == AppCompactTextSource.title &&
      iconSource == AppNotificationIconSource.notification &&
      !removeOriginalMessage;
  bool get isEffectiveDefault =>
      iconSource == AppNotificationIconSource.notification &&
      compactTextSource == AppCompactTextSource.title &&
      effectiveTitleSource == AppPresentationTitleSource.notificationTitle &&
      effectiveContentSource == AppPresentationContentSource.notificationText &&
      !removeOriginalMessage;

  AppPresentationOverride copyWith({
    AppCompactTextSource? compactTextSource,
    AppNotificationIconSource? iconSource,
    AppPresentationTitleSource? titleSource,
    AppPresentationContentSource? contentSource,
    bool? removeOriginalMessage,
  }) {
    return AppPresentationOverride(
      compactTextSource: compactTextSource ?? this.compactTextSource,
      iconSource: iconSource ?? this.iconSource,
      titleSource: titleSource ?? this.titleSource,
      contentSource: contentSource ?? this.contentSource,
      removeOriginalMessage:
          removeOriginalMessage ?? this.removeOriginalMessage,
    );
  }

  Map<String, String> toJsonEntry() {
    final Map<String, String> payload = <String, String>{
      'icon_source': iconSource.id,
    };
    if (removeOriginalMessage) {
      payload['remove_original_message'] = 'true';
    }
    if (usesExplicitSources) {
      payload['title_source'] = effectiveTitleSource.id;
      payload['content_source'] = effectiveContentSource.id;
    } else {
      payload['compact_text'] = compactTextSource.id;
    }
    return payload;
  }

  static AppPresentationOverride fromJsonEntry(Map<String, dynamic> json) {
    final AppPresentationTitleSource? titleSource =
        AppPresentationTitleSourceId.tryParse(
          json['title_source'] as String?,
        );
    final AppPresentationContentSource? contentSource =
        AppPresentationContentSourceId.tryParse(
          json['content_source'] as String?,
        );

    return AppPresentationOverride(
      compactTextSource: (titleSource != null || contentSource != null)
          ? AppCompactTextSource.title
          : AppCompactTextSourceId.from(json['compact_text'] as String?),
      iconSource: AppNotificationIconSourceId.from(
        json['icon_source'] as String?,
      ),
      titleSource: titleSource,
      contentSource: contentSource,
      removeOriginalMessage: json['remove_original_message'] == true ||
          json['remove_original_message'] == 'true',
    );
  }
}
