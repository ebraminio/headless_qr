// Adapted from https://github.com/Rich-Harris/headless-qr
// which is adapted from https://github.com/kazuhikoarase/qrcode-generator
// License reproduced below

//---------------------------------------------------------------------
//
// QR Code Generator for JavaScript
//
// Copyright (c) 2009 Kazuhiko Arase
//
// URL: http://www.d-project.com/
//
// Licensed under the MIT license:
//  http://www.opensource.org/licenses/mit-license.php
//
// The word 'QR Code' is registered trademark of
// DENSO WAVE INCORPORATED
//  http://www.denso-wave.com/qrcode/faqpatent-e.html
//
//---------------------------------------------------------------------

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

enum ErrorCorrectionLevel { L, M, Q, H }

List<List<bool>> qr(
  String input, {
  int version = -1,
  ErrorCorrectionLevel errorCorrectionLevel = ErrorCorrectionLevel.M,
}) {
  final data = const Utf8Encoder().convert(input);

  if (version < 1) {
    for (version = 1; version < 40; version += 1) {
      final rsBlocks = _QRRSBlock.getRsBlocks(version, errorCorrectionLevel);
      final buffer = _QrBitBuffer();

      buffer.put(4, 4);
      buffer.put(data.length, _QRUtil.getLengthInBits(version));
      buffer.putBytes(data);

      var totalDataCount = 0;
      for (var i = 0; i < rsBlocks.length; i += 1) {
        totalDataCount += rsBlocks[i].dataCount;
      }

      if (buffer.getLengthInBits() <= totalDataCount * 8) break;
    }
  }

  final size = version * 4 + 17;
  final modules =
      List<List<bool?>>.generate(size, (_) => List.generate(size, (_) => null));

  var minLostPoint = .0;
  var bestPattern = _MaskPattern.pattern000;

  final cache = _createData(version, errorCorrectionLevel, data);

  List<List<bool?>> make(bool test, _MaskPattern maskPattern) {
    for (var row = 0; row < size; row += 1) {
      for (var col = 0; col < size; col += 1) {
        modules[row][col] = null;
      }
    }

    _setupPositionProbePattern(modules, 0, 0);
    _setupPositionProbePattern(modules, size - 7, 0);
    _setupPositionProbePattern(modules, 0, size - 7);
    _setupPositionAdjustPattern(modules, version);
    _setupTimingPattern(modules);
    _setupTypeInfo(modules, test, maskPattern, errorCorrectionLevel);

    if (version >= 7) _setupVersionNumber(modules, version, test);

    _mapData(modules, cache, maskPattern);

    return modules;
  }

  for (var i = 0; i < 8; i += 1) {
    final modules = make(true, _MaskPattern.values[i]);

    final lostPoint = _getLostPoint(modules);

    if (i == 0 || minLostPoint > lostPoint) {
      minLostPoint = lostPoint;
      bestPattern = _MaskPattern.values[i];
    }
  }

  return make(false, bestPattern)
      .map((e) => e.map((e) => e!).toList())
      .toList();
}

const _pad0 = 0xec;
const _pad1 = 0x11;

enum _MaskPattern {
  pattern000,
  pattern001,
  pattern010,
  pattern011,
  pattern100,
  pattern101,
  pattern110,
  pattern111;

  bool Function(int i, int j) getMaskFunction() {
    switch (this) {
      case pattern000:
        return (int i, int j) => (i + j) % 2 == 0;
      case pattern001:
        return (int i, int j) => i % 2 == 0;
      case pattern010:
        return (int i, int j) => j % 3 == 0;
      case pattern011:
        return (int i, int j) => (i + j) % 3 == 0;
      case pattern100:
        return (int i, int j) => ((i / 2).floor() + (j / 3).floor()) % 2 == 0;
      case pattern101:
        return (int i, int j) => ((i * j) % 2) + ((i * j) % 3) == 0;
      case pattern110:
        return (int i, int j) => (((i * j) % 2) + ((i * j) % 3)) % 2 == 0;
      case pattern111:
        return (int i, int j) => (((i * j) % 3) + ((i + j) % 2)) % 2 == 0;
    }
  }
}

