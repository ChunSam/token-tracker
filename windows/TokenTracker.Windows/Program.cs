using System.Windows.Forms;
using TokenTracker.Windows;

using var singleInstance = new Mutex(
    initiallyOwned: true,
    name: @"Global\TokenTracker.Windows.SingleInstance",
    createdNew: out var createdNew);

if (!createdNew)
{
    return;
}

ApplicationConfiguration.Initialize();
Application.Run(new TrayAppContext());
