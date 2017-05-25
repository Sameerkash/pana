import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logging.dart';
import 'utils.dart';

class DartSdk {
  Map<String, String> _environment = {};
  String _dartCmd;
  String _dartAnalyzerCmd;
  String _dartfmtCmd;
  String _pubCmd;
  String _version;

  DartSdk({String sdkDir, Map<String, String> environment}) {
    String path = '';
    if (sdkDir != null) {
      path = sdkDir;
      if (!sdkDir.endsWith(Platform.pathSeparator)) {
        path += Platform.pathSeparator;
      }
    }
    if (environment != null) {
      _environment.addAll(environment);
    }
    _dartCmd = '${path}dart';
    _dartAnalyzerCmd = '${path}dartanalyzer';
    _dartfmtCmd = '${path}dartfmt';
    _pubCmd = '${path}pub';
  }

  Future<String> get version async {
    if (_version == null) {
      var r = handleProcessErrors(await Process.run(_dartCmd, ['--version'],
          environment: _environment));
      _version = r.stderr.toString().trim();
    }
    return _version;
  }

  Future<ProcessResult> runAnalyzer(String packageDir) {
    return Process.run(
      _dartAnalyzerCmd,
      ['--strong', '--format', 'machine', '.'],
      environment: _environment,
      workingDirectory: packageDir,
    );
  }

  Future<List<String>> filesNeedingFormat(String packageDir) async {
    var result = await Process.run(
      _dartfmtCmd,
      ['--dry-run', '--set-exit-if-changed', packageDir],
      environment: _environment,
    );
    if (result.exitCode == 0) {
      return const [];
    }

    var lines = LineSplitter.split(result.stdout).toList()..sort();
    assert(lines.isNotEmpty);
    return lines;
  }
}

class PubEnvironment {
  DartSdk _dartSdk;
  String _pubCacheDir;
  Map<String, String> _environment = {};

  PubEnvironment({DartSdk dartSdk, String pubCacheDir}) {
    _dartSdk = dartSdk ?? new DartSdk();
    _environment.addAll(_defaultPubEnv);
    _environment.addAll(_dartSdk._environment);
    _pubCacheDir = pubCacheDir;
    if (pubCacheDir != null) {
      var resolvedDir = new Directory(pubCacheDir).resolveSymbolicLinksSync();
      if (resolvedDir != pubCacheDir) {
        throw new ArgumentError([
          "Make sure you resolve symlinks:",
          pubCacheDir,
          resolvedDir
        ].join('\n'));
      }
      _environment['PUB_CACHE'] = pubCacheDir;
    }
  }

  DartSdk get sdk => _dartSdk;
  String get pubCacheDir => _pubCacheDir;

  Future<ProcessResult> runUpgrade(String packageDir,
      {int retryCount: 3}) async {
    ProcessResult result;
    do {
      retryCount--;
      log.info('Running `pub upgrade`...');
      result = await Process.run(
        _dartSdk._pubCmd,
        ['upgrade', '--verbosity', 'all'],
        workingDirectory: packageDir,
        environment: _environment,
      );
    } while (result.exitCode != 0 && retryCount > 0);
    return result;
  }

  Future<PackageLocation> getLocation(String package, {String version}) async {
    var args = ['cache', 'add', '--verbose'];
    if (version != null) {
      args.addAll(['--version', version]);
    }
    args.add(package);

    var result = handleProcessErrors(await Process.run(
      _dartSdk._pubCmd,
      args,
      environment: _environment,
    ));

    var match = _versionDownloadRexexp.allMatches(result.stdout.trim()).single;
    var pkgMatch = match[1];
    assert(pkgMatch == package);

    var versionString = match[2];
    assert(versionString.endsWith('.'));
    while (versionString.endsWith('.')) {
      versionString = versionString.substring(0, versionString.length - 1);
    }

    if (version != null) {
      assert(versionString == version);
    }

    // now get all installed packages
    result = handleProcessErrors(await Process.run(
      _dartSdk._pubCmd,
      ['cache', 'list'],
      environment: _environment,
    ));

    var json = JSON.decode(result.stdout) as Map;

    var location =
        json['packages'][package][versionString]['location'] as String;

    if (location == null) {
      throw "Huh? This should be cached!";
    }

    return new PackageLocation(package, versionString, location);
  }
}

class PackageLocation {
  final String package;
  final String version;
  final String location;

  PackageLocation(this.package, this.version, this.location);
}

final _versionDownloadRexexp =
    new RegExp(r"^MSG : (?:Downloading |Already cached )([\w-]+) (.+)$");

const _defaultPubEnv = const <String, String>{
  'PUB_ENVIRONMENT': 'kevmoo.pkg_clean',
};
