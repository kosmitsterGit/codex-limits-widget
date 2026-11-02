using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

public sealed class LimitsBackend : IDisposable {
    private Process process;
    private int sequence = 1;
    private readonly string executable;
    private readonly string home;
    public LimitsBackend(string executable, string home) { this.executable = executable; this.home = home; }
    private string ReadResponse(int id) {
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (DateTime.UtcNow < deadline) {
            var read = process.StandardOutput.ReadLineAsync();
            if (!read.Wait(Math.Max(1, (int)(deadline - DateTime.UtcNow).TotalMilliseconds)))
                throw new TimeoutException("Codex did not respond within 30 seconds.");
            string line = read.Result;
            if (line == null) throw new IOException("The Codex connection was closed.");
            // JSON is parsed by PowerShell; only match the numeric response id here.
            if (System.Text.RegularExpressions.Regex.IsMatch(line, "\"id\"\\s*:\\s*" + id + "\\s*[,}]")) return line;
        }
        throw new TimeoutException("The Codex request timed out.");
    }
    private void Send(string message) { process.StandardInput.WriteLine(message); process.StandardInput.Flush(); }
    private void Connect() {
        if (process != null && !process.HasExited) return;
        var start = new ProcessStartInfo(executable, "app-server --stdio") {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
            StandardErrorEncoding = System.Text.Encoding.UTF8
        };
        start.EnvironmentVariables["CODEX_HOME"] = home;
        start.EnvironmentVariables["HOME"] = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        process = new Process { StartInfo = start };
        process.ErrorDataReceived += (s,e) => { }; // Drain logs without retaining private data.
        process.Start();
        process.BeginErrorReadLine();
        Send("{\"id\":0,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex_limits_widget\",\"title\":\"Codex Limits\",\"version\":\"1.0.0\"}}}");
        string init = ReadResponse(0);
        if (init.Contains("\"error\"")) throw new IOException("Codex rejected the widget connection.");
        Send("{\"method\":\"initialized\"}");
    }
    public Task<string> FetchAsync() {
        return Task.Run(() => {
            try {
                Connect();
                int id = sequence++;
                Send("{\"id\":" + id + ",\"method\":\"account/rateLimits/read\"}");
                return ReadResponse(id);
            } catch { Dispose(); throw; }
        });
    }
    public void Dispose() {
        if (process == null) return;
        try { if (!process.HasExited) process.Kill(); } catch { }
        process.Dispose(); process = null;
    }
}
