using Rts.Content;

if (args.Length == 2 && args[0] == "--map")
{
    var pathing = ParsedTerrainReader.ReadPathing(File.ReadAllText(Path.Combine(args[1], "pathing.json")));
    var heights = ParsedTerrainReader.ReadHeights(File.ReadAllText(Path.Combine(args[1], "terrain-heightfield.json")));
    Console.WriteLine($"terrain loaded: pathing={pathing.Width}x{pathing.Height} cell={pathing.CellSize} heights={heights.Width}x{heights.Height} tile={heights.TileSize}; raw static terrain only");
    return;
}

Console.Error.WriteLine("Usage: --map <parsed-map-directory>; standalone simulation sample is in external/rts_kernel/samples");
Environment.ExitCode = 1;
