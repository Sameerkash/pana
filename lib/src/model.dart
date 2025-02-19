// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:quiver/core.dart' show hashObjects;

import 'json_converters.dart';
import 'pubspec.dart';

part 'model.g.dart';

@JsonSerializable()
@VersionConverter()
class Summary {
  @JsonKey()
  final PanaRuntimeInfo runtimeInfo;

  final String packageName;

  @JsonKey(includeIfNull: false)
  final Version packageVersion;

  @JsonKey(includeIfNull: false)
  final Pubspec pubspec;

  final LicenseFile licenseFile;

  /// The packages that are either direct-, dev- or transient dependencies.
  @JsonKey(includeIfNull: false)
  final List<String> allDependencies;

  @JsonKey(includeIfNull: false)
  final List<String> tags;

  @JsonKey(includeIfNull: false)
  final Report report;

  /// Markdown-formatted text with errors encountered by `pana`.
  @JsonKey(includeIfNull: false)
  final String errorMessage;

  Summary({
    @required this.runtimeInfo,
    @required this.packageName,
    @required this.packageVersion,
    @required this.pubspec,
    @required this.allDependencies,
    @required this.licenseFile,
    @required this.tags,
    @required this.report,
    @required this.errorMessage,
  });

  factory Summary.fromJson(Map<String, dynamic> json) =>
      _$SummaryFromJson(json);

  Map<String, dynamic> toJson() => _$SummaryToJson(this);

  Summary change({
    PanaRuntimeInfo runtimeInfo,
    List<String> tags,
  }) {
    return Summary(
      runtimeInfo: runtimeInfo ?? this.runtimeInfo,
      packageName: packageName,
      packageVersion: packageVersion,
      pubspec: pubspec,
      allDependencies: allDependencies,
      licenseFile: licenseFile,
      tags: tags ?? this.tags,
      report: report,
      errorMessage: errorMessage,
    );
  }
}

@JsonSerializable()
class PanaRuntimeInfo {
  final String panaVersion;
  final String sdkVersion;
  @JsonKey(includeIfNull: false)
  final Map<String, dynamic> flutterVersions;

  PanaRuntimeInfo({
    this.panaVersion,
    this.sdkVersion,
    this.flutterVersions,
  });

  factory PanaRuntimeInfo.fromJson(Map<String, dynamic> json) =>
      _$PanaRuntimeInfoFromJson(json);

  Map<String, dynamic> toJson() => _$PanaRuntimeInfoToJson(this);

  bool get hasFlutter => flutterVersions != null;

  /// The Flutter SDK version.
  String get flutterVersion => flutterVersions == null
      ? null
      : flutterVersions['frameworkVersion'] as String;

  /// The Dart SDK used by Flutter internally.
  String get flutterInternalDartSdkVersion {
    if (flutterVersions == null) return null;
    final value = flutterVersions['dartSdkVersion'] as String;
    if (value == null) return null;
    final parts = value.split(' ');
    if (parts.length > 2 && parts[1] == '(build' && parts[2].endsWith(')')) {
      final buildValue = parts[2].split(')').first;
      try {
        Version.parse(buildValue);
        return buildValue;
      } catch (_) {
        // ignore
      }
    }
    return parts.first;
  }
}

@JsonSerializable()
class LicenseFile {
  final String path;
  final String name;

  @JsonKey(includeIfNull: false)
  final String version;

  @JsonKey(includeIfNull: false)
  final String url;

  LicenseFile(this.path, this.name, {this.version, this.url});

  factory LicenseFile.fromJson(Map<String, dynamic> json) =>
      _$LicenseFileFromJson(json);

  Map<String, dynamic> toJson() => _$LicenseFileToJson(this);

  LicenseFile change({String url}) =>
      LicenseFile(path, name, version: version, url: url ?? this.url);

  String get shortFormatted => version == null ? name : '$name $version';

  @override
  String toString() => '$path: $shortFormatted';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseFile &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          name == other.name &&
          version == other.version &&
          url == other.url;

