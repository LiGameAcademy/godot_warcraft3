/** Minimal mat4 / quat helpers for WC3 node evaluation (column-major). */

export function mat4Identity(out = new Float32Array(16)) {
  out.set([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  return out;
}

export function mat4Multiply(out, a, b) {
  const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  const a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  const a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  const a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];

  let b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3];
  out[0] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[1] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[2] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[3] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

  b0 = b[4]; b1 = b[5]; b2 = b[6]; b3 = b[7];
  out[4] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[5] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[6] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[7] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

  b0 = b[8]; b1 = b[9]; b2 = b[10]; b3 = b[11];
  out[8] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[9] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[10] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[11] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

  b0 = b[12]; b1 = b[13]; b2 = b[14]; b3 = b[15];
  out[12] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[13] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[14] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[15] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  return out;
}

/** Rotation around origin `pivot` then translation (WC3 node local). */
export function mat4FromRotationTranslationScaleOrigin(out, q, v, s, pivot) {
  const x = q[0], y = q[1], z = q[2], w = q[3];
  const x2 = x + x, y2 = y + y, z2 = z + z;
  const xx = x * x2, xy = x * y2, xz = x * z2;
  const yy = y * y2, yz = y * z2, zz = z * z2;
  const wx = w * x2, wy = w * y2, wz = w * z2;
  const sx = s[0], sy = s[1], sz = s[2];

  out[0] = (1 - (yy + zz)) * sx;
  out[1] = (xy + wz) * sx;
  out[2] = (xz - wy) * sx;
  out[3] = 0;
  out[4] = (xy - wz) * sy;
  out[5] = (1 - (xx + zz)) * sy;
  out[6] = (yz + wx) * sy;
  out[7] = 0;
  out[8] = (xz + wy) * sz;
  out[9] = (yz - wx) * sz;
  out[10] = (1 - (xx + yy)) * sz;
  out[11] = 0;
  out[12] = v[0] + pivot[0] - (out[0] * pivot[0] + out[4] * pivot[1] + out[8] * pivot[2]);
  out[13] = v[1] + pivot[1] - (out[1] * pivot[0] + out[5] * pivot[1] + out[9] * pivot[2]);
  out[14] = v[2] + pivot[2] - (out[2] * pivot[0] + out[6] * pivot[1] + out[10] * pivot[2]);
  out[15] = 1;
  return out;
}

export function mat4DecomposeTRS(m) {
  const t = [m[12], m[13], m[14]];
  const sx = Math.hypot(m[0], m[1], m[2]) || 1;
  const sy = Math.hypot(m[4], m[5], m[6]) || 1;
  const sz = Math.hypot(m[8], m[9], m[10]) || 1;
  const s = [sx, sy, sz];
  const r00 = m[0] / sx, r01 = m[4] / sy, r02 = m[8] / sz;
  const r10 = m[1] / sx, r11 = m[5] / sy, r12 = m[9] / sz;
  const r20 = m[2] / sx, r21 = m[6] / sy, r22 = m[10] / sz;
  const trace = r00 + r11 + r22;
  let qw, qx, qy, qz;
  if (trace > 0) {
    const a = Math.sqrt(trace + 1) * 2;
    qw = 0.25 * a;
    qx = (r21 - r12) / a;
    qy = (r02 - r20) / a;
    qz = (r10 - r01) / a;
  } else if (r00 > r11 && r00 > r22) {
    const a = Math.sqrt(1 + r00 - r11 - r22) * 2;
    qw = (r21 - r12) / a;
    qx = 0.25 * a;
    qy = (r01 + r10) / a;
    qz = (r02 + r20) / a;
  } else if (r11 > r22) {
    const a = Math.sqrt(1 + r11 - r00 - r22) * 2;
    qw = (r02 - r20) / a;
    qx = (r01 + r10) / a;
    qy = 0.25 * a;
    qz = (r12 + r21) / a;
  } else {
    const a = Math.sqrt(1 + r22 - r00 - r11) * 2;
    qw = (r10 - r01) / a;
    qx = (r02 + r20) / a;
    qy = (r12 + r21) / a;
    qz = 0.25 * a;
  }
  return { t, r: [qx, qy, qz, qw], s };
}

/** Invert affine mat4 (column-major). Returns null if singular. */
export function mat4Invert(out, m) {
  const a00 = m[0], a01 = m[1], a02 = m[2];
  const a10 = m[4], a11 = m[5], a12 = m[6];
  const a20 = m[8], a21 = m[9], a22 = m[10];
  const a30 = m[12], a31 = m[13], a32 = m[14];
  const b01 = a22 * a11 - a12 * a21;
  const b11 = -a22 * a10 + a12 * a20;
  const b21 = a21 * a10 - a11 * a20;
  let det = a00 * b01 + a01 * b11 + a02 * b21;
  if (Math.abs(det) < 1e-12) return null;
  det = 1 / det;
  out[0] = b01 * det;
  out[1] = (-a22 * a01 + a02 * a21) * det;
  out[2] = (a12 * a01 - a02 * a11) * det;
  out[3] = 0;
  out[4] = b11 * det;
  out[5] = (a22 * a00 - a02 * a20) * det;
  out[6] = (-a12 * a00 + a02 * a10) * det;
  out[7] = 0;
  out[8] = b21 * det;
  out[9] = (-a21 * a00 + a01 * a20) * det;
  out[10] = (a11 * a00 - a01 * a10) * det;
  out[11] = 0;
  out[12] = (-a30 * out[0] - a31 * out[4] - a32 * out[8]);
  out[13] = (-a30 * out[1] - a31 * out[5] - a32 * out[9]);
  out[14] = (-a30 * out[2] - a31 * out[6] - a32 * out[10]);
  out[15] = 1;
  return out;
}

/** Transform WC3 vec3 to glTF/Y-up: (x,y,z)->(x,z,-y) */
export function wc3ToGltfVec3(x, y, z) {
  return [x, z, -y];
}

/** Transform WC3 quat to glTF/Y-up by rotating imag part. */
export function wc3ToGltfQuat(x, y, z, w) {
  return [x, z, -y, w];
}
