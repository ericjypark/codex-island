using System.Drawing;

namespace IslandPrototype;

internal static class FullscreenGeometry
{
    internal static bool CoversMonitor(Rectangle client,Rectangle monitor)=>client.Width>0&&client.Height>0
        &&monitor.Width>0&&monitor.Height>0&&client.Left<=monitor.Left&&client.Top<=monitor.Top
        &&client.Right>=monitor.Right&&client.Bottom>=monitor.Bottom;
}
