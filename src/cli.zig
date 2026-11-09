const builtin = @import("builtin");
const is_windows = builtin.target.os.tag == .windows;

const std = @import("std");
const process = std.process;

/// Prints the error message to stderr and terminates process with exit code `1`.
///
/// On Windows, in absence of parent process, waits for user input giving a chance
/// for the user to notice the error message.
pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);

    if (is_windows) windows.waitForInputIfLastProcess();
    process.exit(1);
}

const windows = struct {
    const w = std.os.windows;

    extern "kernel32" fn GetConsoleProcessList([*]w.DWORD, w.DWORD) callconv(.winapi) w.DWORD;

    const exit_message = "Press any key to exit...\n";

    fn waitForInputIfLastProcess() void {
        var process_list_buffer: [1]w.DWORD = undefined;
        const process_count = GetConsoleProcessList(
            &process_list_buffer,
            @intCast(process_list_buffer.len),
        );

        // In case `process_list_buffer` capacity was not enough, it'll return
        // the real amount of processes anyway, so that we could check and retry
        // the call. However, we don't really need it, since all we want is the
        // process count itself.
        // process_count=1 means that this process doesn't have a parent (such as cmd.exe).
        // process_count=0 indicates a `GetConsoleProcessList` failure, in which case,
        // we will still wait for input just in case.
        // Otherwise, there is a parent process and we exit immediately.
        if (process_count > 1) return;

        // Since this function is fairly low-level anyway,
        // perform stdin and stderr operations without `std.Io` integration.
        var iosb: w.IO_STATUS_BLOCK = undefined;
        _ = w.ntdll.NtWriteFile(
            std.Io.File.stderr().handle,
            null, // Event
            null, // ApcRoutine
            null, // ApcContext
            &iosb,
            exit_message.ptr,
            @intCast(exit_message.len),
            null, // ByteOffset
            null, // Key
        );

        var read_buffer: [1]u8 = undefined;
        _ = w.ntdll.NtReadFile(
            std.Io.File.stdin().handle,
            null, // Event
            null, // ApcRoutine
            null, // ApcContext
            &iosb,
            &read_buffer,
            @intCast(read_buffer.len),
            null, // ByteOffset
            null, // Key
        );
    }
};
