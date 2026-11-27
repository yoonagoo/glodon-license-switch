
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("广联达与 Virbox 开关")]
[assembly: AssemblyDescription("下载并启动最新版的广联达与 Virbox 开关")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

internal static class Launcher
{
    private const string ResourceName = "GlodonLicenseSwitch.Launcher.cmd";

    private static int Main(string[] args)
    {
        bool statusOnly = args.Length == 1 && args[0] == "--status";
        string folder = Path.Combine(Path.GetTempPath(), "GlodonLauncher-" + Guid.NewGuid().ToString("N"));
        string launcherPath = Path.Combine(folder, "launcher.cmd");

        try
        {
            Directory.CreateDirectory(folder);
            using (Stream input = typeof(Launcher).Assembly.GetManifestResourceStream(ResourceName))
            using (FileStream output = new FileStream(launcherPath, FileMode.CreateNew))
            {
                if (input == null)
                    throw new InvalidOperationException("启动器缺少内置的 CMD 脚本。");

                input.CopyTo(output);
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                Arguments = statusOnly ? "/d /c launcher.cmd --status" : "/d /c launcher.cmd",
                WorkingDirectory = folder,
                UseShellExecute = false
            };
            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("启动失败：{0}", error.Message);
            if (!statusOnly && !Console.IsInputRedirected)
            {
                Console.Error.WriteLine("按任意键退出。");
                Console.ReadKey(true);
            }
            return 1;
        }
        finally
        {
            try
            {
                File.Delete(launcherPath);
                if (Directory.Exists(folder))
                    Directory.Delete(folder);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