  @override
  int get hashCode =>
      path.hashCode ^ name.hashCode ^ version.hashCode ^ url.hashCode;
}

abstract class LicenseNames {
  static const String AGPL = 'AGPL';
  static const String Apache = 'Apache';
  static const String BSD = 'BSD';
  static const String GPL = 'GPL';
  static const String LGPL = 'LGPL';
  static const String MIT = 'MIT';
  static const String MPL = 'MPL';
  static const String Unlicense = 'Unlicense';
  static const String unknown = 'unknown';
}

@JsonSerializable()
class CodeProblem implements Comparable<CodeProblem> {
  /// The errors which don't block platform classification.
  static const _platformNonBlockerTypes = <String>[
    'STATIC_TYPE_WARNING',
    'STATIC_WARNING',
  ];

  static const _platformNonBlockerCodes = <String>[
    'ARGUMENT_TYPE_NOT_ASSIGNABLE',
    'STRONG_MODE_COULD_NOT_INFER',
    'STRONG_MODE_INVALID_CAST_FUNCTION_EXPR',
    'STRONG_MODE_INVALID_CAST_NEW_EXPR',
    'STRONG_MODE_INVALID_METHOD_OVERRIDE',
  ];

  final String severity;
  final String errorType;
  final String errorCode;

  final String file;
  final int line;
  final int col;
  final int length;
  final String description;

  CodeProblem({
    @required this.severity,
    @required this.errorType,
    @required this.errorCode,
    @required this.description,
    @required this.file,
    @required this.line,
    @required this.col,
    @required this.length,
  });

  factory CodeProblem.fromJson(Map<String, dynamic> json) =>
      _$CodeProblemFromJson(json);

  Map<String, dynamic> toJson() => _$CodeProblemToJson(this);

  bool get isError => severity?.toUpperCase() == 'ERROR';

  bool get isWarning => severity?.toUpperCase() == 'WARNING';

  bool get isInfo => severity?.toUpperCase() == 'INFO';

  /// `true` iff [isError] is `true` and [errorType] is not safe to ignore for
  /// platform classification.
  bool get isPlatformBlockingError =>
      isError &&
      !_platformNonBlockerTypes.contains(errorType) &&
      !_platformNonBlockerCodes.contains(errorCode);

  @override
  int compareTo(CodeProblem other) {
    var myVals = _values;
    var otherVals = other._values;
    for (var i = 0; i < myVals.length; i++) {
      var compare = (_values[i] as Comparable).compareTo(otherVals[i]);

      if (compare != 0) {
        return compare;
      }
    }

    assert(this == other);

    return 0;
  }

  int severityCompareTo(CodeProblem other) {
    if (isError && !other.isError) return -1;
    if (!isError && other.isError) return 1;
    if (isWarning && !other.isWarning) return -1;
    if (!isWarning && other.isWarning) return 1;
    if (isInfo && !other.isInfo) return -1;
    if (!isInfo && other.isInfo) return 1;
    return compareTo(other);
  }

  @override
  int get hashCode => hashObjects(_values);

