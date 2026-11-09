// Deterministic stand-in executables for testing the complete Windows launcher.
// This fixture never communicates with a device or a network service.
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;

public static class Tr4mpassAppleToolFixture
{
    private const string One = "00008030-0000000000000001";
    private const string Two = "00008030-0000000000000002";

    public static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string tool = Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
        string scenario = File.ReadAllText(Path.Combine(root, "scenario.txt")).Trim();
        File.AppendAllText(Path.Combine(root, "calls.log"), tool + "|" + String.Join("|", args) + Environment.NewLine);
        if (args.Length == 1 && args[0] == "--version")
        {
            if (scenario == "broken-runtime") return 9;
            Console.WriteLine(tool + " test-fixture");
            return 0;
        }
        if (args.Length == 1 && args[0] == "--hang") { Thread.Sleep(5000); return 0; }
        if (tool == "idevice_id")
        {
            if (scenario == "enumeration-error") return 3;
            if (scenario == "no-device") return 0;
            if (scenario == "connect-later")
            {
                string seen = Path.Combine(root, "enumerated.txt");
                if (!File.Exists(seen)) { File.WriteAllText(seen, "1"); return 0; }
            }
            Console.WriteLine(One);
            if (scenario == "multiple") Console.WriteLine(Two);
            return 0;
        }
        if (tool == "ideviceinfo")
        {
            if (args.Length != 5 || args[0] != "-s" || args[1] != "-u" || args[3] != "-k") return 10;
            if (args[2] != One && args[2] != Two) return 11;
            if (scenario == "info-error") return 4;
            if (scenario == "transient-info")
            {
                string seen = Path.Combine(root, "info-seen.txt");
                if (!File.Exists(seen)) { File.WriteAllText(seen, "1"); return 4; }
            }
            switch (args[4])
            {
                case "ProductType": Console.WriteLine("iPhone14,3"); break;
                case "ProductVersion": Console.WriteLine("18.1"); break;
                case "HardwareModel": Console.WriteLine("D64AP"); break;
                case "ActivationState":
                    if (File.Exists(Path.Combine(root, "activated.txt")) && scenario == "delayed-verification")
                    {
                        string seen = Path.Combine(root, "verification-seen.txt");
                        if (!File.Exists(seen)) { File.WriteAllText(seen, "1"); return 4; }
                    }
                    Console.WriteLine(File.ReadAllText(Path.Combine(root, "state.txt")).Trim());
                    break;
                default: return 12;
            }
            return 0;
        }
        if (tool == "ideviceactivation")
        {
            if (args.Length != 3 || args[0] != "activate" || args[1] != "-u") return 13;
            if (scenario == "activation-rejected") return 5;
            File.WriteAllText(Path.Combine(root, "activated.txt"), "1");
            if (scenario != "unverified") File.WriteAllText(Path.Combine(root, "state.txt"), "Activated");
            return 0;
        }
        return 14;
    }
}