void _setupPositionProbePattern(
  List<List<bool?>> modules,
  int row,
  int col,
) {
  for (var r = -1; r <= 7; r += 1) {
    if (row + r <= -1 || modules.length <= row + r) continue;

    for (var c = -1; c <= 7; c += 1) {
      if (col + c <= -1 || modules.length <= col + c) continue;

      modules[row + r][col + c] = (0 <= r && r <= 6 && (c == 0 || c == 6)) ||
          (0 <= c && c <= 6 && (r == 0 || r == 6)) ||
          (2 <= r && r <= 4 && 2 <= c && c <= 4);
    }
  }
}

void _setupPositionAdjustPattern(List<List<bool?>> modules, int version) {
  final pos = _QRUtil.getPatternPosition(version);

  for (var i = 0; i < pos.length; i += 1) {
    for (var j = 0; j < pos.length; j += 1) {
      final row = pos[i];
      final col = pos[j];

      if (modules[row][col] != null) continue;

      for (var r = -2; r <= 2; r += 1) {
        for (var c = -2; c <= 2; c += 1) {
          modules[row + r][col + c] =
              r == -2 || r == 2 || c == -2 || c == 2 || (r == 0 && c == 0);
        }
      }
    }
  }
}

void _setupTimingPattern(List<List<bool?>> modules) {
  for (var r = 8; r < modules.length - 8; r += 1) {
    if (modules[r][6] != null) continue;
    modules[r][6] = r % 2 == 0;
  }

  for (var c = 8; c < modules.length - 8; c += 1) {
    if (modules[6][c] != null) continue;
    modules[6][c] = c % 2 == 0;
  }
}

int _correctionValue(ErrorCorrectionLevel level) {
  switch (level) {
    case ErrorCorrectionLevel.L:
      return 1;
    case ErrorCorrectionLevel.M:
      return 0;
    case ErrorCorrectionLevel.Q:
      return 3;
    case ErrorCorrectionLevel.H:
      return 2;
  }
}

void _setupTypeInfo(
  List<List<bool?>> modules,
  bool test,
  _MaskPattern maskPattern,
  ErrorCorrectionLevel errorCorrectionLevel,
) {
  final data =
      (_correctionValue(errorCorrectionLevel) << 3) | maskPattern.index;
  final bits = _QRUtil.getBchTypeInfo(data);

  // vertical
  for (var i = 0; i < 15; i += 1) {
    final mod = !test && ((bits >> i) & 1) == 1;

    if (i < 6) {
      modules[i][8] = mod;
    } else if (i < 8) {
      modules[i + 1][8] = mod;
    } else {
      modules[modules.length - 15 + i][8] = mod;
    }
  }

  // horizontal
  for (var i = 0; i < 15; i += 1) {
    final mod = !test && ((bits >> i) & 1) == 1;

    if (i < 8) {
      modules[8][modules.length - i - 1] = mod;
    } else if (i < 9) {
      modules[8][15 - i - 1 + 1] = mod;
    } else {
      modules[8][15 - i - 1] = mod;
    }
  }

  // fixed module
  modules[modules.length - 8][8] = !test;
}

void _setupVersionNumber(List<List<bool?>> modules, int version, bool test) {
  final bits = _QRUtil.getBchTypeNumber(version);

  for (var i = 0; i < 18; i += 1) {
    final mod = !test && ((bits >> i) & 1) == 1;
    modules[(i / 3).floor()][(i % 3) + modules.length - 8 - 3] = mod;
  }

  for (var i = 0; i < 18; i += 1) {
    final mod = !test && ((bits >> i) & 1) == 1;
    modules[(i % 3) + modules.length - 8 - 3][(i / 3).floor()] = mod;
  }
}

