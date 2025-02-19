// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pana/src/create_report.dart';
import 'package:pana/src/package_context.dart';
import 'package:path/path.dart' as path;

import 'download_utils.dart';
import 'license.dart';
import 'logging.dart';
import 'maintenance.dart';
import 'messages.dart';
import 'model.dart';
import 'pubspec.dart';
import 'sdk_env.dart';
import 'tag_detection.dart';
import 'utils.dart';

class InspectOptions {
  final String pubHostedUrl;
  final String dartdocOutputDir;
  final int dartdocRetry;
  final Duration dartdocTimeout;
  final bool isInternal;
  final int lineLength;

  /// The analysis options (in yaml format) to use for the analysis.
  final String analysisOptionsYaml;

  InspectOptions({
    this.pubHostedUrl,
    this.dartdocOutputDir,
    this.dartdocRetry = 0,
    this.dartdocTimeout,
    this.isInternal = false,
    this.lineLength,
    this.analysisOptionsYaml,
  });
}

class PackageAnalyzer {
  final ToolEnvironment _toolEnv;
  final UrlChecker _urlChecker;

  PackageAnalyzer(this._toolEnv, {UrlChecker urlChecker})
      : _urlChecker = urlChecker ?? UrlChecker();

  static Future<PackageAnalyzer> create({
    String sdkDir,
    String flutterDir,
    String pubCacheDir,
    String pubHostedUrl,
  }) async {
    return PackageAnalyzer(await ToolEnvironment.create(
        dartSdkDir: sdkDir,
        flutterSdkDir: flutterDir,
        pubCacheDir: pubCacheDir,
        environment: <String, String>{
          if (pubHostedUrl != null) 'PUB_HOSTED_URL': pubHostedUrl,
        }));
  }

  Future<Summary> inspectPackage(
    String package, {
    String version,
    InspectOptions options,
    Logger logger,
  }) async {
    options ??= InspectOptions();
    return withLogger(() async {
      return withTempDir((tempDir) async {
        await downloadPackage(package, version,
            destination: tempDir, pubHostedUrl: options.pubHostedUrl);
        return await _inspect(tempDir, options);
      });
    }, logger: logger);
  }

  Future<Summary> inspectDir(String packageDir, {InspectOptions options}) {
    options ??= InspectOptions();
    return _inspect(packageDir, options);
  }

  Future<Summary> _inspect(String pkgDir, InspectOptions options) async {
    final context = PackageContext(
      toolEnvironment: _toolEnv,
      packageDir: pkgDir,
      options: options,
      urlChecker: _urlChecker,
    );

    var dartFiles = await listFiles(
      pkgDir,
      endsWith: '.dart',
      deleteBadExtracted: true,
    )
        .where(
            (file) => path.isWithin('bin', file) || path.isWithin('lib', file))
        .toList();

    Pubspec pubspec;
    try {
      pubspec = context.pubspec;
    } catch (e, st) {
      log.info('Unable to read pubspec.yaml', e, st);
      return Summary(
        runtimeInfo: _toolEnv.runtimeInfo,
        packageName: null,
        packageVersion: null,
        pubspec: pubspec,
        allDependencies: null,
        licenseFile: null,
        tags: null,
        report: null,
        errorMessage: pubspecParseError(e),
      );
    }
    if (pubspec.hasUnknownSdks) {
      context.errors.add('The following unknown SDKs are in `pubspec.yaml`:\n'
          '  `${pubspec.unknownSdks}`.\n\n'
          '`pana` doesn’t recognize them; please remove the `sdk` entry or '
          '[report the issue](https://github.com/dart-lang/pana/issues).');
    }

    final pkgResolution = await context.resolveDependencies();

    if (pkgResolution != null && options.dartdocOutputDir != null) {
      for (var i = 0; i <= options.dartdocRetry; i++) {
        try {
          final r = await _toolEnv.dartdoc(
            pkgDir,
            options.dartdocOutputDir,
            validateLinks: i == 0,
            timeout: options.dartdocTimeout,
          );
          if (!r.wasTimeout) {
            break;
          }
        } catch (e, st) {
          log.severe('Could not run dartdoc.', e, st);
        }
      }
    }

    final tags = <String>[];
    if (pkgResolution != null) {
      List<CodeProblem> analyzerItems;
      if (dartFiles.isNotEmpty) {
        try {
          analyzerItems = await context.staticAnalysis();
        } on ToolException catch (e) {
          context.errors
              .add(runningDartanalyzerFailed(context.usesFlutter, e.message));
        }
      }
      if (analyzerItems != null && !analyzerItems.any((item) => item.isError)) {
        final tagger = Tagger(pkgDir);
        final explanations = <Explanation>[];
        tagger.sdkTags(tags, explanations);
        tagger.flutterPlatformTags(tags, explanations);
        tagger.runtimeTags(tags, explanations);
        tagger.nullSafetyTags(tags, explanations);
      }
    }

    final licenseFile = await detectLicenseInDir(pkgDir);
    final licenseUrl = await getLicenseUrl(
        _urlChecker, pubspec.repository ?? pubspec.homepage, licenseFile);

    final errorMessage = context.errors.isEmpty
        ? null
        : context.errors.map((e) => e.trim()).join('\n\n');
    return Summary(
      runtimeInfo: _toolEnv.runtimeInfo,
      packageName: pubspec.name,
      packageVersion: pubspec.version,
      pubspec: pubspec,
      allDependencies:
          pkgResolution?.dependencies?.map((d) => d.package)?.toList(),
      licenseFile: licenseFile?.change(url: licenseUrl),
      tags: tags,
      report: await createReport(context),
      errorMessage: errorMessage,
    );
  }
}