  @override
  bool operator ==(Object other) {
    if (other is CodeProblem) {
      var myVals = _values;
      var otherVals = other._values;
      for (var i = 0; i < myVals.length; i++) {
        if (myVals[i] != otherVals[i]) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  List<Object> get _values =>
      [file, line, col, severity, errorType, errorCode, description];
}

/// Models the 'new-style' pana report.
@JsonSerializable(explicitToJson: true)
class Report {
  /// The scoring sections.
  final List<ReportSection> sections;

  Report({@required this.sections});

  static Report fromJson(Map<String, dynamic> json) => _$ReportFromJson(json);
  Map<String, dynamic> toJson() => _$ReportToJson(this);

  int get grantedPoints =>
      sections.fold<int>(0, (sum, section) => sum + section.grantedPoints);

  int get maxPoints =>
      sections.fold<int>(0, (sum, section) => sum + section.maxPoints);

  /// Creates a new [Report] instance with [section] extending and already
  /// existing [ReportSection]. The sections are matched via the `title`.
  ///
  /// The granted and max points will be added to the existing section.
  /// The status will be min of the two statuses.
  ///
  /// The summary will be appended to the end of the existing summary.
  ///
  ///
  /// If there is no section matched, the section will be added to the end of
  /// the sections list.
  Report joinSection(ReportSection section) {
    final matched = sections.firstWhere(
        (s) => (s.id != null && s.id == section.id) || s.title == section.title,
        orElse: () => null);
    if (matched == null) {
      return Report(sections: [...sections, section]);
    } else {
      return Report(
          sections: sections.map(
        (s) {
          if (s != matched) {
            return s;
          }
          return ReportSection(
              id: s.id,
              title: s.title,
              maxPoints: s.maxPoints + section.maxPoints,
              grantedPoints: s.grantedPoints + section.grantedPoints,
              summary: [s.summary.trim(), section.summary.trim()].join('\n\n'),
              status: minStatus(s.status, section.status));
        },
      ).toList());
    }
  }
}

abstract class ReportSectionId {
  static const analysis = 'analysis';
  static const convention = 'convention';
  static const dependency = 'dependency';
  static const documentation = 'documentation';
  static const platform = 'platform';
  static const nullSafety = 'null-safety';
}

enum ReportStatus {
  @JsonValue('failed')
  failed,
  @JsonValue('partial')
  partial,
  @JsonValue('passed')
  passed,
}

/// Returns the lowest of [statuses] to represent them.
ReportStatus summarizeStatuses(Iterable<ReportStatus> statuses) {
  return statuses.fold(ReportStatus.passed, minStatus);
}

/// Returns the lowest status of [a] and [b] ranked in the order of the enum.
///
/// Example: `minStatus(ReportStatus.failed, ReportStatus.partial) == ReportStatus.partial`.
///
/// Returns `null` when any of them is `null` (may be the case with old data).
ReportStatus minStatus(ReportStatus a, ReportStatus b) {
  if (a == null || b == null) return null;
  return ReportStatus.values[min(a.index, b.index)];
}

@JsonSerializable()
class ReportSection {
  final String id;
  final String title;

  /// How many points did this section score
  final int grantedPoints;

  /// How many points could this section have scored.
  final int maxPoints;

  /// Is this section considered passing.
  final ReportStatus status;

  /// Should describe the overall goals in a few lines, followed by
  /// descriptions of each issue that resulted in [grantedPoints] being less
  /// than  [maxPoints] (if any).
  ///
  /// Markdown formatted.
  final String summary;

  ReportSection({
    @required this.id,
    @required this.title,
    @required this.grantedPoints,
    @required this.maxPoints,
    @required this.summary,
    @required this.status,
  });

  static ReportSection fromJson(Map<String, dynamic> json) =>
      _$ReportSectionFromJson(json);
  Map<String, dynamic> toJson() => _$ReportSectionToJson(this);
}

/// The json output from `dart pub outdated --json`.
@JsonSerializable()
class Outdated {
  final List<OutdatedPackage> packages;
  Outdated(this.packages);

  static Outdated fromJson(Map<String, dynamic> json) =>
      _$OutdatedFromJson(json);

  Map<String, dynamic> toJson() => _$OutdatedToJson(this);
}

@JsonSerializable()
class OutdatedPackage {
  final String package;
  final VersionDescriptor upgradable;
  final VersionDescriptor latest;

  OutdatedPackage(this.package, this.upgradable, this.latest);

  static OutdatedPackage fromJson(Map<String, dynamic> json) =>
      _$OutdatedPackageFromJson(json);

  Map<String, dynamic> toJson() => _$OutdatedPackageToJson(this);
}

@JsonSerializable()
class VersionDescriptor {
  final String version;
  VersionDescriptor(this.version);

  static VersionDescriptor fromJson(Map<String, dynamic> json) =>
      _$VersionDescriptorFromJson(json);

  Map<String, dynamic> toJson() => _$VersionDescriptorToJson(this);
}