void _mapData(
  List<List<bool?>> modules,
  List<int> data,
  _MaskPattern maskPattern,
) {
  var inc = -1;
  var row = modules.length - 1;
  var bitIndex = 7;
  var byteIndex = 0;
  final maskFunc = maskPattern.getMaskFunction();

  for (var col = modules.length - 1; col > 0; col -= 2) {
    if (col == 6) col -= 1;

    while (true) {
      for (var c = 0; c < 2; c += 1) {
        if (modules[row][col - c] == null) {
          var dark = false;

          if (byteIndex < data.length) {
            dark = ((data[byteIndex] >>> bitIndex) & 1) == 1;
          }

          final mask = maskFunc(row, col - c);

          if (mask) {
            dark = !dark;
          }

          modules[row][col - c] = dark;
          bitIndex -= 1;

          if (bitIndex == -1) {
            byteIndex += 1;
            bitIndex = 7;
          }
        }
      }

      row += inc;

      if (row < 0 || modules.length <= row) {
        row -= inc;
        inc = -inc;
        break;
      }
    }
  }
}

double _getLostPoint(List<List<bool?>> modules) {
  final size = modules.length;
  var lostPoint = .0;

  isDark(int row, int col) => modules[row][col]!;

  // LEVEL1
  for (var row = 0; row < size; row += 1) {
    for (var col = 0; col < size; col += 1) {
      final dark = isDark(row, col);
      var sameCount = 0;

      for (var r = -1; r <= 1; r += 1) {
        if (row + r < 0 || size <= row + r) continue;

        for (var c = -1; c <= 1; c += 1) {
          if (col + c < 0 || size <= col + c) continue;
          if (r == 0 && c == 0) continue;

          if (dark == isDark(row + r, col + c)) {
            sameCount += 1;
          }
        }
      }

      if (sameCount > 5) lostPoint += 3 + sameCount - 5;
    }
  }

  // LEVEL2
  for (var row = 0; row < size - 1; row += 1) {
    for (var col = 0; col < size - 1; col += 1) {
      var count = 0;
      if (isDark(row, col)) count += 1;
      if (isDark(row + 1, col)) count += 1;
      if (isDark(row, col + 1)) count += 1;
      if (isDark(row + 1, col + 1)) count += 1;
      if (count == 0 || count == 4) {
        lostPoint += 3;
      }
    }
  }

  // LEVEL3
  for (var row = 0; row < size; row += 1) {
    for (var col = 0; col < size - 6; col += 1) {
      if (isDark(row, col) &&
          !isDark(row, col + 1) &&
          isDark(row, col + 2) &&
          isDark(row, col + 3) &&
          isDark(row, col + 4) &&
          !isDark(row, col + 5) &&
          isDark(row, col + 6)) {
        lostPoint += 40;
      }
    }
  }

  for (var col = 0; col < size; col += 1) {
    for (var row = 0; row < size - 6; row += 1) {
      if (isDark(row, col) &&
          !isDark(row + 1, col) &&
          isDark(row + 2, col) &&
          isDark(row + 3, col) &&
          isDark(row + 4, col) &&
          !isDark(row + 5, col) &&
          isDark(row + 6, col)) {
        lostPoint += 40;
      }
    }
  }

  // LEVEL4
  var darkCount = 0;

  for (var col = 0; col < size; col += 1) {
    for (var row = 0; row < size; row += 1) {
      if (isDark(row, col)) darkCount += 1;
    }
  }

  final ratio = ((100 * darkCount) / size / size - 50).abs() / 5;
  lostPoint += ratio * 10;

  return lostPoint;
}

typedef _Rs = ({int dataCount, int totalCount});

