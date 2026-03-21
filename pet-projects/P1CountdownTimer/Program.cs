// dotnet new console -n CountdownTimer
// dotnet run -- 10

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    // ReSharper disable AccessToDisposedClosure
    cts.Cancel();
    // ReSharper restore AccessToDisposedClosure
};

int? ParseSeconds(string[] args)
{
    if (args.Length > 0
        && int.TryParse(args[0], out int n))
    {
        return n;
    }

    return null;
}

async Task CountDown(int seconds, CancellationTokenSource cancellationTokenSource)
{
    Console.WriteLine($"Counting down from {seconds}s. Press Ctrl+C to cancel.");

    for (int i = seconds; i > 0; i--)
    {
        Console.Write($"\r  {i:000}s remaining...  ");
        try
        {
            await Task.Delay(1000, cancellationTokenSource.Token);
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine("\nCancelled.");
            return;
        }
    }

    Console.Write("\r  0s — ");
    Console.Write("\a"); // BEL character — terminal bell
    Console.ForegroundColor = ConsoleColor.Green;
    Console.WriteLine("Done! ✓           ");
    Console.ResetColor();
}


int seconds = ParseSeconds(args) ?? 10;
await CountDown(seconds, cts);
