/**
 * Little-endian binary reader for classic WC3 map files.
 */
export class BufferReader {
  /** @param {Buffer} buffer */
  constructor(buffer) {
    this.buffer = buffer;
    this.offset = 0;
  }

  get remaining() {
    return this.buffer.length - this.offset;
  }

  get eof() {
    return this.offset >= this.buffer.length;
  }

  /** @param {number} n */
  skip(n) {
    this.offset += n;
  }

  /** @param {number} n */
  peekBytes(n) {
    return this.buffer.subarray(this.offset, this.offset + n);
  }

  readUInt8() {
    const v = this.buffer.readUInt8(this.offset);
    this.offset += 1;
    return v;
  }

  readInt8() {
    const v = this.buffer.readInt8(this.offset);
    this.offset += 1;
    return v;
  }

  readUInt16() {
    const v = this.buffer.readUInt16LE(this.offset);
    this.offset += 2;
    return v;
  }

  readInt16() {
    const v = this.buffer.readInt16LE(this.offset);
    this.offset += 2;
    return v;
  }

  readUInt32() {
    const v = this.buffer.readUInt32LE(this.offset);
    this.offset += 4;
    return v;
  }

  readInt32() {
    const v = this.buffer.readInt32LE(this.offset);
    this.offset += 4;
    return v;
  }

  readFloat() {
    const v = this.buffer.readFloatLE(this.offset);
    this.offset += 4;
    return v;
  }

  /** @param {number} n */
  readBytes(n) {
    const slice = this.buffer.subarray(this.offset, this.offset + n);
    this.offset += n;
    return Buffer.from(slice);
  }

  /** 4-char Blizzard ID, preserved as ASCII (may contain non-printable). */
  readFourCC() {
    return this.readBytes(4).toString("latin1");
  }

  /** Null-terminated UTF-8 string. */
  readString() {
    const start = this.offset;
    while (this.offset < this.buffer.length && this.buffer[this.offset] !== 0) {
      this.offset += 1;
    }
    const str = this.buffer.toString("utf8", start, this.offset);
    if (this.offset < this.buffer.length) this.offset += 1; // skip NUL
    return str;
  }
}