List<int> _createBytes(_QrBitBuffer buffer, List<_Rs> rsBlocks) {
  var offset = 0;

  var maxDcCount = 0;
  var maxEcCount = 0;

  final dcData = List<List<int>>.generate(rsBlocks.length, (_) => []);
  final ecData = List<List<int>>.generate(rsBlocks.length, (_) => []);

  for (var r = 0; r < rsBlocks.length; r += 1) {
    final dcCount = rsBlocks[r].dataCount;
    final ecCount = rsBlocks[r].totalCount - dcCount;

    maxDcCount = max(maxDcCount, dcCount);
    maxEcCount = max(maxEcCount, ecCount);

    dcData[r] = List.generate(dcCount, (_) => 0);

    for (var i = 0; i < dcData[r].length; i += 1) {
      dcData[r][i] = 0xff & buffer.getBuffer()[i + offset];
    }
    offset += dcCount;

    final rsPoly = _QRUtil.getErrorCorrectPolynomial(ecCount);
    final rawPoly = _QrPolynomial(dcData[r], rsPoly.getLength() - 1);

    final modPoly = rawPoly.mod(rsPoly);
    ecData[r] = List.generate(rsPoly.getLength() - 1, (_) => 0);
    for (var i = 0; i < ecData[r].length; i += 1) {
      final modIndex = i + modPoly.getLength() - ecData[r].length;
      ecData[r][i] = modIndex >= 0 ? modPoly.getAt(modIndex) : 0;
    }
  }

  var totalCodeCount = 0;
  for (var i = 0; i < rsBlocks.length; i += 1) {
    totalCodeCount += rsBlocks[i].totalCount;
  }

  final data = List.generate(totalCodeCount, (index) => 0);
  var index = 0;

  for (var i = 0; i < maxDcCount; i += 1) {
    for (var r = 0; r < rsBlocks.length; r += 1) {
      if (i < dcData[r].length) {
        data[index] = dcData[r][i];
        index += 1;
      }
    }
  }

  for (var i = 0; i < maxEcCount; i += 1) {
    for (var r = 0; r < rsBlocks.length; r += 1) {
      if (i < ecData[r].length) {
        data[index] = ecData[r][i];
        index += 1;
      }
    }
  }

  return data;
}

List<int> _createData(
  int version,
  ErrorCorrectionLevel errorCorrectionLevel,
  Uint8List data,
) {
  final rsBlocks = _QRRSBlock.getRsBlocks(version, errorCorrectionLevel);

  final buffer = _QrBitBuffer();

  buffer.put(4, 4);
  buffer.put(data.length, _QRUtil.getLengthInBits(version));
  buffer.putBytes(data);

  // calc num max data.
  var totalDataCount = 0;
  for (var i = 0; i < rsBlocks.length; i += 1) {
    totalDataCount += rsBlocks[i].dataCount;
  }

  if (buffer.getLengthInBits() > totalDataCount * 8) {
    throw RangeError(
      'code length overflow. (${buffer.getLengthInBits()}>${totalDataCount * 8})',
    );
  }

  // end code
  if (buffer.getLengthInBits() + 4 <= totalDataCount * 8) buffer.put(0, 4);

  // padding
  while (buffer.getLengthInBits() % 8 != 0) {
    buffer.putBit(false);
  }

  // padding
  while (true) {
    if (buffer.getLengthInBits() >= totalDataCount * 8) break;
    buffer.put(_pad0, 8);

    if (buffer.getLengthInBits() >= totalDataCount * 8) break;
    buffer.put(_pad1, 8);
  }

  return _createBytes(buffer, rsBlocks);
}

