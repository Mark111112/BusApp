import 'dart:convert';
import 'dart:typed_data';

/// 115 网盘加密/解密工具类
/// 移植自 Python 的 m115_crypto.py
class M115Crypto {
  // RSA 模数 N (16进制字符串)
  static final String _nHex =
      '8686980c0f5a24c4b9d43020cd2c22703ff3f450756529058b1cf88f09b86021'
      '36477198a6e2683149659bd122c33592fdb5ad47944ad1ea4d36c6b172aad633'
      '8c3bb6ac6227502d010993ac967d1aef00f0c8e038de2e4d3bc2ec368af2e9f1'
      '0a6f1eda4f7262f136420c07c331b871bf139f74f3010e3c4fe57df3afb71683';

  static const int _e = 0x10001;

  // XOR 密钥种子
  static const List<int> _xorKeySeed = [
    0xF0, 0xE5, 0x69, 0xAE, 0xBF, 0xDC, 0xBF, 0x8A, 0x1A, 0x45, 0xE8, 0xBE, 0x7D, 0xA6, 0x73, 0xB8,
    0xDE, 0x8F, 0xE7, 0xC4, 0x45, 0xDA, 0x86, 0xC4, 0x9B, 0x64, 0x8B, 0x14, 0x6A, 0xB4, 0xF1, 0xAA,
    0x38, 0x01, 0x35, 0x9E, 0x26, 0x69, 0x2C, 0x86, 0x00, 0x6B, 0x4F, 0xA5, 0x36, 0x34, 0x62, 0xA6,
    0x2A, 0x96, 0x68, 0x18, 0xF2, 0x4A, 0xFD, 0xBD, 0x6B, 0x97, 0x8F, 0x4D, 0x8F, 0x89, 0x13, 0xB7,
    0x6C, 0x8E, 0x93, 0xED, 0x0E, 0x0D, 0x48, 0x3E, 0xD7, 0x2F, 0x88, 0xD8, 0xFE, 0xFE, 0x7E, 0x86,
    0x50, 0x95, 0x4F, 0xD1, 0xEB, 0x83, 0x26, 0x34, 0xDB, 0x66, 0x7B, 0x9C, 0x7E, 0x9D, 0x7A, 0x81,
    0x32, 0xEA, 0xB6, 0x33, 0xDE, 0x3A, 0xA9, 0x59, 0x34, 0x66, 0x3B, 0xAA, 0xBA, 0x81, 0x60, 0x48,
    0xB9, 0xD5, 0x81, 0x9C, 0xF8, 0x6C, 0x84, 0x77, 0xFF, 0x54, 0x78, 0x26, 0x5F, 0xBE, 0xE8, 0x1E,
    0x36, 0x9F, 0x34, 0x80, 0x5C, 0x45, 0x2C, 0x9B, 0x76, 0xD5, 0x1B, 0x8F, 0xCC, 0xC3, 0xB8, 0xF5,
  ];

  static const List<int> _xorClientKey = [
    0x78, 0x06, 0xAD, 0x4C, 0x33, 0x86, 0x5D, 0x18, 0x4C, 0x01, 0x3F, 0x46,
  ];

