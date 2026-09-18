import 'dart:typed_data';

/// A model artifact that has been verified against the exact release identity
/// requested by the local runtime.
class VettedMotionModelArtifact {
  VettedMotionModelArtifact({
    required Uint8List bytes,
    required this.modelVersion,
    required this.sha256,
  }) : bytes = Uint8List.fromList(bytes);

  /// A private copy prevents a caller from changing bytes after verification.
  final Uint8List bytes;
  final String modelVersion;
  final String sha256;
}

/// Verifies downloaded model bytes before they can reach a local detector.
///
/// This is deliberately separate from HTTP and model-engine code. The Worker
/// decides which immutable artifact is production; the app only accepts bytes
/// whose version and digest agree with that decision.
class MotionModelArtifactIntegrity {
  const MotionModelArtifactIntegrity._();

  static VettedMotionModelArtifact verify({
    required String requestedModelVersion,
    required Uint8List bytes,
    required String? artifactModelVersion,
    required String? expectedSha256,
  }) {
    final requested = requestedModelVersion.trim();
    final actualVersion = artifactModelVersion?.trim() ?? '';
    if (requested.isEmpty || actualVersion.isEmpty) {
      throw const MotionModelArtifactIntegrityException(
        'Model version metadata is missing.',
      );
    }
    if (requested != actualVersion) {
      throw const MotionModelArtifactIntegrityException(
        'Model version does not match the requested release.',
      );
    }

    final expected = _normalizeDigest(expectedSha256);
    if (expected == null) {
      throw const MotionModelArtifactIntegrityException(
        'Model checksum metadata is invalid.',
      );
    }
    if (bytes.isEmpty) {
      throw const MotionModelArtifactIntegrityException(
        'Model artifact is empty.',
      );
    }

    final actual = _sha256Hex(bytes);
    if (actual != expected) {
      throw const MotionModelArtifactIntegrityException(
        'Model artifact checksum does not match its release.',
      );
    }

    return VettedMotionModelArtifact(
      bytes: bytes,
      modelVersion: actualVersion,
      sha256: actual,
    );
  }

  static String? _normalizeDigest(String? value) {
    final raw = value?.trim().toLowerCase() ?? '';
    final digest = raw.startsWith('sha256:') ? raw.substring(7) : raw;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ? digest : null;
  }
}

String _sha256Hex(Uint8List input) {
  const initialHash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const roundConstants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedLength);
  padded.setAll(0, input);
  padded[input.length] = 0x80;
  final bitLength = input.length * 8;
  for (var i = 0; i < 8; i++) {
    padded[paddedLength - 1 - i] = (bitLength >> (i * 8)) & 0xff;
  }

  final hash = List<int>.from(initialHash);
  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final index = offset + (i * 4);
      words[i] =
          (padded[index] << 24) |
          (padded[index + 1] << 16) |
          (padded[index + 2] << 8) |
          padded[index + 3];
    }
    for (var i = 16; i < 64; i++) {
      words[i] =
          (_smallSigma1(words[i - 2]) +
              words[i - 7] +
              _smallSigma0(words[i - 15]) +
              words[i - 16]) &
          0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var i = 0; i < 64; i++) {
      final temp1 =
          (h +
              _bigSigma1(e) +
              _choose(e, f, g) +
              roundConstants[i] +
              words[i]) &
          0xffffffff;
      final temp2 = (_bigSigma0(a) + _majority(a, b, c)) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }

  return hash.map((value) => value.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int amount) =>
    ((value >>> amount) | (value << (32 - amount))) & 0xffffffff;

int _smallSigma0(int value) =>
    _rotateRight(value, 7) ^ _rotateRight(value, 18) ^ (value >>> 3);

int _smallSigma1(int value) =>
    _rotateRight(value, 17) ^ _rotateRight(value, 19) ^ (value >>> 10);

int _bigSigma0(int value) =>
    _rotateRight(value, 2) ^ _rotateRight(value, 13) ^ _rotateRight(value, 22);

int _bigSigma1(int value) =>
    _rotateRight(value, 6) ^ _rotateRight(value, 11) ^ _rotateRight(value, 25);

int _choose(int x, int y, int z) => (x & y) ^ (~x & z);

int _majority(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);

class MotionModelArtifactIntegrityException implements Exception {
  const MotionModelArtifactIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'MotionModelArtifactIntegrityException: $message';
}