class _QRUtil {
  static const _patternPositionTable = [
    <int>[],
    [6, 18],
    [6, 22],
    [6, 26],
    [6, 30],
    [6, 34],
    [6, 22, 38],
    [6, 24, 42],
    [6, 26, 46],
    [6, 28, 50],
    [6, 30, 54],
    [6, 32, 58],
    [6, 34, 62],
    [6, 26, 46, 66],
    [6, 26, 48, 70],
    [6, 26, 50, 74],
    [6, 30, 54, 78],
    [6, 30, 56, 82],
    [6, 30, 58, 86],
    [6, 34, 62, 90],
    [6, 28, 50, 72, 94],
    [6, 26, 50, 74, 98],
    [6, 30, 54, 78, 102],
    [6, 28, 54, 80, 106],
    [6, 32, 58, 84, 110],
    [6, 30, 58, 86, 114],
    [6, 34, 62, 90, 118],
    [6, 26, 50, 74, 98, 122],
    [6, 30, 54, 78, 102, 126],
    [6, 26, 52, 78, 104, 130],
    [6, 30, 56, 82, 108, 134],
    [6, 34, 60, 86, 112, 138],
    [6, 30, 58, 86, 114, 142],
    [6, 34, 62, 90, 118, 146],
    [6, 30, 54, 78, 102, 126, 150],
    [6, 24, 50, 76, 102, 128, 154],
    [6, 28, 54, 80, 106, 132, 158],
    [6, 32, 58, 84, 110, 136, 162],
    [6, 26, 54, 82, 110, 138, 166],
    [6, 30, 58, 86, 114, 142, 170]
  ];

  static const _g15 = (1 << 10) |
      (1 << 8) |
      (1 << 5) |
      (1 << 4) |
      (1 << 2) |
      (1 << 1) |
      (1 << 0);
  static const _g18 = (1 << 12) |
      (1 << 11) |
      (1 << 10) |
      (1 << 9) |
      (1 << 8) |
      (1 << 5) |
      (1 << 2) |
      (1 << 0);
  static const _g15Mask =
      (1 << 14) | (1 << 12) | (1 << 10) | (1 << 4) | (1 << 1);

  static int _getBchDigit(int data) {
    var digit = 0;
    while (data != 0) {
      digit += 1;
      data >>>= 1;
    }
    return digit;
  }

  static int getBchTypeInfo(int data) {
    var d = data << 10;
    while (_getBchDigit(d) - _getBchDigit(_g15) >= 0) {
      d ^= _g15 << (_getBchDigit(d) - _getBchDigit(_g15));
    }
    return ((data << 10) | d) ^ _g15Mask;
  }

  static int getBchTypeNumber(int data) {
    var d = data << 12;
    while (_getBchDigit(d) - _getBchDigit(_g18) >= 0) {
      d ^= _g18 << (_getBchDigit(d) - _getBchDigit(_g18));
    }
    return (data << 12) | d;
  }

  static List<int> getPatternPosition(int version) {
    return _patternPositionTable[version - 1];
  }

  static _QrPolynomial getErrorCorrectPolynomial(int errorCorrectLength) {
    var a = _QrPolynomial([1], 0);
    for (var i = 0; i < errorCorrectLength; i += 1) {
      a = a.multiply(_QrPolynomial([1, qrMath.gExp(i)], 0));
    }
    return a;
  }

  static int getLengthInBits(int type) {
    if (1 <= type && type < 10) {
      // 1 - 9
      return 8;
    } else if (type < 27) {
      // 10 - 26
      return 16;
    } else if (type < 41) {
      // 27 - 40
      return 16;
    } else {
      throw RangeError('type:$type');
    }
  }
}

class _QRMath {
  final expTable = List.generate(256, (index) => 0);
  final logTable = List.generate(256, (index) => 0);

  _QRMath() {
    // initialize tables
    for (var i = 0; i < 8; i += 1) {
      expTable[i] = 1 << i;
    }
    for (var i = 8; i < 256; i += 1) {
      expTable[i] =
          expTable[i - 4] ^ expTable[i - 5] ^ expTable[i - 6] ^ expTable[i - 8];
    }
    for (var i = 0; i < 255; i += 1) {
      logTable[expTable[i]] = i;
    }
  }

  int gLog(int n) {
    if (n < 1) throw RangeError('gLog($n)');

    return logTable[n];
  }

