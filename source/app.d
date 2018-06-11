import std.stdio;
import std.process;
import std.experimental.logger;
import std.array;
import std.algorithm;
import std.path;
import std.string;
import std.file;
import core.time;
import std.uni;
import std.datetime;

import log;

version (Windows)
{
	import core.sys.windows.wincon;
	import std.system;
}

void createLog()
{
	string logDirPath = buildPath(dirName(thisExePath()), "Log");
	if (!exists(logDirPath) || !isDir(logDirPath))
	{
		info("create dir:", logDirPath);
		mkdirRecurse(logDirPath);
	}
	addConsoleLog(LogLevel.info);
	string logFileName = baseName(thisExePath());
	logFileName = logFileName.endsWith(".exe") ? logFileName.replace(".exe",
			".txt") : logFileName ~ ".txt";
	addFileLog(buildPath(dirName(thisExePath()), "log", logFileName));
}

void main(string[] args)
{
	string childExePath;
	string childExeName;
	string[] childArgs;
	string exeName = baseName(args[0]);
	string postfixName;
	version (Windows)
	{
		postfixName = "_supervisor.exe";
	}
	else
	{
		postfixName = "_supervisor";
	}
	string exeLowName = toLower(exeName);
	ptrdiff_t index = indexOf(exeLowName, "_supervisor.exe");
	if (index != -1)
	{
		childExeName = exeName[0 .. index];
		version (Windows)
		{
			childExeName ~= ".exe";
		}
		childExePath = buildPath(dirName(thisExePath()), childExeName);
	}
	if (childExeName.length == 0)
	{
		if (args.length == 1)
		{
			warning("invalid argument, should like ", exeName, " $exe $exeArg1 .. $exeArgN");
			return;
		}
		childExePath = args[1];
		version (linux)
		{
			if (indexOf(childExePath, "/") == -1)
			{
				childExePath = buildPath(dirName(thisExePath()), childExePath);
			}
		}
		childArgs ~= childExePath;
		if (args.length > 2)
		{
			childArgs ~= args[2 .. $];
		}

	}
	else
	{
		childArgs ~= childExePath;
		if (args.length > 1)
		{
			childArgs ~= args[1 .. $];
		}
	}

	info("child exe path:", childExePath);

	if (!std.file.exists(childExePath))
	{
		warning("child exe not exist");
		return;
	}
	else if (std.file.isDir(childExePath))
	{
		warning("child exe is directory");
		return;
	}

	createLog();
	info("Supervisor: Self ProcessID:", thisProcessID());

	version (Windows)
	{
		string consoleTitle = childExePath;
		SetConsoleTitleA(consoleTitle.toStringz());
	}
	string cmd = join(childArgs, " ");
	while (true)
	{
		info("Supervisor: start child process:", cmd);
		MonoTime before = MonoTime.currTime;

		auto pid = spawnProcess(childArgs, std.stdio.stdin, std.stdio.stdout, std.stdio.stdout);
		info("Supervisor: child process pid:", pid.processID);
		info("Supervisor: wait child pid start");
		wait(pid);
		info("Supervisor: wait child pid end");

		MonoTime after = MonoTime.currTime;
		Duration timeElapsed = after - before;
		if (timeElapsed.total!"seconds"() < 3)
		{
			warning("Supervisor: process end two quick");
			break;
		}
	}

}
