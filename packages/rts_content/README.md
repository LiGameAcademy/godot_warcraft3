# RTS content boundary

This ordinary .NET library converts the existing parsed map JSON into kernel types. It has no Godot or filesystem dependency and does not replace the asset pipeline.

Authored JSON numbers are quantized directly from their decimal token to signed 32.32, nearest with ties away from zero. `BinaryScalarInput.TryConvert` is a separate transport boundary for Godot mouse/vector values: it quantizes the exact IEEE754 value with the same rounding rule, and rejects nonfinite or overflowing inputs. These two inputs need not produce the same raw value for a displayed decimal such as 0.1.

`ParsedTerrainReader.ReadPathing` accepts the existing static cells and an optional copied runtime obstacle overlay. The caller must provide the latter when tree or building footprints are active. `ReadHeights` consumes the existing heightfield output.

Kernel snapshot JSON is opaque transport data. Keep the C# string intact in GDScript; parsing and re-encoding it through floating-point JSON numbers can corrupt raw Int64 values.

The Godot bridge preserves the seven-argument `SubmitMoveTo` entry point. Queue-aware calls use the separate eight-argument `SubmitMoveOrder` entry point, including the explicit append flag; GDScript `call()` must not rely on CLR optional arguments.

## Unit movement and starts

`UnitMovementCatalog` joins the existing `UnitData.records` and `UnitBalance.records` by their case-sensitive unit codes. Printable four-character ASCII codes map to explicit big-endian FourCC definition IDs. Table order does not affect movement content identity.

Currently only `foot` and `horse` with positive movement speed are admitted as ground capabilities. Other movement types and stationary speed markers (`0`, `_`, `-`) are reported as exclusions; unknown codes remain unknown. Supported profiles with invalid positive speed, collision radius or turn rate fail loading instead of receiving defaults. The `isbldg` flag does not discard a moving capability: uprooted ancient profiles with radius 144 are retained. This admits the capability; it does not implement uprooting or building state changes.

Turn rate uses the current kernel revolutions/second contract. This conversion does not claim that original Warcraft III turn-rate units have been verified. `MapStartLocations.Read` reads only `sloc` markers, sorted by unique player IDs 0–9; it does not spawn neutral units or implement placement rules.

The content integration executable accepts optional local asset validation:

```powershell
dotnet run --project tests/kernel -c Release -- --asset-root <existing-assets-directory>
```

The repository contains synthetic fixtures only. Original game assets remain external. The optional Echo Isles checks read static WPM; actual tree/building occupancy must still come from the runtime overlay.