  int gExp(int n) {
    while (n < 0) {
      n += 255;
    }

    while (n >= 256) {
      n -= 255;
    }

    return expTable[n];
  }
}

final qrMath = _QRMath();

class _QrPolynomial {
  List<int> _num = [];

  _QrPolynomial(List<int> num, int shift) {
    var offset = 0;
    while (offset < num.length && num[offset] == 0) {
      offset += 1;
    }

    _num = List.generate(num.length - offset + shift, (_) => 0);
    for (var i = 0; i < num.length - offset; i += 1) {
      _num[i] = num[i + offset];
    }
  }

  int getAt(int index) => _num[index];

  int getLength() => _num.length;

  _QrPolynomial multiply(_QrPolynomial e) {
    final num = List.generate(getLength() + e.getLength() - 1, (_) => 0);

    for (var i = 0; i < getLength(); i += 1) {
      for (var j = 0; j < e.getLength(); j += 1) {
        num[i + j] ^=
            qrMath.gExp(qrMath.gLog(getAt(i)) + qrMath.gLog(e.getAt(j)));
      }
    }

    return _QrPolynomial(num, 0);
  }

  _QrPolynomial mod(_QrPolynomial e) {
    if (getLength() - e.getLength() < 0) return this;

    final ratio = qrMath.gLog(getAt(0)) - qrMath.gLog(e.getAt(0));

    final num = List.generate(getLength(), (_) => 0);
    for (var i = 0; i < getLength(); i += 1) {
      num[i] = getAt(i);
    }

    for (var i = 0; i < e.getLength(); i += 1) {
      num[i] ^= qrMath.gExp(qrMath.gLog(e.getAt(i)) + ratio);
    }

    // recursive call
    return _QrPolynomial(num, 0).mod(e);
  }
}

