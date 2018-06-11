module log;
import std.stdio;
public import std.experimental.logger;
import std.range;
import std.datetime;
import std.path;
import std.traits;
import std.format;
import std.string;
import std.file;
import std.conv;
import std.algorithm.comparison;
import core.thread;
import std.concurrency;

class MyConsoleLogger : Logger
{
    this(LogLevel logLevel)
    {
        super(logLevel);
    }

    protected override @safe void writeLogMsg(ref LogEntry payload)
    {
        const auto dt = cast(DateTime) payload.timestamp;
        const auto fsec = payload.timestamp.fracSecs.total!"msecs";
        writefln("%d-%02d-%02dT%02d:%02d:%02d.%03d %s %s", dt.year, dt.month,
                dt.day, dt.hour, dt.minute, dt.second, fsec, payload.logLevel, payload.msg);
        //writeln(payload.timestamp, " ", payload.msg);
    }
}

class MyFileLogger : FileLogger
{
    private ulong charactersWritten;
    private string filePath;
    private string fileNameWithOutExt;
    private string extName;
    private string dirPath;
    private ulong maxLogFileId;
    private FileLogSetting logSetting;

    this(in string filePath, FileLogSetting logSetting)
    {
        this.logSetting = logSetting;
        this.filePath = filePath;
        this.dirPath = dirName(this.filePath);
        this.fileNameWithOutExt = stripExtension(baseName(this.filePath));
        this.extName = extension(baseName(this.filePath));
        if (!exists(this.dirPath))
        {
            mkdirRecurse(this.dirPath);
        }

        try
        {
            foreach (DirEntry item; dirEntries(this.dirPath, SpanMode.depth))
            {
                try
                {
                    string logFileName = baseName(item.name);
                    string s1;
                    ulong id;
                    string s2;
                    logFileName.formattedRead("%s_%d%s", s1, id, s2);
                    this.maxLogFileId = max(this.maxLogFileId, id);
                }
                catch (Exception e)
                {
                    continue;
                }
            }
        }
        catch (Exception e)
        {
            writeln(e.message());
        }

        super(this.filePath, this.logSetting.level);
        this.charactersWritten = this.file_.size();
    }

    /* This method overrides the base class method in order to log to a file
       without requiring heap allocated memory. Additionally, the $(D FileLogger)
       local mutex is logged to serialize the log calls.
     */
    override protected void beginLogMsg(string file, int line, string funcName, string prettyFuncName,
            string moduleName, LogLevel logLevel, Tid threadId, SysTime timestamp, Logger logger) @safe
    {
        import std.string : lastIndexOf;

        ptrdiff_t fnIdx = file.lastIndexOf(dirSeparator) + 1;
        ptrdiff_t funIdx = funcName.lastIndexOf('.') + 1;

        const auto dt = cast(DateTime) timestamp;
        const auto fsec = timestamp.fracSecs.total!"msecs";

        auto buf = appender!string();
        formattedWrite(buf, "%d-%02d-%02dT%02d:%02d:%02d.%03d %s %u %s_%u: ",
                dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, fsec,
                logLevel, Thread.getThis().id(), file[fnIdx .. $], line);
        this.file_.lockingTextWriter().put(buf.data);
        charactersWritten += buf.data().length;
    }

    /* This methods overrides the base class method and writes the parts of
       the log call directly to the file.
     */
    override protected void logMsgPart(scope const(char)[] msg)
    {
        charactersWritten += msg.length;
        formattedWrite(this.file_.lockingTextWriter(), "%s", msg);
    }
    /* This methods overrides the base class method and finalizes the active
       log call. This requires flushing the $(D File) and releasing the
       $(D FileLogger) local mutex.
     */
    override protected void finishLogMsg()
    {
        charactersWritten += 1;
        this.file_.lockingTextWriter().put("\n");
        if (this.logSetting.atuoFlush)
            this.file_.flush();
        if (this.charactersWritten > this.logSetting.maxByteSize)
        {
            this.maxLogFileId += 1;
            string newFilePath = buildPath(this.dirPath,
                    this.fileNameWithOutExt ~ "_" ~ to!string(this.maxLogFileId) ~ this.extName);
            this.file_.close();
            rename(filePath, newFilePath);
            this.file_.open(this.filePath, "a");
            this.charactersWritten = 0;
            if (this.maxLogFileId > this.logSetting.maxFileCount)
            {
                ulong toRemoveLogFileId = this.maxLogFileId - 3;
                while (true)
                {
                    string toRemoveLogFilePath = buildPath(this.dirPath,
                            this.fileNameWithOutExt ~ "_" ~ to!string(
                                toRemoveLogFileId) ~ this.extName);
                    if (exists(toRemoveLogFilePath))
                    {
                        remove(toRemoveLogFilePath);
                        toRemoveLogFileId -= 1;
                    }
                    else
                    {
                        break;
                    }
                }
            }
        }
    }

}

__gshared MultiLogger gMultiLog;
__gshared MyFileLogger gMyFileLogger;
__gshared MyConsoleLogger gMyConsoleLogger;

shared static this()
{
    sharedLog = gMultiLog = new MultiLogger;
}

struct FileLogSetting
{
    LogLevel level = LogLevel.info;
    ulong maxByteSize = 100 * 1024 * 1024;
    int maxFileCount = 3;
    bool atuoFlush = true;
}

FileLogSetting defaultFileLogSetting;

void addFileLog(string logFilePath, FileLogSetting logSetting = defaultFileLogSetting)
{
    gMyFileLogger = new MyFileLogger(logFilePath, logSetting);
    gMultiLog.insertLogger("fileLog", gMyFileLogger);
}

void setFileLogLevel(LogLevel level)
{
    gMultiLog.logLevel = level;
}

void addConsoleLog(LogLevel level = LogLevel.info)
{
    gMyConsoleLogger = new MyConsoleLogger(level);
    gMultiLog.insertLogger("consoleLog", gMyConsoleLogger);
}

void setConsoleLogLevel(LogLevel level)
{
    gMultiLog.logLevel = level;
}
