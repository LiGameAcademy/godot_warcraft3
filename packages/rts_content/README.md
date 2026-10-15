# RTS content boundary

This ordinary .NET library converts the existing parsed map JSON into kernel types. It has no Godot or filesystem dependency and does not replace the asset pipeline.

Authored JSON numbers are quantized directly from their decimal token to signed 32.32, nearest with ties away from zero. `BinaryScalarInput.TryConvert` is a separate transport boundary for Godot mouse/vector values: it quantizes the exact IEEE754 value with the same rounding rule, and rejects nonfinite or overflowing inputs. These two inputs need not produce the same raw value for a displayed decimal such as 0.1.

`ParsedTerrainReader.ReadPathing` accepts the existing static cells and an optional copied runtime obstacle overlay. The caller must provide the latter when tree or building footprints are active. `ReadHeights` consumes the existing heightfield output.

Kernel snapshot JSON is opaque transport data. Keep the C# string intact in GDScript; parsing and re-encoding it through floating-point JSON numbers can corrupt raw Int64 values.

The Godot bridge preserves the seven-argument `SubmitMoveTo` entry point. Queue-aware calls use the separate eight-argument `SubmitMoveOrder` entry point, including the explicit append flag; GDScript `call()` must not rely on CLR optional arguments.