class _QRRSBlock {
  static const _rsBlockTable = [
    // L
    // M
    // Q
    // H

    // 1
    [1, 26, 19],
    [1, 26, 16],
    [1, 26, 13],
    [1, 26, 9],

    // 2
    [1, 44, 34],
    [1, 44, 28],
    [1, 44, 22],
    [1, 44, 16],

    // 3
    [1, 70, 55],
    [1, 70, 44],
    [2, 35, 17],
    [2, 35, 13],

    // 4
    [1, 100, 80],
    [2, 50, 32],
    [2, 50, 24],
    [4, 25, 9],

    // 5
    [1, 134, 108],
    [2, 67, 43],
    [2, 33, 15, 2, 34, 16],
    [2, 33, 11, 2, 34, 12],

    // 6
    [2, 86, 68],
    [4, 43, 27],
    [4, 43, 19],
    [4, 43, 15],

    // 7
    [2, 98, 78],
    [4, 49, 31],
    [2, 32, 14, 4, 33, 15],
    [4, 39, 13, 1, 40, 14],

    // 8
    [2, 121, 97],
    [2, 60, 38, 2, 61, 39],
    [4, 40, 18, 2, 41, 19],
    [4, 40, 14, 2, 41, 15],

    // 9
    [2, 146, 116],
    [3, 58, 36, 2, 59, 37],
    [4, 36, 16, 4, 37, 17],
    [4, 36, 12, 4, 37, 13],

    // 10
    [2, 86, 68, 2, 87, 69],
    [4, 69, 43, 1, 70, 44],
    [6, 43, 19, 2, 44, 20],
    [6, 43, 15, 2, 44, 16],

    // 11
    [4, 101, 81],
    [1, 80, 50, 4, 81, 51],
    [4, 50, 22, 4, 51, 23],
    [3, 36, 12, 8, 37, 13],

    // 12
    [2, 116, 92, 2, 117, 93],
    [6, 58, 36, 2, 59, 37],
    [4, 46, 20, 6, 47, 21],
    [7, 42, 14, 4, 43, 15],

    // 13
    [4, 133, 107],
    [8, 59, 37, 1, 60, 38],
    [8, 44, 20, 4, 45, 21],
    [12, 33, 11, 4, 34, 12],

    // 14
    [3, 145, 115, 1, 146, 116],
    [4, 64, 40, 5, 65, 41],
    [11, 36, 16, 5, 37, 17],
    [11, 36, 12, 5, 37, 13],

    // 15
    [5, 109, 87, 1, 110, 88],
    [5, 65, 41, 5, 66, 42],
    [5, 54, 24, 7, 55, 25],
    [11, 36, 12, 7, 37, 13],

    // 16
    [5, 122, 98, 1, 123, 99],
    [7, 73, 45, 3, 74, 46],
    [15, 43, 19, 2, 44, 20],
    [3, 45, 15, 13, 46, 16],

    // 17
    [1, 135, 107, 5, 136, 108],
    [10, 74, 46, 1, 75, 47],
    [1, 50, 22, 15, 51, 23],
    [2, 42, 14, 17, 43, 15],

    // 18
    [5, 150, 120, 1, 151, 121],
    [9, 69, 43, 4, 70, 44],
    [17, 50, 22, 1, 51, 23],
    [2, 42, 14, 19, 43, 15],

    // 19
    [3, 141, 113, 4, 142, 114],
    [3, 70, 44, 11, 71, 45],
    [17, 47, 21, 4, 48, 22],
    [9, 39, 13, 16, 40, 14],

    // 20
    [3, 135, 107, 5, 136, 108],
    [3, 67, 41, 13, 68, 42],
    [15, 54, 24, 5, 55, 25],
    [15, 43, 15, 10, 44, 16],

    // 21
    [4, 144, 116, 4, 145, 117],
    [17, 68, 42],
    [17, 50, 22, 6, 51, 23],
    [19, 46, 16, 6, 47, 17],

    // 22
    [2, 139, 111, 7, 140, 112],
    [17, 74, 46],
    [7, 54, 24, 16, 55, 25],
    [34, 37, 13],

    // 23
    [4, 151, 121, 5, 152, 122],
    [4, 75, 47, 14, 76, 48],
    [11, 54, 24, 14, 55, 25],
    [16, 45, 15, 14, 46, 16],

    // 24
    [6, 147, 117, 4, 148, 118],
    [6, 73, 45, 14, 74, 46],
    [11, 54, 24, 16, 55, 25],
    [30, 46, 16, 2, 47, 17],

    // 25
    [8, 132, 106, 4, 133, 107],
    [8, 75, 47, 13, 76, 48],
    [7, 54, 24, 22, 55, 25],
    [22, 45, 15, 13, 46, 16],

    // 26
    [10, 142, 114, 2, 143, 115],
    [19, 74, 46, 4, 75, 47],
    [28, 50, 22, 6, 51, 23],
    [33, 46, 16, 4, 47, 17],

    // 27
    [8, 152, 122, 4, 153, 123],
    [22, 73, 45, 3, 74, 46],
    [8, 53, 23, 26, 54, 24],
    [12, 45, 15, 28, 46, 16],

    // 28
    [3, 147, 117, 10, 148, 118],
    [3, 73, 45, 23, 74, 46],
    [4, 54, 24, 31, 55, 25],
    [11, 45, 15, 31, 46, 16],

    // 29
    [7, 146, 116, 7, 147, 117],
    [21, 73, 45, 7, 74, 46],
    [1, 53, 23, 37, 54, 24],
    [19, 45, 15, 26, 46, 16],

    // 30
    [5, 145, 115, 10, 146, 116],
    [19, 75, 47, 10, 76, 48],
    [15, 54, 24, 25, 55, 25],
    [23, 45, 15, 25, 46, 16],

    // 31
    [13, 145, 115, 3, 146, 116],
    [2, 74, 46, 29, 75, 47],
    [42, 54, 24, 1, 55, 25],
    [23, 45, 15, 28, 46, 16],

    // 32
    [17, 145, 115],
    [10, 74, 46, 23, 75, 47],
    [10, 54, 24, 35, 55, 25],
    [19, 45, 15, 35, 46, 16],

    // 33
    [17, 145, 115, 1, 146, 116],
    [14, 74, 46, 21, 75, 47],
    [29, 54, 24, 19, 55, 25],
    [11, 45, 15, 46, 46, 16],

    // 34
    [13, 145, 115, 6, 146, 116],
    [14, 74, 46, 23, 75, 47],
    [44, 54, 24, 7, 55, 25],
    [59, 46, 16, 1, 47, 17],

    // 35
    [12, 151, 121, 7, 152, 122],
    [12, 75, 47, 26, 76, 48],
    [39, 54, 24, 14, 55, 25],
    [22, 45, 15, 41, 46, 16],

    // 36
    [6, 151, 121, 14, 152, 122],
    [6, 75, 47, 34, 76, 48],
    [46, 54, 24, 10, 55, 25],
    [2, 45, 15, 64, 46, 16],

    // 37
    [17, 152, 122, 4, 153, 123],
    [29, 74, 46, 14, 75, 47],
    [49, 54, 24, 10, 55, 25],
    [24, 45, 15, 46, 46, 16],

    // 38
    [4, 152, 122, 18, 153, 123],
    [13, 74, 46, 32, 75, 47],
    [48, 54, 24, 14, 55, 25],
    [42, 45, 15, 32, 46, 16],

    // 39
    [20, 147, 117, 4, 148, 118],
    [40, 75, 47, 7, 76, 48],
    [43, 54, 24, 22, 55, 25],
    [10, 45, 15, 67, 46, 16],

    // 40
    [19, 148, 118, 6, 149, 119],
    [18, 75, 47, 31, 76, 48],
    [34, 54, 24, 34, 55, 25],
    [20, 45, 15, 61, 46, 16]
  ];