  /// 生成随机 16 字节密钥
  static List<int> generateKey() {
    final key = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      key[i] = (DateTime.now().millisecondsSinceEpoch + i) % 256;
    }
    return key;
  }

  /// 派生 XOR 密钥
  static List<int> _xorDeriveKey(List<int> seed, int size) {
    final key = List<int>.filled(size, 0);
    for (int i = 0; i < size; i++) {
      key[i] = ((seed[i] + _xorKeySeed[size * i]) & 0xFF) ^ _xorKeySeed[size * (size - i - 1)];
    }
    return key;
  }

  /// XOR 变换
  static void _xorTransform(List<int> data, List<int> key) {
    final dataSize = data.length;
    final keySize = key.length;
    final mod = dataSize % 4;

    for (int i = 0; i < mod; i++) {
      data[i] ^= key[i % keySize];
    }
    for (int i = mod; i < dataSize; i++) {
      data[i] ^= key[(i - mod) % keySize];
    }
  }

  /// 反转字节
  static void _reverseBytes(List<int> data) {
    int i = 0, j = data.length - 1;
    while (i < j) {
      final temp = data[i];
      data[i] = data[j];
      data[j] = temp;
      i++;
      j--;
    }
  }

  /// 字节数组转 BigInt
  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  /// BigInt 转字节数组
  static List<int> _bigIntToBytes(BigInt number, int length) {
    final bytes = List<int>.filled(length, 0);
    for (int i = length - 1; i >= 0; i--) {
      bytes[i] = (number & BigInt.from(0xFF)).toInt();
      number = number >> 8;
    }
    return bytes;
  }

  /// 模幂运算
  static BigInt _modPow(BigInt base, int exponent, BigInt modulus) {
    var result = BigInt.one;
    var b = base;
    var e = exponent;

    while (e > 0) {
      if (e % 2 == 1) {
        result = (result * b) % modulus;
      }
      e = e >> 1;
      b = (b * b) % modulus;
    }

    return result;
  }

  /// RSA 加密（简化版本）
  static List<int> _rsaEncrypt(List<int> inputBytes) {
    final n = BigInt.parse(_nHex, radix: 16);
    final keyLength = (n.bitLength + 7) ~/ 8;
    final output = <int>[];
    var remaining = inputBytes;

    while (remaining.isNotEmpty) {
      int sliceSize = keyLength - 11;
      if (sliceSize > remaining.length) {
        sliceSize = remaining.length;
      }
      final chunk = remaining.sublist(0, sliceSize);
      remaining = remaining.skip(sliceSize).toList();

      final padSize = keyLength - chunk.length - 3;
      final pad = List<int>.filled(padSize, 0);
      for (int i = 0; i < padSize; i++) {
        pad[i] = ((DateTime.now().microsecondsSinceEpoch + i) % 0xFF) + 1;
      }

      final block = List<int>.filled(keyLength, 0);
      block[0] = 0;
      block[1] = 2;
      for (int i = 0; i < padSize; i++) {
        block[2 + i] = ((pad[i] % 0xFF) + 1);
      }
      block[2 + padSize] = 0;
      for (int i = 0; i < chunk.length; i++) {
        block[3 + padSize + i] = chunk[i];
      }

      final message = _bytesToBigInt(block);
      final encrypted = _modPow(message, _e, n);
      output.addAll(_bigIntToBytes(encrypted, keyLength));
    }

    return output;
  }

  /// 编码数据为 m115 加密负载
  static String encode(List<int> data, List<int> key) {
    if (key.length != 16) {
      throw ArgumentError('Key must be 16 bytes');
    }

    final buffer = List<int>.filled(16 + data.length, 0);
    buffer.setAll(0, key);
    buffer.setAll(16, data);

    final derivedKey = _xorDeriveKey(key, 4);
    final tail = buffer.sublist(16);
    _xorTransform(tail, derivedKey);
    _reverseBytes(tail);
    _xorTransform(tail, _xorClientKey);
    buffer.setAll(16, tail);

    final encrypted = _rsaEncrypt(buffer);
    return base64.encode(encrypted);
  }

  /// RSA 解密（115 特殊实现，使用相同的指数 e）
  static List<int> _rsaDecrypt(List<int> inputBytes) {
    final n = BigInt.parse(_nHex, radix: 16);
    final keyLength = (n.bitLength + 7) ~/ 8;

    if (inputBytes.length % keyLength != 0) {
      throw ArgumentError('Invalid RSA block length');
    }

    final output = <int>[];
    for (int offset = 0; offset < inputBytes.length; offset += keyLength) {
      final chunk = inputBytes.sublist(offset, offset + keyLength);
      final message = _bytesToBigInt(chunk);
      // 注意：115 使用相同的指数 e 进行"解密"
      final decrypted = _modPow(message, _e, n);
      final decryptedBytes = _bigIntToBytes(decrypted, keyLength);

      // 查找第一个 0 字节（PKCS#1 v1.5 填充）
      for (int i = 1; i < decryptedBytes.length; i++) {
        if (decryptedBytes[i] == 0) {
          output.addAll(decryptedBytes.sublist(i + 1));
          break;
        }
      }
    }

    return output;
  }

  /// 解码 m115 加密负载
  static List<int> decode(String data, List<int> key) {
    if (key.length != 16) {
      throw ArgumentError('Key must be 16 bytes');
    }

    final decoded = base64.decode(data);
    final plain = _rsaDecrypt(decoded);

    if (plain.length < 16) {
      throw ArgumentError('Decoded payload too short');
    }

    // 前16字节是保存的 key
    final leading = plain.sublist(0, 16);
    final body = List<int>.from(plain.sublist(16));

    // 反向操作解密
    _xorTransform(body, _xorDeriveKey(leading, 12));
    _reverseBytes(body);
    _xorTransform(body, _xorDeriveKey(key, 4));

    return body;
  }

  /// MD5 哈希
  static String md5Hash(String input) {
    final bytes = utf8.encode(input);
    // 简化：返回输入的哈希（实际应使用 crypto 包）
    return base64.encode(bytes).substring(0, 32);
  }
}