  static List<int> _getRsBlockTable(
    int version,
    ErrorCorrectionLevel errorCorrectionLevel,
  ) {
    switch (errorCorrectionLevel) {
      case ErrorCorrectionLevel.L:
        return _rsBlockTable[(version - 1) * 4 + 0];
      case ErrorCorrectionLevel.M:
        return _rsBlockTable[(version - 1) * 4 + 1];
      case ErrorCorrectionLevel.Q:
        return _rsBlockTable[(version - 1) * 4 + 2];
      case ErrorCorrectionLevel.H:
        return _rsBlockTable[(version - 1) * 4 + 3];
    }
  }

  static List<_Rs> getRsBlocks(
    int version,
    ErrorCorrectionLevel errorCorrectionLevel,
  ) {
    final rsBlock = _getRsBlockTable(version, errorCorrectionLevel);

    final length = rsBlock.length / 3;

    final list = <_Rs>[];

    for (var i = 0; i < length; i += 1) {
      final count = rsBlock[i * 3 + 0];
      final totalCount = rsBlock[i * 3 + 1];
      final dataCount = rsBlock[i * 3 + 2];

      for (var j = 0; j < count; j += 1) {
        list.add((totalCount: totalCount, dataCount: dataCount));
      }
    }

    return list;
  }
}

class _QrBitBuffer {
  final _buffer = <int>[];
  var _length = 0;

  List<int> getBuffer() => _buffer;

  void put(int num, int length) {
    for (var i = 0; i < length; i += 1) {
      putBit(((num >>> (length - i - 1)) & 1) == 1);
    }
  }

  int getLengthInBits() => _length;

  void putBit(bool bit) {
    final bufIndex = (_length / 8).floor();
    if (_buffer.length <= bufIndex) {
      _buffer.add(0);
    }

    if (bit) {
      _buffer[bufIndex] |= 0x80 >>> _length % 8;
    }

    _length += 1;
  }

  void putBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i += 1) {
      put(bytes[i], 8);
    }
  }
}
